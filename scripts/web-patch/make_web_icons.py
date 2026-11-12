#!/usr/bin/env python3
"""从 assets/icon/app_icon.png 生成 Web 端图标。

Flutter 的 `flutter create --platforms=web` 只会塞一套默认 Flutter logo
（web/favicon.png + web/icons/Icon-*.png），跟应用本身毫无关系。这里用
仓库里那份正式图标重绘整套：

  web/favicon.png            32×32  浏览器标签页
  web/icons/Icon-192.png     192×192 PWA 普通图标
  web/icons/Icon-512.png     512×512 PWA 普通图标
  web/icons/Icon-maskable-192.png   192×192 Android 自适应（安全区 80%）
  web/icons/Icon-maskable-512.png   512×512

原始图标是 1024×1024 白底 + 居中 718px 绿色图形（左右上下各 153px 留白）。
普通图标沿用这个构图；maskable 版本按 Android 规范把内容缩到 80% 居中，
否则系统裁圆角时会切掉图形边缘。

用法：
    python3 scripts/web-patch/make_web_icons.py <输出目录>

`scripts/build-web.sh` 会在 `flutter create` 之后调用它，产物落在临时副本的
`web/` 下，不写回主仓库。
"""

import pathlib
import sys

try:
    from PIL import Image
except ImportError:  # pragma: no cover - 构建环境提示
    print('error: Pillow is required (pip install pillow)', file=sys.stderr)
    sys.exit(1)

REPO = pathlib.Path(__file__).resolve().parents[2]
SOURCE = REPO / 'assets' / 'icon' / 'app_icon.png'

# (文件名, 边长, 内容占比)
# 普通图标：原图已经是 70% 占比的白底方图，直接缩放。
# maskable：Android 规定安全区是中间 80% 圆/方，内容必须再缩一圈。
TARGETS = [
    ('favicon.png', 32, 1.0),
    ('icons/Icon-192.png', 192, 1.0),
    ('icons/Icon-512.png', 512, 1.0),
    ('icons/Icon-maskable-192.png', 192, 0.80),
    ('icons/Icon-maskable-512.png', 512, 0.80),
]


def render(source: Image.Image, size: int, content_ratio: float) -> Image.Image:
    """把 source 缩放后居中贴到 size×size 的白底画布上。"""
    canvas = Image.new('RGBA', (size, size), (255, 255, 255, 255))
    inner = max(1, round(size * content_ratio))
    scaled = source.resize((inner, inner), Image.LANCZOS)
    offset = (size - inner) // 2
    canvas.paste(scaled, (offset, offset), scaled)
    return canvas


def main() -> int:
    if len(sys.argv) < 2:
        print('usage: make_web_icons.py <web-dir>', file=sys.stderr)
        return 2
    web_dir = pathlib.Path(sys.argv[1])
    if not web_dir.is_dir():
        print(f'error: {web_dir} is not a directory', file=sys.stderr)
        return 1
    if not SOURCE.exists():
        print(f'error: icon source missing: {SOURCE}', file=sys.stderr)
        return 1

    source = Image.open(SOURCE).convert('RGBA')
    written = []
    for name, size, ratio in TARGETS:
        out = web_dir / name
        out.parent.mkdir(parents=True, exist_ok=True)
        # maskable 保留 RGBA（系统会自己裁形状）；普通图标铺白底，
        # 避免某些启动器把透明区渲染成黑块。
        image = render(source, size, ratio)
        image.save(out, 'PNG', optimize=True)
        written.append(f'{name} ({size}px)')
    print('  web icons: ' + ', '.join(written))
    return 0


if __name__ == '__main__':
    sys.exit(main())
