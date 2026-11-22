#!/usr/bin/env python3
"""保证 libmpv.so 的 DT_NEEDED 里有 libc++_shared.so。

为什么需要这一步：third_party/ohos-libmpv 里的预编译 libmpv.so 链接时没有把
C++ 运行时声明成依赖（DT_NEEDED 只有 libohaudio.so 和 libc.so），但它导入了
std::__n1::to_chars(char*, char*, float/double) 这类只在 libc++ 里定义的符号。
结果就是把 libc++_shared.so 放在同一目录也不够——运行时 linker 只在 libmpv 自己
的依赖域里找符号，找不到就 dlopen 失败，应用落到「PlaybackEngineUnavailable」。
（v6.0.2 的 HAP 就是这么挂的。）

脚本就地修复：把 dynstr 尾部 "libc.so\0libmpv.so\0" 这段改写成
"libc++_shared.so\0"，让原本指向 libc.so 的 NEEDED 改指 libc++；被毁掉的
SONAME 槽改成 DT_DEBUG（linker 只对可执行文件解释这个标签，共享库上等于空操作，
名字缺失时 linker 直接用文件名兜底）。
丢掉显式的 libc.so 依赖是安全的：libc 永远在进程的全局符号域里（libapp.so 已经
声明过），libmpv 的 memcpy/malloc 之类照常解析。

对已经修好的库是空操作，可重复执行；遇到没见过的布局直接非零退出，绝不悄悄产出
一个装不上的 HAP。

用法: fix-libmpv-needed.py <libmpv.so> [...]
"""

from __future__ import annotations

import struct
import sys

DT_NEEDED = 1
DT_STRTAB = 5
DT_STRSZ = 10
DT_SONAME = 14
DT_DEBUG = 21

WANT = b"libc++_shared.so"


class ElfError(RuntimeError):
    pass


def _u(fmt: str, data: bytes, off: int):
    return struct.unpack_from(fmt, data, off)


