#!/usr/bin/env python3
"""从 Design/AppIcon-source.png 生成 AppIcon.appiconset 全套尺寸。

源稿是 1254×1254 的导出图：一块带 1px 深色描边的圆角瓷砖居中，四周是衬垫底色
（左/上/右 75px、下 93px，不对称 → 是导出衬垫，不是画面）。生成时裁到瓷砖外边界、
用实测圆角半径做圆角遮罩（瓷砖外的部分透明），得到"满格"图标资产：交给 macOS 27 的
图标管线（系统圆角遮罩 / Icon Composer）叠合时不会多出一层衬垫。

参数来自源稿实测（2026-10-19）：
- 瓷砖边界: x∈[74, 1181)、y∈[74, 1162)（下沿收 2px：底部描边极淡，让内容贴满画布）
- 圆角: 四角联合拟合 r≈250（圆角矩形，与绘制边界误差 <2px）
- 不能用"颜色是否接近底色"来判定内外：瓷砖自身有明暗过渡，左下的暗部与衬垫底色
  几乎同色（rgb≈17,21,31），按颜色判会把瓷砖咬出缺口

依赖 Pillow（仅开发期；应用本体零依赖）。
用法：python3 scripts/make_appicon.py
"""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageStat

REPO = Path(__file__).resolve().parent.parent
SOURCE = REPO / "Design/AppIcon-source.png"
ICONSET = REPO / "Latent/Resources/Assets.xcassets/AppIcon.appiconset"

TILE_BOX = (74, 74, 1181, 1162)  # 瓷砖外边界，含 1px 描边
CORNER_RADIUS = 250              # 圆角半径（源稿实测）
SUPERSAMPLE = 4                  # 遮罩超采样倍数（降采样用面积平均，边缘无振铃）

# 文件名 → 边长（macOS 图标清单：16/32/128/256/512 的 1x 与 2x）
SIZES: dict[str, int] = {
    "icon_16x16.png": 16,
    "icon_16x16@2x.png": 32,
    "icon_32x32.png": 32,
    "icon_32x32@2x.png": 64,
    "icon_128x128.png": 128,
    "icon_128x128@2x.png": 256,
    "icon_256x256.png": 256,
    "icon_256x256@2x.png": 512,
    "icon_512x512.png": 512,
    "icon_512x512@2x.png": 1024,
}

MANIFEST: list[tuple[str, str]] = [
    ("16x16", "1x"),
    ("16x16", "2x"),
    ("32x32", "1x"),
    ("32x32", "2x"),
    ("128x128", "1x"),
    ("128x128", "2x"),
    ("256x256", "1x"),
    ("256x256", "2x"),
    ("512x512", "1x"),
    ("512x512", "2x"),
]


def filename_for(size: str, scale: str) -> str:
    return f"icon_{size}.png" if scale == "1x" else f"icon_{size}@{scale}.png"


def rounded_mask(width: int, height: int, radius: float) -> Image.Image:
    """满幅圆角矩形遮罩：直边贴画布，四角按 radius 裁圆。"""
    big = Image.new("L", (width * SUPERSAMPLE, height * SUPERSAMPLE), 0)
    ImageDraw.Draw(big).rounded_rectangle(
        [0, 0, width * SUPERSAMPLE, height * SUPERSAMPLE],
        radius=radius * SUPERSAMPLE,
        fill=255,
    )
    # 面积平均降采样：得到干净的抗锯齿边缘（LANCZOS 会在硬边产生振铃）
    return big.resize((width, height), Image.Resampling.BOX)


def main() -> None:
    tile = Image.open(SOURCE).convert("RGB").crop(TILE_BOX)
    w, h = tile.size
    mask = rounded_mask(w, h, CORNER_RADIUS)

    # 1) 自检：四角透明、四边中点不透明、不透明占比符合圆角矩形
    if any(mask.getpixel(p) for p in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]):
        raise SystemExit("四角应为透明")
    if any(
        mask.getpixel(p) != 255
        for p in [(0, h // 2), (w // 2, 0), (w - 1, h // 2), (w // 2, h - 1)]
    ):
        raise SystemExit("四边中点的内容应贴满画布")
    ratio = mask.histogram()[255] / (w * h)
    expected = 1 - 4 * CORNER_RADIUS**2 * (1 - 3.141592653589793 / 4) / (w * h)
    if abs(ratio - expected) > 0.005:
        raise SystemExit(f"不透明占比异常：{ratio:.3f}（期望 {expected:.3f}）")

    # 2) 透明区的 RGB 填边界环均色（缩放时避免黑边）
    ring = ImageChops.difference(mask, mask.filter(ImageFilter.MinFilter(3)))
    ring_color = tuple(int(round(v)) for v in ImageStat.Stat(tile, ring).mean)
    rgb = Image.composite(tile, Image.new("RGB", tile.size, ring_color), mask)

    # 3) 输出全部尺寸（源稿非正方，直接压成正方；1.5% 各向拉伸不可见）
    rgba = rgb.convert("RGBA")
    rgba.putalpha(mask)
    ICONSET.mkdir(parents=True, exist_ok=True)
    for name, side in SIZES.items():
        rgba.resize((side, side), Image.Resampling.LANCZOS).save(ICONSET / name)
        print(f"  ✓ {name}  {side}px")

    # 4) Contents.json
    images = [
        {"filename": filename_for(size, scale), "idiom": "mac", "scale": scale, "size": size}
        for size, scale in MANIFEST
    ]
    contents = {"images": images, "info": {"author": "xcode", "version": 1}}
    (ICONSET / "Contents.json").write_text(
        json.dumps(contents, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    print(f"完成 → {ICONSET}（边界环均色 {ring_color}，不透明占比 {ratio:.3f}）")


if __name__ == "__main__":
    main()
