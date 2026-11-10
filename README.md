# Face Login

App móvil (Flutter) con inicio de sesión por reconocimiento facial y backend en Python (FastAPI + OpenCV).

## Por qué Flutter y no React Native

Para teléfonos de gama baja, Flutter compila a código nativo (AOT) y no tiene un
puente JavaScript ni un motor JS corriendo en paralelo. Arranca más rápido, usa menos
RAM y se ve igual en Android viejos. React Native depende de la versión de WebView/JS
del dispositivo y su rendimiento cae más en equipos de 1–2 GB de RAM.

## Cómo está pensada para equipos de bajos recursos

- **El reconocimiento corre en el servidor.** El teléfono solo toma una foto; no carga
  modelos de IA, así que la app pesa poco y no se calienta.
- **Foto pequeña:** 480×640 a calidad 70 (≈30–50 KB). Sube rápido incluso con 3G.
- **Cámara del sistema** (`image_picker`) en vez de una vista previa en vivo: mucha
  menos memoria y batería.
- **Recupera la foto** si Android cierra la app por falta de RAM mientras la cámara
  está abierta (`retrieveLostData`).
- **Pocas dependencias** (`http`, `image_picker`, `shared_preferences`), APK separado
  por arquitectura y con `minify`/`shrinkResources`.

## Estructura

```
face_login/
├── backend/
│   ├── main.py             API: /register, /login, /me, /logout
│   ├── face_engine.py      Detección (YuNet), reconocimiento (SFace) y prueba de vida
│   ├── download_models.py  Descarga los modelos ONNX de OpenCV Zoo
│   ├── tools/export_antispoof.py  Convierte MiniFASNet a ONNX (una sola vez)
│   └── test_api.py         Pruebas
└── app/                    Proyecto Flutter
    └── lib/
        ├── main.dart       Pantallas: inicio, login, registro, home
        ├── api.dart        Cliente HTTP y sesión
        └── face_capture.dart  Captura de la selfie
```

## 1. Levantar el backend

```bash
cd backend
python -m venv .venv
.venv\Scripts\activate          # en Linux/Mac: source .venv/bin/activate
pip install -r requirements.txt
python download_models.py
uvicorn main:app --host 0.0.0.0 --port 8000
```

Revisa que funcione en http://localhost:8000/docs

### Modelos anti-suplantación (una sola vez)

MiniFASNet (Minivision, Apache 2.0) solo se publica en formato PyTorch. Se convierte
una vez a ONNX en un entorno aparte; el servidor no necesita PyTorch:

```bash
python -m venv export_venv
export_venv\Scripts\pip install torch onnx onnxscript --index-url https://download.pytorch.org/whl/cpu
git clone --depth 1 https://github.com/minivision-ai/Silent-Face-Anti-Spoofing fas_repo
export_venv\Scripts\python tools\export_antispoof.py fas_repo
```

Esto deja `antispoof_*.onnx` en `backend/models/`. Sin esos archivos el servidor no
arranca, salvo que se ponga `FACE_ANTISPOOF=off` (solo para desarrollo).

## 2. Correr la app

Emulador de Android (usa `10.0.2.2` para llegar al PC):

```bash
cd app
flutter run
```

Teléfono real en la misma red Wi-Fi (cambia por la IP de tu PC, la ves con `ipconfig`):

```bash
flutter run --dart-define=API_URL=http://192.168.1.50:8000
```

APK para instalar:

```bash
flutter build apk --release --split-per-abi --dart-define=API_URL=http://192.168.1.50:8000
```

Los equipos de gama baja casi siempre usan `app-armeabi-v7a-release.apk`
(o `arm64-v8a` si son de 64 bits).

## Pruebas del backend

```bash
set FACE_TEST_A=C:\fotos\persona_a.jpg
set FACE_TEST_B=C:\fotos\persona_b.jpg
pytest -q
```

## Prueba de vida (anti-suplantación)

Para entrar o registrarse la app pide **dos selfies**: una de frente y otra con la
cabeza girada. El servidor aplica tres controles:

1. **Modelo MiniFASNet** sobre cada foto: detecta fotos impresas y pantallas
   (textura, moiré, bordes). Umbral: `MIN_REAL_SCORE`.
2. **Paralaje 3D:** en una cara real la nariz sobresale del plano de ojos y boca.
   Con los puntos de ojos y boca se calcula cómo se habría deformado una imagen
   plana, y si la nariz cae justo donde predice esa deformación, es una foto o una
   pantalla, por mucho que se incline. Umbral: `MIN_PARALLAX`.
3. Las dos fotos deben ser de la **misma persona**, y la de frente debe coincidir
   con la registrada.

Un intento de suplantación cuenta como intento fallido para el bloqueo de 5 minutos.

**Límites honestos:** el control 2 depende de los puntos faciales de YuNet, que con
una foto *muy* inclinada pueden equivocarse; por eso existe el control 1. Ninguno de
los dos frena del todo un video de la persona girando la cabeza en otra pantalla o
una máscara 3D. Calibra los umbrales con fotos reales de tus usuarios antes de
producción.

## Seguridad: qué falta antes de producción

- **HTTPS:** quita `android:usesCleartextTraffic="true"` del `AndroidManifest.xml` y
  sirve la API detrás de HTTPS.
- **Datos biométricos:** los vectores faciales en `users.db` son datos sensibles;
  cífralos en reposo y pide consentimiento según la ley de tu país.
- Ajusta `COSINE_THRESHOLD` en `face_engine.py` (más alto = más estricto).
