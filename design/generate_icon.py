# -*- coding: utf-8 -*-
"""
简忆 (JIAN YI) · HarmonyOS 应用图标生成器

产出符合 HarmonyOS 分层图标规范的两层资源：
  - background.png : 1024x1024, RGB, 纯色不透明, 无圆角/内边距
  - foreground.png : 1024x1024, RGBA, 仅核心图形, 其余 100% 透明
  - startIcon.png  : 152x152,  RGBA, 启动窗口图标 (合成图 + 圆角)

同时生成设计预览图 design/icon-preview.png、完整合成图 design/icon-full.png。

色值全部取自 entry/src/main/ets/common/Theme.ets 与
entry/src/main/resources/base/element/color.json，改主题时请同步这里。

用法：
  python design/generate_icon.py                  # 默认 slips（简牍，用户 2026-11-13 选定）
  python design/generate_icon.py --scheme seal   # 换成「朱印」
  python design/generate_icon.py --scheme page   # 换成「墨页」

依赖：Pillow；中文字体（Windows 自带，脚本内有多平台 fallback）。
本机无 HarmonyOS SDK，图标资源本身不参与 ArkTS 编译，生成即可被 DevEco 直接打包。
"""

from __future__ import annotations

import argparse
import os
from PIL import Image, ImageDraw, ImageFont, ImageChops, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DESIGN_DIR = os.path.join(ROOT, 'design')

SIZE = 1024          # 官方要求的前景/背景层边长
SS = 3               # 超采样倍数，降采样时获得干净边缘
CANVAS = SIZE * SS

# ---- 纸墨色板（与 Theme.ets / color.json 一一对应）------------------------
PAPER = (246, 242, 233, 255)      # C.paper          #F6F2E9
PAPER2 = (239, 233, 220, 255)     # C.paper2         #EFE9DC
INK = (27, 25, 23, 255)           # C.ink            #1B1917
CINNABAR = (180, 67, 46, 255)     # C.cinnabar       #B4432E
RULE = (222, 215, 201, 255)       # C.rule           #DED7C9

# 字体：印章用宋体（横细竖粗，最接近白文印），标签用无衬线
SERIF_FONTS = [
    'C:/Windows/Fonts/STZHONGS.TTF',           # 华文中宋（首选）
    'C:/Windows/Fonts/STSONG.TTF',             # 华文宋体
    '/System/Library/Fonts/PingFang.ttc',
    '/usr/share/fonts/opentype/noto/NotoSerifCJK-Bold.ttc',
    '/usr/share/fonts/truetype/arphic/uming.ttc',
]
SANS_FONTS = [
    'C:/Windows/Fonts/msyh.ttc',
    '/System/Library/Fonts/PingFang.ttc',
    '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
]


def pick_font(candidates: list[str]) -> str:
    for p in candidates:
        if os.path.exists(p):
            return p
    raise RuntimeError('找不到中文字体，请编辑 generate_icon.py 的 SERIF_FONTS / SANS_FONTS')


SERIF = pick_font(SERIF_FONTS)
SANS = pick_font(SANS_FONTS)


def sc(v: float) -> int:
    return int(round(v * SS))


def box(d: ImageDraw.ImageDraw, rect, radius: float,
        fill=None, outline=None, width: float = 0) -> None:
    d.rounded_rectangle([sc(v) for v in rect], radius=sc(radius),
                        fill=fill, outline=outline, width=sc(width))


def line(d: ImageDraw.ImageDraw, rect, radius: float, fill) -> None:
    d.rounded_rectangle([sc(v) for v in rect], radius=sc(radius), fill=fill)


def new_layer() -> Image.Image:
    return Image.new('RGBA', (CANVAS, CANVAS), (0, 0, 0, 0))


def down(im: Image.Image, size: int = SIZE) -> Image.Image:
    return im.resize((size, size), Image.LANCZOS)


def knockout_char(fg: Image.Image, char: str, px: float,
                  font_path: str, inflate: float = 2) -> None:
    """把汉字从前景层里镂空（白文印），露出下层宣纸白；保留抗锯齿边缘。"""
    f = ImageFont.truetype(font_path, sc(px))
    glyph = Image.new('L', (CANVAS, CANVAS), 0)
    gd = ImageDraw.Draw(glyph)
    bbox = gd.textbbox((0, 0), char, font=f)
    x = (CANVAS - (bbox[2] - bbox[0])) / 2 - bbox[0]
    y = (CANVAS - (bbox[3] - bbox[1])) / 2 - bbox[1]
    gd.text((x, y), char, font=f, fill=255)
    if inflate > 0:
        k = int(inflate * SS) * 2 + 1
        glyph = glyph.filter(ImageFilter.MaxFilter(k))
    fg.putalpha(ImageChops.subtract(fg.getchannel('A'), glyph))


