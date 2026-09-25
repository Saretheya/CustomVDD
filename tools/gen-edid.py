#!/usr/bin/env python3
# -*- coding: utf-8 -*-
r"""
CustomVDD EDID 生成器

生成自研虚拟显示器的 EDID，并输出驱动需要的 C++ 模式表。

目标参数：
  厂商码    CVD
  产品码    0x0001
  显示器名  CustomVDD
  分辨率    1920x1080 / 2560x1440 / 3440x1440 / 3840x2160
  刷新率    60 / 90 / 120 / 144 / 165 / 240

注意：首选模式（preferred）保持为 2560x1440@144，以维持当前选中状态不变。
"""

import struct
import sys

# ------------------------------------------------------------------
# 监视器模式表：顺序即 pModeList 顺序，索引 0 为 preferred
# ------------------------------------------------------------------
MODES = [
    (2560, 1440, 144),   # 0  <- preferred（保持当前选中不变）
    (2560, 1440,  60),
    (2560, 1440,  90),
    (2560, 1440, 120),
    (2560, 1440, 165),
    (2560, 1440, 240),
    (1920, 1080,  60),
    (1920, 1080,  90),
    (1920, 1080, 120),
    (1920, 1080, 144),
    (1920, 1080, 165),
    (1920, 1080, 240),
    (3440, 1440,  60),
    (3440, 1440,  90),
    (3440, 1440, 120),
    (3440, 1440, 144),
    (3440, 1440, 165),
    (3440, 1440, 240),
    (3840, 2160,  60),
    (3840, 2160,  90),
    (3840, 2160, 120),
    (3840, 2160, 144),
    (3840, 2160, 165),
    (3840, 2160, 240),
]

PREFERRED_INDEX = 0


def mfg_id(code: str) -> int:
    """3 字母厂商码 -> EDID 16-bit（每字母 5 bit，A=1）"""
    v = 0
    for ch in code.upper():
        v = (v << 5) | (ord(ch) - ord('A') + 1)
    return v


def desc_string(tag: int, text: str) -> bytes:
    """EDID 描述符：0xFC=名称, 0xFF=序列号, 0xFE=文本"""
    b = bytearray(18)
    b[0:5] = bytes([0x00, 0x00, 0x00, tag, 0x00])
    t = text.encode('ascii')[:13]
    b[5:5 + len(t)] = t
    if len(t) < 13:
        b[5 + len(t)] = 0x0A          # 换行结尾
        for i in range(5 + len(t) + 1, 18):
            b[i] = 0x20               # 空格填充
    return bytes(b)


def detailed_timing(pixclk_khz: int, hact: int, hblk: int, vact: int, vblk: int,
                    hsync_off: int, hsync_w: int, vsync_off: int, vsync_w: int,
                    hsize_mm: int = 100, vsize_mm: int = 60) -> bytes:
    """标准 detailed timing descriptor（18 字节）"""
    clock = pixclk_khz // 10          # 单位 10kHz
    b = bytearray(18)
    b[0:2] = struct.pack('<H', clock)
    b[2] = hact & 0xFF
    b[3] = hblk & 0xFF
    b[4] = ((hact >> 8) << 4) | ((hblk >> 8) & 0x0F)
    b[5] = vact & 0xFF
    b[6] = vblk & 0xFF
    b[7] = ((vact >> 8) << 4) | ((vblk >> 8) & 0x0F)
    b[8] = hsync_off & 0xFF
    b[9] = hsync_w & 0xFF
    b[10] = ((vsync_off & 0x0F) << 4) | (vsync_w & 0x0F)
    b[11] = 0x00
    b[12] = hsize_mm & 0xFF
    b[13] = vsize_mm & 0xFF
    b[14] = 0x00
    b[15] = 0x00
    b[16] = 0x00
    b[17] = 0x1E                      # 标志（数字分离同步等）
    return bytes(b)


