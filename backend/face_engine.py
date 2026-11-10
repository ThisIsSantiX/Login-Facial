"""Motor de reconocimiento facial ligero basado en OpenCV (YuNet + SFace).

YuNet detecta el rostro (~230 KB) y SFace genera un vector de 128 valores
(~37 MB). Ambos corren en CPU sin GPU, así que el teléfono solo envía una foto
pequeña y todo el trabajo pesado se hace aquí.

MiniFASNet (~1.8 MB, dos modelos) detecta fotos impresas y pantallas.
"""
import logging
import os
from dataclasses import dataclass
from pathlib import Path

import cv2
import numpy as np

log = logging.getLogger("uvicorn.error")


def _fmt(value: float | None) -> str:
    return "-" if value is None else f"{value:.2f}"


MODELS_DIR = Path(__file__).parent / "models"
DETECTOR_PATH = MODELS_DIR / "face_detection_yunet_2023mar.onnx"
RECOGNIZER_PATH = MODELS_DIR / "face_recognition_sface_2021dec.onnx"
# Modelo anti-suplantación -> escala del recorte alrededor de la cara.
ANTISPOOF_MODELS = {
    MODELS_DIR / "antispoof_2.7_80x80_MiniFASNetV2.onnx": 2.7,
    MODELS_DIR / "antispoof_4_0_0_80x80_MiniFASNetV1SE.onnx": 4.0,
}
# Solo para desarrollo: FACE_ANTISPOOF=off desactiva el modelo anti-suplantación.
ANTISPOOF_ENABLED = os.environ.get("FACE_ANTISPOOF", "on") != "off"
# Probabilidad mínima de "cara real" (promedio de los dos modelos).
MIN_REAL_SCORE = 0.6

# Umbral recomendado por OpenCV para similitud coseno con SFace.
COSINE_THRESHOLD = 0.363
# Tamaño máximo al que se reduce la imagen antes de detectar.
MAX_SIDE = 640
# El rostro debe ocupar al menos esta fracción del ancho de la foto.
MIN_FACE_RATIO = 0.18

# Prueba de vida: se piden dos fotos, una de frente y otra con la cabeza girada.
#
# En una cara real la nariz sobresale del plano que forman ojos y comisuras de
# la boca. Al girar la cabeza, la nariz se desplaza de una forma que ninguna
# imagen plana (foto impresa, pantalla) puede imitar, por mucho que se incline:
# los puntos de una imagen plana siempre se relacionan por una homografía.
# Se calcula la homografía con ojos y boca, se predice dónde debería quedar la
# nariz si la cara fuera plana y se mide el error (paralaje), en proporción a
# la distancia entre los ojos.
MIN_YAW_CHANGE = 0.20
MIN_PARALLAX = 0.10
# Umbral algo más bajo que COSINE_THRESHOLD porque la cara girada se parece
# menos a la de frente, aunque sea la misma persona.
SAME_PERSON_THRESHOLD = 0.30


class FaceError(Exception):
    """Error comprensible para el usuario (sin rostro, varios rostros, etc.)."""


class LivenessError(FaceError):
    """Las fotos no demuestran que haya una persona real frente a la cámara."""


@dataclass
class FaceSample:
    vector: np.ndarray
    # Probabilidad de que sea una cara real (None si el anti-spoofing está apagado).
    real_score: float | None
    # Puntos de YuNet: ojo der., ojo izq., nariz, boca der., boca izq.
    landmarks: np.ndarray

    @property
    def eye_distance(self) -> float:
        return float(np.linalg.norm(self.landmarks[1] - self.landmarks[0]))

    @property
    def yaw(self) -> float:
        """Giro horizontal: 0 es de frente; ~0.3 o más, claramente girada."""
        right_eye, left_eye, nose = self.landmarks[:3]
        axis = (left_eye - right_eye) / self.eye_distance
        middle = (left_eye + right_eye) / 2
        # Proyección sobre el eje de los ojos: no influye si la cabeza está ladeada.
        return float(np.dot(nose - middle, axis) / self.eye_distance)


def parallax(front: FaceSample, turned: FaceSample) -> float:
    """Cuánto se aleja la nariz de donde estaría si la cara fuera plana."""
    plane = [0, 1, 3, 4]  # ojos y comisuras de la boca
    h = cv2.getPerspectiveTransform(
        front.landmarks[plane].astype(np.float32),
        turned.landmarks[plane].astype(np.float32),
    )
    predicted = cv2.perspectiveTransform(
        front.landmarks[2].reshape(1, 1, 2).astype(np.float32), h
    )[0, 0]
    return float(np.linalg.norm(predicted - turned.landmarks[2]) / turned.eye_distance)