# ---- 方案 A：朱印（备选）--------------------------------------------------
# 一枚居中朱红方印，白文「简」字，内圈细白边。色块集中，
# 系统圆形/圆角遮罩裁切后依然完整，48dp 下也认得出。
def fg_seal() -> Image.Image:
    fg = new_layer()
    d = ImageDraw.Draw(fg)
    box(d, (202, 202, 822, 822), 30, fill=CINNABAR)
    box(d, (238, 238, 786, 786), 14, outline=PAPER, width=6)
    knockout_char(fg, '简', 402, SERIF, inflate=2)
    return fg


# ---- 方案 B：墨页 ---------------------------------------------------------
# 墨线勾出的一页纸，三道记录横线，右下角压一枚朱红小印。
def fg_page() -> Image.Image:
    fg = new_layer()
    d = ImageDraw.Draw(fg)
    box(d, (248, 172, 776, 852), 20, outline=INK, width=22)
    line(d, (318, 306, 706, 324), 9, INK)
    line(d, (318, 404, 706, 422), 9, INK)
    line(d, (318, 502, 600, 520), 9, INK)
    box(d, (676, 742, 806, 872), 14, fill=CINNABAR)
    # 小印中央留一个米白方点，避免变成纯色方块
    line(d, (722, 788, 760, 826), 4, PAPER)
    return fg


# ---- 方案 C：简牍（当前落地方案）------------------------------------------
# 「简」字本义即竹简：三片墨色简 + 一道朱红编绳，呼应记录与记忆。
def fg_slips() -> Image.Image:
    fg = new_layer()
    d = ImageDraw.Draw(fg)
    xs = (290, 446, 602)
    for x in xs:
        box(d, (x, 224, x + 132, 800), 18, fill=INK)
    for x in xs:
        line(d, (x + 30, 316, x + 102, 330), 7, PAPER)
        line(d, (x + 30, 402, x + 102, 416), 7, PAPER)
        line(d, (x + 30, 646, x + 102, 660), 7, PAPER)
    line(d, (262, 512, 762, 558), 23, CINNABAR)
    return fg


SCHEMES = {
    'seal': ('朱印 · 白文「简」', '红底白字印，最醒目，小尺寸辨识度最高', fg_seal),
    'page': ('墨页 · 一页记录', '墨线纸页配朱红小印，最贴近书写意象', fg_page),
    'slips': ('简牍 · 三简一绳', '取「简」字本义，文化感最强', fg_slips),
}


def background() -> Image.Image:
    """纯色不透明背景层；官方要求无透明像素、无圆角、无内边距。"""
    return Image.new('RGB', (SIZE, SIZE), PAPER[:3])


def composite(bg: Image.Image, fg: Image.Image) -> Image.Image:
    out = bg.convert('RGBA')
    out.alpha_composite(fg)
    return out.convert('RGB')


def make_start_icon(full: Image.Image) -> Image.Image:
    """启动窗口图标：合成图缩到 152，切成系统模板那样的圆角方形。"""
    m = 4
    mask = Image.new('L', (152 * m, 152 * m), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, 152 * m, 152 * m],
                                          radius=34 * m, fill=255)
    mask = mask.resize((152, 152), Image.LANCZOS)
    icon = full.resize((152, 152), Image.LANCZOS).convert('RGBA')
    icon.putalpha(mask)
    return icon


def write_resources(bg: Image.Image, fg: Image.Image, full: Image.Image) -> None:
    targets = [
        os.path.join(ROOT, 'AppScope', 'resources', 'base', 'media'),
        os.path.join(ROOT, 'entry', 'src', 'main', 'resources', 'base', 'media'),
    ]
    bg.save(os.path.join(DESIGN_DIR, 'icon-background.png'))
    fg.save(os.path.join(DESIGN_DIR, 'icon-foreground.png'))
    for t in targets:
        bg.save(os.path.join(t, 'background.png'))
        fg.save(os.path.join(t, 'foreground.png'))
    make_start_icon(full).save(os.path.join(targets[1], 'startIcon.png'))
    full.save(os.path.join(DESIGN_DIR, 'icon-full.png'))


