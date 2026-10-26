#!/usr/bin/env python3
"""Print a TrueType/OpenType font's PostScript name (name table, nameID 6).

iOS looks fonts up by PostScript name, Android by file name. Naming the file after the
PostScript name makes one `fontFamily` string work on both.

Usage: ttf-name.py <font.ttf>
"""
import struct
import sys


def postscript_name(path):
    with open(path, "rb") as f:
        data = f.read()
    num_tables = struct.unpack(">H", data[4:6])[0]
    for i in range(num_tables):
        tag, _, offset, _ = struct.unpack(">4sIII", data[12 + 16 * i:28 + 16 * i])
        if tag != b"name":
            continue
        _, count, string_offset = struct.unpack(">HHH", data[offset:offset + 6])
        for j in range(count):
            rec = offset + 6 + 12 * j
            platform, encoding, _, name_id, length, str_off = struct.unpack(">HHHHHH", data[rec:rec + 12])
            if name_id != 6:
                continue
            raw = data[offset + string_offset + str_off:offset + string_offset + str_off + length]
            # Windows/Unicode platforms store UTF-16BE; Mac Roman otherwise.
            return raw.decode("utf-16-be") if platform in (0, 3) else raw.decode("latin-1")
    sys.exit(f"{path}: no PostScript name found")


if __name__ == "__main__":
    print(postscript_name(sys.argv[1]))
