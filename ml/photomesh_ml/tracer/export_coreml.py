"""Export a trained CircuitNet to Core ML (and optionally ONNX).

    python -m photomesh_ml.tracer.export_coreml --checkpoint runs/tracer/last.pt --size 640 --out CircuitNet.mlpackage

Core ML contract (what the Swift assembler reads):
    input  "image"       RGB image, `size` x `size`, scaled 1/255 then ImageNet-normalised inside the model
    output "symbol_heat" [1, 13, size/4, size/4]  probabilities, channel order = TRACER_CLASSES
           "symbol_size" [1, 2, ...]  box (w, h) in stride units;   "symbol_off" [1, 2, ...] sub-cell offset
           "polarity"    [1, 4, ...]  probabilities right/up/left/down
           "wire", "junction", "terminal" [1, 1, ...] probabilities
"""
from __future__ import annotations

import argparse
import json

import torch
import torch.nn as nn

from ..classes import POLARITY, TRACER_CLASSES
from .model import IMAGENET_MEAN, IMAGENET_STD, ExportWrapper
from .checkpoint import load_checkpoint


class WithNormalisation(nn.Module):
    """Takes a [1, 3, H, W] image in 0..1 (Core ML ImageType with scale 1/255) and normalises inside."""

    def __init__(self, wrapped: ExportWrapper):
        super().__init__()
        self.wrapped = wrapped
        self.register_buffer("mean", torch.tensor(IMAGENET_MEAN).view(1, 3, 1, 1))
        self.register_buffer("std", torch.tensor(IMAGENET_STD).view(1, 3, 1, 1))

    def forward(self, x):
        return self.wrapped((x - self.mean) / self.std)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--checkpoint", required=True)
    parser.add_argument("--size", type=int, default=640)
    parser.add_argument("--out", default="CircuitNet.mlpackage")
    parser.add_argument("--onnx", default=None, help="also write an ONNX file")
    parser.add_argument("--fp32", action="store_true", help="keep float32 weights (default float16)")
    args = parser.parse_args()
    model, ckpt = load_checkpoint(args.checkpoint, torch.device("cpu"))
    model.eval()
    net = WithNormalisation(ExportWrapper(model)).eval()
    example = torch.rand(1, 3, args.size, args.size)
    traced = torch.jit.trace(net, example)

    import coremltools as ct
    outputs = [ct.TensorType(name=n) for n in ExportWrapper.ORDER]
    mlmodel = ct.convert(
        traced,
        inputs=[ct.ImageType(name="image", shape=example.shape, scale=1 / 255.0, color_layout=ct.colorlayout.RGB)],
        outputs=outputs,
        minimum_deployment_target=ct.target.iOS17,
        compute_precision=ct.precision.FLOAT32 if args.fp32 else ct.precision.FLOAT16,
        convert_to="mlprogram",
    )
    mlmodel.short_description = "PhotoMesh CircuitNet: circuit symbols, polarity, wires, junctions, terminals"
    mlmodel.user_defined_metadata["classes"] = json.dumps(TRACER_CLASSES)
    mlmodel.user_defined_metadata["polarity"] = json.dumps(POLARITY)
    mlmodel.user_defined_metadata["stride"] = "4"
    mlmodel.user_defined_metadata["input_size"] = str(args.size)
    mlmodel.save(args.out)
    print("wrote", args.out)

    if args.onnx:
        try:
            torch.onnx.export(net, example, args.onnx, input_names=["image"], output_names=list(ExportWrapper.ORDER), opset_version=17, dynamo=False)
            print("wrote", args.onnx)
        except Exception as exc:  # noqa: BLE001
            print(f"ONNX export skipped ({exc.__class__.__name__}: {exc}); pip install onnx onnxscript and retry")


if __name__ == "__main__":
    main()
