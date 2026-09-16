"""CircuitNet: a small fully-convolutional multi-task network that exports cleanly to Core ML.

Input:  float image [B, 3, H, W], ImageNet-normalised, H and W multiples of 32.
Outputs (all at stride 4, i.e. [B, C, H/4, W/4]):
    symbol_heat  [13]  sigmoid, one channel per TRACER_CLASSES entry
    symbol_size  [2]   box width, height in stride units
    symbol_off   [2]   sub-cell centre offset
    polarity     [4]   logits over right / up / left / down
    wire         [1]   sigmoid, wire ink
    junction     [1]   sigmoid, points where three or more conductors meet
    terminal     [1]   sigmoid, points where a lead meets a symbol body
Backbones: "tiny" (tests / CPU), "mobilenet_v3_large" (phone), "resnet18" (server or bigger phone).
"""
from __future__ import annotations

import math
from typing import Optional

import torch
import torch.nn as nn
import torch.nn.functional as F

from ..classes import POLARITY, TRACER_CLASSES

HEADS = {"symbol_heat": len(TRACER_CLASSES), "symbol_size": 2, "symbol_off": 2, "polarity": len(POLARITY), "wire": 1, "junction": 1, "terminal": 1}
SIGMOID_HEADS = ("symbol_heat", "wire", "junction", "terminal")