def read_dynamic(data: bytes):
    """返回 (strab_off, strsz, dynamic_entries[(tag, val, 文件偏移)])。"""
    if data[:4] != b"\x7fELF" or data[4] != 2 or data[5] != 1:
        raise ElfError("不是 ELF64 小端文件")

    e_phoff, = _u("<Q", data, 0x20)
    e_phentsize, e_phnum = _u("<HH", data, 0x36)

    dyn_off = None
    for i in range(e_phnum):
        base = e_phoff + i * e_phentsize
        p_type, = _u("<I", data, base)
        if p_type == 2:  # PT_DYNAMIC
            p_offset, = _u("<Q", data, base + 0x08)
            p_filesz, = _u("<Q", data, base + 0x20)
            dyn_off = (p_offset, p_filesz)
            break
    if dyn_off is None:
        raise ElfError("没有 PT_DYNAMIC")

    off, size = dyn_off
    entries = []
    strtab = strsz = None
    for i in range(size // 16):
        base = off + i * 16
        tag, val = _u("<qQ", data, base)
        if tag == 0:  # DT_NULL
            break
        entries.append((tag, val, base))
        if tag == DT_STRTAB:
            strtab = val
        elif tag == DT_STRSZ:
            strsz = val
    if strtab is None or strsz is None:
        raise ElfError("缺少 DT_STRTAB / DT_STRSZ")
    return strtab, strsz, entries


def dynstr(data: bytes, strtab: int, strsz: int) -> bytes:
    # 段的 vaddr 与文件偏移在这个库里恰好相等；用 program header 换算更稳妥。
    e_phoff, = _u("<Q", data, 0x20)
    e_phentsize, e_phnum = _u("<HH", data, 0x36)
    for i in range(e_phnum):
        base = e_phoff + i * e_phentsize
        p_type, = _u("<I", data, base)
        if p_type != 1:  # PT_LOAD
            continue
        p_offset, = _u("<Q", data, base + 0x08)
        p_vaddr, = _u("<Q", data, base + 0x10)
        p_filesz, = _u("<Q", data, base + 0x20)
        if p_vaddr <= strtab < p_vaddr + p_filesz:
            return data[p_offset + (strtab - p_vaddr): p_offset + (strtab - p_vaddr) + strsz]
    raise ElfError("DT_STRTAB 不在任何 PT_LOAD 里")


def cstr(table: bytes, off: int) -> bytes:
    end = table.find(b"\0", off)
    if end < 0:
        raise ElfError(f"字符串在偏移 {off:#x} 没有结束符")
    return table[off:end]


def main(path: str) -> int:
    data = bytearray(open(path, "rb").read())
    strtab, strsz, entries = read_dynamic(data)
    table = dynstr(bytes(data), strtab, strsz)

    needed = [(val, base) for tag, val, base in entries if tag == DT_NEEDED]
    names = [cstr(table, val).decode("utf-8", "replace") for val, _ in needed]
    if WANT.decode() in names:
        print(f"{path}: 已声明 {WANT.decode()}，无需修改")
        return 0
    if "libohaudio.so" not in names:
        raise ElfError(f"NEEDED={names}，不符合预期（缺 libohaudio.so）")

    def place_string(slot_offset: int, require_empty: bool = True) -> None:
        """把 WANT 写进 dynstr 的 slot_offset（相对 STRTAB）。"""
        nonlocal data
        need = len(WANT) + 1
        if slot_offset + need > strsz:
            raise ElfError("预留区放不下 libc++_shared.so")
        if require_empty and any(table[slot_offset: slot_offset + need - 1]):
            raise ElfError("预留区不是空的")
        # 用 PT_LOAD 把相对偏移换算成文件偏移
        e_phoff, = _u("<Q", data, 0x20)
        e_phentsize, e_phnum = _u("<HH", data, 0x36)
        for i in range(e_phnum):
            base = e_phoff + i * e_phentsize
            if _u("<I", data, base)[0] != 1:
                continue
            p_offset, = _u("<Q", data, base + 0x08)
            p_vaddr, = _u("<Q", data, base + 0x10)
            p_filesz, = _u("<Q", data, base + 0x20)
            if p_vaddr <= strtab < p_vaddr + p_filesz:
                file_off = p_offset + (strtab - p_vaddr) + slot_offset
                data[file_off: file_off + need] = WANT + b"\0"
                return
        raise ElfError("无法换算字符串表偏移")

    # 方案 A：dynstr 尾部还有空位 —— 直接追加，不破坏任何已有字符串。
    tail = len(table)
    while tail > 0 and table[tail - 1] == 0:
        tail -= 1
    free = strsz - tail
    spare = [base for tag, val, base in entries if tag == DT_SONAME]
    if free >= len(WANT) + 1 and spare:
        place_string(tail)
        # SONAME 槽改造成额外的 NEEDED
        base = spare[0]
        struct.pack_into("<qQ", data, base, DT_NEEDED, tail)
        print(f"{path}: 在 dynstr 尾部追加 {WANT.decode()}，复用 SONAME 槽")
        print(f"{path}: DT_NEEDED -> {names + [WANT.decode()]}")
        open(path, "wb").write(data)
        return 0

    # 方案 B：dynstr 没空位，但 "libc.so\0libmpv.so\0" 连在一起 —— 改写这一段。
    libc = next(((val, base) for val, base in needed if cstr(table, val) == b"libc.so"), None)
    soname = next(((val, base) for tag, val, base in entries if tag == DT_SONAME), None)
    if libc and soname:
        start, end = libc[0], soname[0] + len(cstr(table, soname[0])) + 1
        if end - start >= len(WANT) + 1:
            place_string(start, require_empty=False)
            struct.pack_into("<qQ", data, libc[1], DT_NEEDED, start)   # 本来就指向 start
            struct.pack_into("<qQ", data, soname[1], DT_DEBUG, 0)      # 名字已不存在
            print(f"{path}: 用 'libc.so' 槽位改写为 {WANT.decode()}，SONAME 槽改为 DT_DEBUG")
            print(f"{path}: DT_NEEDED -> {['libohaudio.so', WANT.decode()]}")
            open(path, "wb").write(data)
            return 0

    raise ElfError(
        "dynstr 既没有尾部空位，也没有可合并的 'libc.so'+SONAME 槽位；"
        "请重新链接 libmpv（target_link_libraries(... c++_shared)）而不是改二进制"
    )


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    rc = 0
    for p in sys.argv[1:]:
        try:
            main(p)
        except ElfError as exc:
            print(f"{p}: {exc}", file=sys.stderr)
            rc = 1
    sys.exit(rc)
