"""Pruebas de la API y de la prueba de vida.

Las pruebas de la API necesitan dos fotos de personas distintas (una cara por foto):
  set FACE_TEST_A=ruta\\persona_a.jpg
  set FACE_TEST_B=ruta\\persona_b.jpg
  pytest -q

Para probar el modelo anti-suplantación con fotos reales y falsas:
  set FACE_TEST_REAL=ruta\\cara_real.jpg
  set FACE_TEST_FAKE=ruta\\foto_de_una_foto.jpg
"""
import os
import tempfile
from contextlib import closing

import cv2
import numpy as np
import pytest

os.environ["FACE_DB"] = os.path.join(tempfile.mkdtemp(), "test.db")

from fastapi.testclient import TestClient  # noqa: E402

import main  # noqa: E402
from face_engine import (  # noqa: E402
    MIN_PARALLAX,
    MIN_REAL_SCORE,
    FaceSample,
    parallax,
)

A = os.environ.get("FACE_TEST_A")
B = os.environ.get("FACE_TEST_B")
needs_photos = pytest.mark.skipif(not (A and B), reason="Faltan FACE_TEST_A/B")

client = TestClient(main.app)


# --- Prueba de vida con una cara sintética en 3D -------------------------------

# Ojo der., ojo izq., nariz, boca der., boca izq. (x, y, z); z hacia la cámara.
FACE_3D = np.array(
    [[-0.5, 0, 0], [0.5, 0, 0], [0, 0.5, 0.55], [-0.4, 1, 0.1], [0.4, 1, 0.1]]
)


def project(points: np.ndarray, yaw_deg: float, tilt_deg: float = 0) -> np.ndarray:
    """Gira los puntos y los proyecta con una cámara a 6 unidades de distancia."""
    a, t = np.radians(yaw_deg), np.radians(tilt_deg)
    rot_y = np.array([[np.cos(a), 0, np.sin(a)], [0, 1, 0], [-np.sin(a), 0, np.cos(a)]])
    rot_x = np.array([[1, 0, 0], [0, np.cos(t), -np.sin(t)], [0, np.sin(t), np.cos(t)]])
    p = points @ rot_y.T @ rot_x.T
    depth = 6 - p[:, 2]
    return (p[:, :2] / depth[:, None]) * 600 + 300


def sample(points_2d: np.ndarray) -> FaceSample:
    return FaceSample(np.zeros(128, np.float32), None, points_2d)


@pytest.mark.parametrize("yaw", [-30, -20, 20, 30])
def test_cabeza_real_girada_tiene_paralaje(yaw):
    front = sample(project(FACE_3D, 0))
    turned = sample(project(FACE_3D, yaw))
    assert parallax(front, turned) > MIN_PARALLAX


@pytest.mark.parametrize("yaw,tilt", [(30, 0), (50, 0), (40, 25), (-45, -20)])
def test_foto_plana_inclinada_no_tiene_paralaje(yaw, tilt):
    # Una foto impresa: todos los puntos en el mismo plano, se inclina como un papel.
    flat_photo = np.c_[project(FACE_3D, 0) / 600 - 0.5, np.zeros(5)]
    front = sample(project(flat_photo, 0))
    turned = sample(project(flat_photo, yaw, tilt))
    assert parallax(front, turned) < MIN_PARALLAX / 4


# --- API -----------------------------------------------------------------------


def photo(path, transform=None):
    img = cv2.imread(path)
    if transform:
        img = transform(img)
    return ("f.jpg", cv2.imencode(".jpg", img)[1].tobytes(), "image/jpeg")


def photos(front, turned=None):
    return {"photo": front, "photo_turn": turned or front}


@pytest.fixture
def sin_prueba_de_vida(monkeypatch):
    """Con fotos fijas no se puede girar la cabeza, así que se omite ese paso."""
    monkeypatch.setattr(main.engine, "check_liveness", lambda front, turned: None)


@needs_photos
def test_misma_foto_dos_veces_no_pasa_la_prueba_de_vida():
    r = client.post(
        "/register", data={"username": "foto", "pin": "1234"}, files=photos(photo(A))
    )
    assert r.status_code == 422
    assert "gira" in r.json()["detail"]


@needs_photos
def test_register_rechaza_pin_invalido():
    # El PIN se valida antes de tocar las fotos.
    r = client.post(
        "/register", data={"username": "corto", "pin": "12"}, files=photos(photo(A))
    )
    assert r.status_code == 400
    assert "4 dígitos" in r.json()["detail"]


@needs_photos
def test_identify_sin_usuarios(sin_prueba_de_vida):
    # Debe ir antes de cualquier /register exitoso: la DB está vacía.
    r = client.post("/identify", files=photos(photo(A)))
    assert r.status_code == 401
    assert "registrados" in r.json()["detail"]


@needs_photos
def test_identify_reconoce_sin_escribir_usuario(sin_prueba_de_vida):
    # Diana es la única cara B registrada; los demás usuarios son cara A.
    client.post(
        "/register",
        data={"username": "diana", "pin": "1234"},
        files=photos(photo(B)),
    )
    r = client.post("/identify", files=photos(photo(B)))
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["username"] == "diana"

    r = client.get("/me", headers={"Authorization": f"Bearer {body['token']}"})
    assert r.json()["username"] == "diana"