def conv_bn(cin: int, cout: int, k: int = 3, s: int = 1) -> nn.Sequential:
    return nn.Sequential(nn.Conv2d(cin, cout, k, s, k // 2, bias=False), nn.BatchNorm2d(cout), nn.ReLU(inplace=True))


class TinyBackbone(nn.Module):
    """Five stages, strides 2..32; ~0.5M parameters. Good for unit tests and quick CPU runs."""

    channels = (16, 24, 48, 96, 160)

    def __init__(self):
        super().__init__()
        chans = self.channels
        self.stages = nn.ModuleList()
        cin = 3
        for c in chans:
            self.stages.append(nn.Sequential(conv_bn(cin, c, 3, 2), conv_bn(c, c, 3, 1)))
            cin = c

    def forward(self, x: torch.Tensor) -> list[torch.Tensor]:
        feats = []
        for stage in self.stages:
            x = stage(x)
            feats.append(x)
        return feats[1:]  # strides 4, 8, 16, 32


class TorchvisionBackbone(nn.Module):
    """Wraps torchvision MobileNetV3-Large or ResNet-18, returning strides 4, 8, 16, 32."""

    def __init__(self, name: str, pretrained: bool = True):
        super().__init__()
        import torchvision  # noqa: F401
        from torchvision import models
        self.name = name
        if name == "mobilenet_v3_large":
            weights = models.MobileNet_V3_Large_Weights.IMAGENET1K_V1 if pretrained else None
            net = models.mobilenet_v3_large(weights=weights).features
            self.body = net
            self.taps = self._find_taps(net)
            self.channels = tuple(self._channels_at(net, self.taps))
        elif name == "resnet18":
            weights = models.ResNet18_Weights.IMAGENET1K_V1 if pretrained else None
            net = models.resnet18(weights=weights)
            self.stem = nn.Sequential(net.conv1, net.bn1, net.relu, net.maxpool)
            self.layers = nn.ModuleList([net.layer1, net.layer2, net.layer3, net.layer4])
            self.channels = (64, 128, 256, 512)
        else:
            raise ValueError(name)

    @staticmethod
    def _find_taps(features: nn.Sequential) -> list[int]:
        """Indices of the last block at each of strides 4, 8, 16, 32 (found by probing)."""
        taps = []
        x = torch.zeros(1, 3, 64, 64)
        last_size = 64
        with torch.no_grad():
            for i, block in enumerate(features):
                x = block(x)
                if x.shape[-1] != last_size:
                    if taps:
                        taps[-1] = i - 1
                    taps.append(i)
                    last_size = x.shape[-1]
                else:
                    taps[-1] = i
        # taps now marks the last index of each resolution; keep strides 4..32
        return taps[1:5]

    @staticmethod
    def _channels_at(features: nn.Sequential, taps: list[int]) -> list[int]:
        chans = []
        x = torch.zeros(1, 3, 64, 64)
        with torch.no_grad():
            for i, block in enumerate(features):
                x = block(x)
                if i in taps:
                    chans.append(x.shape[1])
        return chans

    def forward(self, x: torch.Tensor) -> list[torch.Tensor]:
        if self.name == "resnet18":
            x = self.stem(x)
            feats = []
            for layer in self.layers:
                x = layer(x)
                feats.append(x)
            return feats
        feats = []
        for i, block in enumerate(self.body):
            x = block(x)
            if i in self.taps:
                feats.append(x)
        return feats


class FPNDecoder(nn.Module):
    """Top-down feature pyramid merged to stride 4."""

    def __init__(self, channels: tuple[int, ...], width: int):
        super().__init__()
        self.laterals = nn.ModuleList([nn.Conv2d(c, width, 1) for c in channels])
        self.smooth = nn.Sequential(conv_bn(width, width), conv_bn(width, width))

    def forward(self, feats: list[torch.Tensor]) -> torch.Tensor:
        x = self.laterals[-1](feats[-1])
        for lateral, f in zip(reversed(self.laterals[:-1]), reversed(feats[:-1])):
            x = F.interpolate(x, size=f.shape[-2:], mode="bilinear", align_corners=False) + lateral(f)
        return self.smooth(x)


class CircuitNet(nn.Module):
    def __init__(self, backbone: str = "tiny", width: int = 64, pretrained: bool = True):
        super().__init__()
        if backbone == "tiny":
            self.backbone = TinyBackbone()
            channels = TinyBackbone.channels[1:]
        else:
            self.backbone = TorchvisionBackbone(backbone, pretrained)
            channels = self.backbone.channels
        self.decoder = FPNDecoder(tuple(channels), width)
        self.heads = nn.ModuleDict()
        for name, cout in HEADS.items():
            head = nn.Sequential(nn.Conv2d(width, width, 3, 1, 1), nn.ReLU(inplace=True), nn.Conv2d(width, cout, 1))
            if name in SIGMOID_HEADS:
                nn.init.constant_(head[-1].bias, -2.19)  # prior probability 0.1
            self.heads[name] = head
        self.backbone_name = backbone

    def forward(self, x: torch.Tensor) -> dict[str, torch.Tensor]:
        feats = self.backbone(x)
        y = self.decoder(feats)
        return {name: head(y) for name, head in self.heads.items()}

    @torch.no_grad()
    def predict(self, x: torch.Tensor) -> dict[str, torch.Tensor]:
        """Forward pass with sigmoids applied (what the exported model returns)."""
        out = self.forward(x)
        for name in SIGMOID_HEADS:
            out[name] = torch.sigmoid(out[name])
        out["polarity"] = torch.softmax(out["polarity"], dim=1)
        return out


class ExportWrapper(nn.Module):
    """Sigmoid/softmax applied, outputs in a fixed order for Core ML / ONNX."""

    ORDER = ("symbol_heat", "symbol_size", "symbol_off", "polarity", "wire", "junction", "terminal")

    def __init__(self, net: CircuitNet):
        super().__init__()
        self.net = net

    def forward(self, x: torch.Tensor):
        out = self.net(x)
        for name in SIGMOID_HEADS:
            out[name] = torch.sigmoid(out[name])
        out["polarity"] = torch.softmax(out["polarity"], dim=1)
        return tuple(out[name] for name in self.ORDER)


IMAGENET_MEAN = (0.485, 0.456, 0.406)
IMAGENET_STD = (0.229, 0.224, 0.225)


def normalize(image_uint8: torch.Tensor) -> torch.Tensor:
    """[B, 3, H, W] uint8 RGB -> normalised float."""
    x = image_uint8.float() / 255.0
    mean = torch.tensor(IMAGENET_MEAN, device=x.device).view(1, 3, 1, 1)
    std = torch.tensor(IMAGENET_STD, device=x.device).view(1, 3, 1, 1)
    return (x - mean) / std