def rounded_preview(fg: Image.Image, bg: Image.Image, size: int,
                    radius: int, wallpaper: tuple,
                    icon_size: int | None = None) -> Image.Image:
    """模拟系统遮罩裁切后的桌面效果：图标居中放在一块壁纸上。"""
    icon_size = icon_size or size - 20
    plate = Image.new('RGBA', (size, size), wallpaper + (255,))
    m = Image.new('L', (SIZE, SIZE), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, SIZE, SIZE], radius=radius, fill=255)
    icon = composite(bg, fg).convert('RGBA').resize((icon_size, icon_size),
                                                    Image.LANCZOS)
    icon.putalpha(m.resize((icon_size, icon_size), Image.LANCZOS))
    off = (size - icon_size) // 2
    plate.alpha_composite(icon, (off, off))
    return plate.convert('RGB')


def make_preview(active: str) -> Image.Image:
    W, H = 1680, 1060
    out = Image.new('RGB', (W, H), PAPER[:3])
    d = ImageDraw.Draw(out)
    big = ImageFont.truetype(SERIF, 46)
    mid = ImageFont.truetype(SANS, 27)
    small = ImageFont.truetype(SANS, 21)
    tiny = ImageFont.truetype(SANS, 19)

    d.text((90, 54), '简忆 · 应用图标设计', font=big, fill=INK[:3])
    d.text((92, 118), '朱红 / 墨色 / 宣纸白 —— 全部取自 common/Theme.ets',
           font=small, fill=(110, 104, 93))

    bg = background()
    # 三方案卡片
    for i, (key, (title, desc, fn)) in enumerate(SCHEMES.items()):
        x = 90 + i * 510
        chosen = key == active
        d.rounded_rectangle([x, 178, x + 460, 648], radius=20,
                            fill=PAPER2[:3],
                            outline=CINNABAR[:3] if chosen else RULE[:3],
                            width=3 if chosen else 1)
        fg = down(fn())
        thumb = composite(bg, fg).resize((300, 300), Image.LANCZOS)
        out.paste(thumb, (x + 80, 208))
        d.text((x + 34, 532), title, font=mid, fill=INK[:3])
        d.text((x + 34, 578), desc, font=tiny, fill=(110, 104, 93))
        if chosen:
            d.text((x + 34, 610), '● 当前落地方案', font=tiny, fill=CINNABAR[:3])

    d.line([(90, 690), (1590, 690)], fill=RULE[:3], width=2)
    d.text((90, 716), '当前方案在系统里的样子', font=ImageFont.truetype(SERIF, 34),
           fill=INK[:3])

    fg = down(SCHEMES[active][2]())
    samples = [
        ('圆角方形遮罩', rounded_preview(fg, bg, 170, 220, PAPER2[:3])),
        ('圆形遮罩', rounded_preview(fg, bg, 170, 512, PAPER2[:3])),
        ('深色壁纸', rounded_preview(fg, bg, 170, 220, (35, 32, 25))),
        ('实际桌面尺寸 56px', rounded_preview(fg, bg, 170, 220, PAPER2[:3], 56)),
    ]
    for i, (label, im) in enumerate(samples):
        x = 90 + i * 300
        out.paste(im, (x, 790))
        d.text((x, 975), label, font=tiny, fill=(110, 104, 93))

    d.text((90, 1020),
           '规范：前景/背景均 1024×1024 PNG；背景纯色不透明，前景仅保留图形；系统自动裁切遮罩。',
           font=tiny, fill=(140, 133, 120))
    out.save(os.path.join(DESIGN_DIR, 'icon-preview.png'))
    return out


def main() -> None:
    ap = argparse.ArgumentParser(description='生成简忆应用图标资源')
    ap.add_argument('--scheme', choices=list(SCHEMES.keys()), default='slips',
                    help='落地哪个方案，默认 slips')
    args = ap.parse_args()

    os.makedirs(DESIGN_DIR, exist_ok=True)
    bg = background()
    fg = down(SCHEMES[args.scheme][2]())
    full = composite(bg, fg)
    write_resources(bg, fg, full)
    make_preview(args.scheme)

    print('方案:', args.scheme, '-', SCHEMES[args.scheme][0])
    print('已写入 AppScope + entry 两套分层图标、startIcon.png')
    print('预览:', os.path.join(DESIGN_DIR, 'icon-preview.png'))
    print('合成:', os.path.join(DESIGN_DIR, 'icon-full.png'))


if __name__ == '__main__':
    main()
