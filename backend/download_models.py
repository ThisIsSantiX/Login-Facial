"""Descarga los modelos oficiales de OpenCV Zoo (YuNet y SFace)."""
import urllib.request
from pathlib import Path

BASE = "https://github.com/opencv/opencv_zoo/raw/main/models"
MODELS = {
    "face_detection_yunet_2023mar.onnx": f"{BASE}/face_detection_yunet/face_detection_yunet_2023mar.onnx",
    "face_recognition_sface_2021dec.onnx": f"{BASE}/face_recognition_sface/face_recognition_sface_2021dec.onnx",
}

models_dir = Path(__file__).parent / "models"
models_dir.mkdir(exist_ok=True)

for name, url in MODELS.items():
    target = models_dir / name
    if target.exists() and target.stat().st_size > 100_000:
        print(f"Ya existe {name}")
        continue
    print(f"Descargando {name}...")
    urllib.request.urlretrieve(url, target)
    print(f"  {target.stat().st_size / 1024:.0f} KB")
