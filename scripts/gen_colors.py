#!/usr/bin/env python3
"""生成本仓库的颜色资产（双主题）。

颜色值来自 docs/设计文档.md 第 8.2 节；资产生成后即以文件为准，此脚本仅作记录与重建用。
用法：python3 scripts/gen_colors.py
"""

from __future__ import annotations

import json
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
COLORS_DIR = REPO / "Latent/Resources/Assets.xcassets/Colors"

# 名字: (暗色 hex, 浅色 hex)
PALETTE: dict[str, tuple[str, str]] = {
    "Bg": ("#0B0D12", "#F5F6F9"),
    "Surface": ("#12151C", "#FFFFFF"),
    "SurfaceElevated": ("#181C25", "#FFFFFF"),
    "Border": ("#242A36", "#E3E7EF"),
    "TextPrimary": ("#F2F4F8", "#0C1117"),
    "TextSecondary": ("#8C94A6", "#5D6775"),
    "AccentColor": ("#7C6CFF", "#5F51E6"),  # Xcode 约定的强调色名
    "AccentText": ("#0A0B14", "#FFFFFF"),
    "Success": ("#4ADE80", "#15803D"),
    "Warning": ("#FBBF24", "#B45309"),
    "Error": ("#FB7185", "#BE123C"),
}


def components(hex_color: str) -> dict[str, str]:
    h = hex_color.lstrip("#")
    return {
        "alpha": "1.000",
        "red": str(int(h[0:2], 16)),
        "green": str(int(h[2:4], 16)),
        "blue": str(int(h[4:6], 16)),
    }


def colorset(light: str, dark: str) -> dict:
    return {
        "colors": [
            {"color": {"color-space": "srgb", "components": components(light)}, "idiom": "universal"},
            {
                "appearances": [{"appearance": "luminosity", "value": "dark"}],
                "color": {"color-space": "srgb", "components": components(dark)},
                "idiom": "universal",
            },
        ],
        "info": {"author": "xcode", "version": 1},
    }


def main() -> None:
    for name, (dark, light) in PALETTE.items():
        scene_dir = COLORS_DIR / f"{name}.colorset"
        scene_dir.mkdir(parents=True, exist_ok=True)
        payload = json.dumps(colorset(light, dark), indent=2, ensure_ascii=False) + "\n"
        (scene_dir / "Contents.json").write_text(payload, encoding="utf-8")
        print(f"  ✓ {name}  dark={dark} light={light}")
    print(f"完成 → {COLORS_DIR}")


if __name__ == "__main__":
    main()