def build_edid() -> bytes:
    e = bytearray(128)

    # --- 头部 ---
    e[0:8] = bytes([0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00])

    # --- 厂商 / 产品 ---
    mfg = mfg_id('CVD')
    e[8] = (mfg >> 8) & 0xFF
    e[9] = mfg & 0xFF
    e[10] = 0x01                      # 产品码低字节
    e[11] = 0x00                      # 产品码高字节 -> 0x0001
    e[12] = 0x01                      # 序列号低
    e[13] = 0x00
    e[14] = 0x00
    e[15] = 0x00
    e[16] = 0x01                      # 生产周
    e[17] = 0x22                      # 1990 + 34 = 2024

    # --- EDID 版本 1.4 ---
    e[18] = 0x01
    e[19] = 0x04

    # --- 基本显示参数 ---
    e[20] = 0xA5                      # 数字输入, 8bit/色, DisplayPort
    e[21] = 0x3C                      # 水平 60cm
    e[22] = 0x22                      # 垂直 34cm (16:9)
    e[23] = 0x78                      # gamma 2.2
    e[24] = 0xFB                      # 特性支持

    # --- 色度坐标（sRGB 近似）---
    e[25] = 0xEE; e[26] = 0x95; e[27] = 0xA3; e[28] = 0x54
    e[29] = 0x4C; e[30] = 0x99; e[31] = 0x26
    e[32] = 0x0F; e[33] = 0x50; e[34] = 0x54

    # --- 建立时间与标准时序 ---
    e[35] = 0x21                      # 建立年份 2021
    e[36] = 0x08
    e[37] = 0x00
    for i in range(38, 54):           # 标准时序留空（模式由驱动模式表提供）
        e[i] = 0x01

    # --- 4 个描述符 ---
    # 说明：驱动侧的 pModeList 才是权威模式来源（ParseMonitorDescription 直接返回它），
    #       这里的 detailed timing 主要用于表达"物理能力"，不决定选中模式。
    #       首选模式由 pModeList[PREFERRED_INDEX] = 2560x1440@144 决定，保持不变。

    # 描述符 1: 2560x1440@60（沿用原始值，避免影响既有选中状态）
    e[54:72] = detailed_timing(
        241500, 2560, 160, 1440, 45,
        hsync_off=48, hsync_w=32, vsync_off=3, vsync_w=5)

    # 描述符 2: 3840x2160@60（新增，标记 4K 能力）
    e[72:90] = detailed_timing(
        594000, 3840, 560, 2160, 90,
        hsync_off=176, hsync_w=88, vsync_off=8, vsync_w=10,
        hsize_mm=160, vsize_mm=90)

    # 描述符 3: 显示器名称
    e[90:108] = desc_string(0xFC, 'CustomVDD')

    # 描述符 4: 范围限制
    #   垂直 48-240 Hz、水平 30-255 kHz、最大像素时钟 2550 MHz
    #   注意：EDID 范围描述符的水平频率与像素时钟字段为 8bit，
    #         故上限分别取 255kHz / 2550MHz（均已为可表示的最大档位）。
    e[108:126] = bytes([
        0x00, 0x00, 0x00, 0xFD, 0x00,   # 范围限制标签
        0x30, 0xF0,                      # 垂直: 48 - 240 Hz
        0x1E, 0xFF,                      # 水平: 30 - 255 kHz
        0xFF,                            # 最大像素时钟 2550 MHz
        0x00,                            # 扩展时序支持
        0x0A,                            # 换行
        0x20, 0x20, 0x20, 0x20, 0x20, 0x20,
    ])

    e[126] = 0x00                     # 扩展块数
    e[127] = (256 - (sum(e[0:127]) % 256)) % 256   # 校验和
    return bytes(e)


def verify(edid: bytes) -> bool:
    ok = True
    if len(edid) != 128:
        print(f'  [错误] 长度 {len(edid)} != 128')
        ok = False
    if sum(edid) % 256 != 0:
        print(f'  [错误] 校验和错误: sum={sum(edid)}')
        ok = False
    return ok


def to_c_array(data: bytes, indent: str = '        ', per_line: int = 16) -> str:
    lines = []
    for i in range(0, len(data), per_line):
        chunk = data[i:i + per_line]
        lines.append(indent + ','.join(f'0x{b:02X}' for b in chunk) + ',')
    return '\n'.join(lines).rstrip(',')


def to_mode_list_cpp() -> str:
    lines = []
    for (w, h, r) in MODES:
        lines.append(f'            {{ {w:4d}, {h:4d}, {r:3d} }},')
    return '\n'.join(lines)


def to_target_modes_cpp() -> str:
    lines = []
    for (w, h, r) in MODES:
        lines.append(f'    TargetModes.push_back(CreateIddCxTargetMode({w}, {h}, {r}));')
    return '\n'.join(lines)


def main():
    edid = build_edid()

    print('=== EDID 校验 ===')
    ok = verify(edid)
    print(f'  长度={len(edid)}  校验和={"OK" if ok else "FAIL"}')

    mfg = (edid[8] << 8) | edid[9]
    name = ''
    for shift in (10, 5, 0):
        name += chr(((mfg >> shift) & 0x1F) + ord('A') - 1)
    print(f'  厂商码={name}  产品码=0x{edid[11]:02X}{edid[10]:02X}')

    for off in (54, 72, 90, 108):
        if edid[off:off + 4] == b'\x00\x00\x00\xFC':
            nm = edid[off + 5:off + 18].split(b'\x0a')[0].decode('ascii', 'replace')
            print(f'  显示器名="{nm}"')

    # 范围限制描述符位于偏移 108，字段相对偏移：
    #   +0..4  00 00 00 FD 00
    #   +5     最小垂直频率 (Hz)
    #   +6     最大垂直频率 (Hz)
    #   +7     最小水平频率 (kHz)
    #   +8     最大水平频率 (kHz)
    #   +9     最大像素时钟 (MHz / 10)
    d = edid
    print(f'  垂直范围: {d[113]}-{d[114]} Hz')
    print(f'  水平范围: {d[115]}-{d[116]} kHz')
    print(f'  最大像素时钟: {d[117] * 10} MHz')
    print()
    print(f'=== 模式表（共 {len(MODES)} 项，preferred 索引 {PREFERRED_INDEX}）===')
    for i, (w, h, r) in enumerate(MODES):
        mark = '  <- preferred' if i == PREFERRED_INDEX else ''
        print(f'  [{i:2d}] {w}x{h} @ {r}Hz{mark}')

    if not ok:
        print()
        print('EDID 校验未通过，终止。')
        sys.exit(1)

    # 输出到文件
    with open('custom_edid.txt', 'w', encoding='utf-8') as f:
        f.write(to_c_array(edid))
    with open('mode_list.txt', 'w', encoding='utf-8') as f:
        f.write(to_mode_list_cpp())
    with open('target_modes.txt', 'w', encoding='utf-8') as f:
        f.write(to_target_modes_cpp())

    print()
    print('已生成:')
    print('  custom_edid.txt     EDID 的 C 数组')
    print('  mode_list.txt       pModeList 条目')
    print('  target_modes.txt    TargetModes 条目')


if __name__ == '__main__':
    main()
