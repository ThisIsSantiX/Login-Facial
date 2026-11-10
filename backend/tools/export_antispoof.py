"""Convierte los modelos MiniFASNet (anti-suplantación) de PyTorch a ONNX.

Solo hace falta correrlo una vez; el servidor usa los .onnx con OpenCV y no
necesita PyTorch. Los modelos son de Minivision (Apache 2.0):
https://github.com/minivision-ai/Silent-Face-Anti-Spoofing

Uso (en un entorno aparte con torch y onnx instalados):
  git clone --depth 1 https://github.com/minivision-ai/Silent-Face-Anti-Spoofing repo
  python tools/export_antispoof.py repo
"""
import sys
from collections import OrderedDict
from pathlib import Path

import torch

repo = Path(sys.argv[1]).resolve()
sys.path.insert(0, str(repo))
from src.model_lib.MiniFASNet import MiniFASNetV1SE, MiniFASNetV2  # noqa: E402

MODELS = {
    "2.7_80x80_MiniFASNetV2.pth": MiniFASNetV2,
    "4_0_0_80x80_MiniFASNetV1SE.pth": MiniFASNetV1SE,
}
out_dir = Path(__file__).resolve().parent.parent / "models"
out_dir.mkdir(exist_ok=True)

for name, factory in MODELS.items():
    model = factory(conv6_kernel=(5, 5))
    # weights_only evita ejecutar código arbitrario al cargar el archivo.
    state = torch.load(
        repo / "resources" / "anti_spoof_models" / name,
        map_location="cpu",
        weights_only=True,
    )
    state = OrderedDict((k.removeprefix("module."), v) for k, v in state.items())
    model.load_state_dict(state)
    model.eval()

    target = out_dir / ("antispoof_" + name.replace(".pth", ".onnx"))
    torch.onnx.export(
        model,
        torch.zeros(1, 3, 80, 80),
        str(target),
        input_names=["input"],
        output_names=["logits"],
        opset_version=13,
        dynamo=False,
    )
    print(f"{target.name}: {target.stat().st_size / 1024:.0f} KB")
