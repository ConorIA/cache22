#!/usr/bin/env python3
"""Rewrite every cpio entry's mtime in a dracut-produced initramfs.img.

dracut --reproducible doesn't fully normalize source-file mtimes — files
older than its tmp initdir keep whatever mtime they had on the build
host filesystem, so two consecutive builds emit cpio archives with
millions of differing bytes (per-entry mtime fields are scattered
throughout).

Touching files in /usr before dracut would trigger overlayfs copy-up
during builds and break hardlinks. Post-processing the produced
initramfs.img avoids that: we walk the cpio frame-by-frame, rewrite
the c_mtime field of each newc header to SOURCE_DATE_EPOCH, and write
the file back. The dracut output format is:

    [early-cpio uncompressed]  +  [main-cpio compressed with zstd]

Both halves are normalized.
"""
import os
import struct
import subprocess
import sys
from pathlib import Path


def parse_cpio_end(data: bytes, start: int) -> int:
    """Return the byte offset just past the TRAILER!!! of a cpio archive
    that begins at `start`. Returns the unpadded end + 512-byte alignment
    (matching kernel/dracut conventions for early-cpio padding)."""
    pos = start
    while True:
        if data[pos:pos + 6] != b"070701":
            return pos
        namesize = int(data[pos + 94:pos + 102], 16)
        filesize = int(data[pos + 54:pos + 62], 16)
        name_end = pos + 110 + namesize
        name_end = (name_end + 3) & ~3
        name = data[pos + 110:pos + 110 + namesize - 1]
        if name == b"TRAILER!!!":
            end = name_end
            return (end + 511) & ~511
        pos = (name_end + filesize + 3) & ~3


def rewrite_cpio_mtimes(data: bytes, mtime: int) -> bytes:
    """Walk the cpio archive in `data` and overwrite every entry's
    c_mtime field (an 8-char ASCII hex starting at offset 46 of each
    110-byte newc header) with `mtime`. Returns the rewritten bytes."""
    mtime_hex = f"{mtime:08x}".encode("ascii")
    assert len(mtime_hex) == 8
    out = bytearray(data)
    pos = 0
    while pos + 110 <= len(out):
        if out[pos:pos + 6] != b"070701":
            # past last entry (could be padding); stop
            break
        namesize = int(bytes(out[pos + 94:pos + 102]), 16)
        filesize = int(bytes(out[pos + 54:pos + 62]), 16)
        # rewrite mtime
        out[pos + 46:pos + 54] = mtime_hex
        name_end = pos + 110 + namesize
        name_end = (name_end + 3) & ~3
        name = bytes(out[pos + 110:pos + 110 + namesize - 1])
        if name == b"TRAILER!!!":
            break
        pos = (name_end + filesize + 3) & ~3
    return bytes(out)


def main() -> None:
    if len(sys.argv) != 3:
        print("usage: normalize-initramfs-mtimes.py <initramfs.img> <epoch>",
              file=sys.stderr)
        sys.exit(2)
    img_path = Path(sys.argv[1])
    mtime = int(sys.argv[2])

    data = img_path.read_bytes()
    early_end = parse_cpio_end(data, 0)

    early = bytes(rewrite_cpio_mtimes(data[:early_end], mtime))
    # The early region is padded to 512; preserve any trailing zeros
    # exactly so the byte length doesn't shift.
    if len(early) < early_end:
        early = early + b"\x00" * (early_end - len(early))

    # Decompress the main archive (zstd), rewrite, recompress matching
    # dracut's --zstd invocation (zstd -10 -q -T0).
    main_compressed = data[early_end:]
    decompressed = subprocess.check_output(
        ["zstd", "-dc"], input=main_compressed,
    )
    main_rewritten = rewrite_cpio_mtimes(decompressed, mtime)
    main_recompressed = subprocess.check_output(
        ["zstd", "-T0", "--quiet", "--stdout", "-10"],
        input=main_rewritten,
    )

    img_path.write_bytes(early + main_recompressed)
    print(f"    normalized cpio mtimes in {img_path} "
          f"(early={len(early)}, main={len(main_recompressed)})")


if __name__ == "__main__":
    main()