def crop_around(img: np.ndarray, box: np.ndarray, scale: float) -> np.ndarray:
    """Recorte cuadrado-proporcional alrededor de la cara, como en el entrenamiento
    de MiniFASNet: se agranda la caja `scale` veces y se desplaza para no salirse."""
    h, w = img.shape[:2]
    x, y, bw, bh = box
    scale = min((h - 1) / bh, (w - 1) / bw, scale)
    nw, nh = bw * scale, bh * scale
    cx, cy = x + bw / 2, y + bh / 2
    left = min(max(cx - nw / 2, 0), w - 1 - nw)
    top = min(max(cy - nh / 2, 0), h - 1 - nh)
    crop = img[int(top) : int(top + nh) + 1, int(left) : int(left + nw) + 1]
    return cv2.resize(crop, (80, 80))


class FaceEngine:
    def __init__(self) -> None:
        for path in (DETECTOR_PATH, RECOGNIZER_PATH):
            if not path.exists():
                raise RuntimeError(
                    f"Falta el modelo {path.name}. Ejecuta: python download_models.py"
                )
        self.detector = cv2.FaceDetectorYN.create(
            str(DETECTOR_PATH), "", (320, 320), score_threshold=0.8
        )
        self.recognizer = cv2.FaceRecognizerSF.create(str(RECOGNIZER_PATH), "")
        self.antispoof = []
        if ANTISPOOF_ENABLED:
            for path, scale in ANTISPOOF_MODELS.items():
                if not path.exists():
                    raise RuntimeError(
                        f"Falta el modelo {path.name}. "
                        "Ejecuta: python tools/export_antispoof.py <repo>"
                    )
                self.antispoof.append((cv2.dnn.readNetFromONNX(str(path)), scale))

    def real_score(self, img: np.ndarray, box: np.ndarray) -> float | None:
        if not self.antispoof:
            return None
        total = 0.0
        for net, scale in self.antispoof:
            # El modelo espera BGR con valores 0-255, sin normalizar.
            blob = crop_around(img, box, scale).astype(np.float32)
            net.setInput(blob.transpose(2, 0, 1)[np.newaxis])
            logits = net.forward()[0]
            probs = np.exp(logits - logits.max())
            total += float(probs[1] / probs.sum())  # clase 1 = cara real
        return total / len(self.antispoof)

    @staticmethod
    def _decode(image_bytes: bytes) -> np.ndarray:
        data = np.frombuffer(image_bytes, dtype=np.uint8)
        img = cv2.imdecode(data, cv2.IMREAD_COLOR)
        if img is None:
            raise FaceError("La imagen no es válida.")
        h, w = img.shape[:2]
        scale = MAX_SIDE / max(h, w)
        if scale < 1:
            img = cv2.resize(img, (int(w * scale), int(h * scale)))
        return img

    def analyze(self, image_bytes: bytes) -> FaceSample:
        img = self._decode(image_bytes)
        h, w = img.shape[:2]
        self.detector.setInputSize((w, h))
        _, faces = self.detector.detect(img)

        if faces is None or len(faces) == 0:
            raise FaceError("No se detectó ningún rostro. Busca mejor luz.")
        if len(faces) > 1:
            raise FaceError("Hay más de un rostro en la foto.")

        face = faces[0]
        if face[2] < w * MIN_FACE_RATIO:
            raise FaceError("Acerca más el rostro a la cámara.")

        aligned = self.recognizer.alignCrop(img, face)
        feature = self.recognizer.feature(aligned)
        sample = FaceSample(
            feature.astype(np.float32).flatten(),
            self.real_score(img, face[:4]),
            face[4:14].reshape(5, 2),
        )
        if sample.eye_distance < 1:
            raise FaceError("No se distinguen bien los ojos.")
        return sample

    def check_liveness(self, front: FaceSample, turned: FaceSample) -> None:
        # Valores de cada control en el log, para calibrar los umbrales.
        log.info(
            "prueba de vida: real=%s/%s giro=%.2f paralaje=%.3f misma_persona=%.2f",
            _fmt(front.real_score),
            _fmt(turned.real_score),
            abs(turned.yaw - front.yaw),
            parallax(front, turned),
            self.similarity(front.vector, turned.vector),
        )
        for sample in (front, turned):
            if sample.real_score is not None and sample.real_score < MIN_REAL_SCORE:
                raise LivenessError(
                    "Parece una foto o una pantalla. Usa tu rostro real."
                )
        if abs(turned.yaw - front.yaw) < MIN_YAW_CHANGE:
            raise LivenessError("En la segunda foto gira más la cabeza hacia un lado.")
        if parallax(front, turned) < MIN_PARALLAX:
            raise LivenessError("No se pudo comprobar que eres una persona real.")
        if self.similarity(front.vector, turned.vector) < SAME_PERSON_THRESHOLD:
            raise LivenessError("Las dos fotos deben ser de la misma persona.")

    def similarity(self, a: np.ndarray, b: np.ndarray) -> float:
        return float(
            self.recognizer.match(
                a.reshape(1, -1), b.reshape(1, -1), cv2.FaceRecognizerSF_FR_COSINE
            )
        )

    def is_match(self, a: np.ndarray, b: np.ndarray) -> tuple[bool, float]:
        score = self.similarity(a, b)
        return score >= COSINE_THRESHOLD, score