@needs_photos
def test_flujo_completo(sin_prueba_de_vida):
    r = client.post(
        "/register", data={"username": "ana", "pin": "1234"}, files=photos(photo(A))
    )
    assert r.status_code == 200, r.text

    r = client.post(
        "/register", data={"username": "ana", "pin": "1234"}, files=photos(photo(A))
    )
    assert r.status_code == 409

    # Misma persona con otra iluminación y espejada: debe entrar.
    def variar(img):
        return cv2.flip(cv2.convertScaleAbs(img, alpha=1.2, beta=-20), 1)

    r = client.post("/login", data={"username": "ana"}, files=photos(photo(A, variar)))
    assert r.status_code == 200, r.text
    token = r.json()["token"]

    r = client.get("/me", headers={"Authorization": f"Bearer {token}"})
    assert r.json()["username"] == "ana"

    # Otra persona con el usuario de Ana: debe rechazarse.
    r = client.post("/login", data={"username": "ana"}, files=photos(photo(B)))
    assert r.status_code == 401

    client.post("/logout", headers={"Authorization": f"Bearer {token}"})
    assert client.get("/me", headers={"Authorization": f"Bearer {token}"}).status_code == 401


@needs_photos
def test_sin_rostro():
    blank = lambda img: img * 0  # noqa: E731
    r = client.post(
        "/register",
        data={"username": "nadie", "pin": "1234"},
        files=photos(photo(A, blank)),
    )
    assert r.status_code == 422


@needs_photos
def test_bloqueo_por_intentos(sin_prueba_de_vida):
    client.post(
        "/register", data={"username": "beto", "pin": "1234"}, files=photos(photo(A))
    )
    for _ in range(5):
        r = client.post("/login", data={"username": "beto"}, files=photos(photo(B)))
        assert r.status_code == 401
    r = client.post("/login", data={"username": "beto"}, files=photos(photo(A)))
    assert r.status_code == 429


@needs_photos
def test_suplantacion_cuenta_como_intento_fallido():
    # Sin el parche, la misma foto dos veces falla la prueba de vida en el login.
    with pytest.MonkeyPatch.context() as mp:
        mp.setattr(main.engine, "check_liveness", lambda front, turned: None)
        client.post(
            "/register", data={"username": "caro", "pin": "1234"}, files=photos(photo(A))
        )
    for _ in range(5):
        r = client.post("/login", data={"username": "caro"}, files=photos(photo(A)))
        assert r.status_code == 401
    r = client.post("/login", data={"username": "caro"}, files=photos(photo(A)))
    assert r.status_code == 429


# --- Login con PIN (sin escáner) ------------------------------------------------


@needs_photos
def test_login_pin_flujo(sin_prueba_de_vida):
    r = client.post(
        "/register", data={"username": "pino", "pin": "4321"}, files=photos(photo(A))
    )
    assert r.status_code == 200, r.text

    # PIN correcto: entra sin fotos.
    r = client.post("/login_pin", data={"username": "pino", "pin": "4321"})
    assert r.status_code == 200, r.text
    token = r.json()["token"]
    r = client.get("/me", headers={"Authorization": f"Bearer {token}"})
    assert r.json()["username"] == "pino"

    # PIN incorrecto: cuenta como intento fallido.
    for _ in range(5):
        r = client.post("/login_pin", data={"username": "pino", "pin": "0000"})
        assert r.status_code == 401
        assert "PIN" in r.json()["detail"]
    # Bloqueado: ni el PIN correcto entra.
    r = client.post("/login_pin", data={"username": "pino", "pin": "4321"})
    assert r.status_code == 429


def test_login_pin_usuario_inexistente():
    r = client.post("/login_pin", data={"username": "nobody99", "pin": "1234"})
    assert r.status_code == 404


def test_login_pin_usuario_sin_pin():
    # Usuario de antes del PIN: se inserta directo en la DB sin pin_hash.
    with closing(main.db()) as conn, conn:
        conn.execute(
            "INSERT INTO users (username, full_name, embedding, created_at) "
            "VALUES (?, ?, ?, ?)",
            ("viejo", "viejo", np.zeros(128, np.float32).tobytes(), 0.0),
        )
    r = client.post("/login_pin", data={"username": "viejo", "pin": "1234"})
    assert r.status_code == 401
    assert "PIN" in r.json()["detail"]


# --- Modelo anti-suplantación --------------------------------------------------

REAL = os.environ.get("FACE_TEST_REAL")
FAKE = os.environ.get("FACE_TEST_FAKE")


@pytest.mark.skipif(
    not (REAL and FAKE and main.engine.antispoof),
    reason="Faltan FACE_TEST_REAL/FAKE o los modelos anti-suplantación",
)
def test_modelo_distingue_real_de_foto():
    real = main.engine.analyze(photo(REAL)[1]).real_score
    fake = main.engine.analyze(photo(FAKE)[1]).real_score
    assert real >= MIN_REAL_SCORE > fake
