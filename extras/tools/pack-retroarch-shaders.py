#!/usr/bin/env python3
"""Build PowerVLC's seekable RetroArch resource catalogue.

The payload is intentionally stored rather than compressed: NSIS/ZIP already
compresses the outer artifact, while fixed offsets let the renderer read one
shader or LUT without unpacking 20+ MB to disk. All integers are little-endian.
"""

import argparse
import os
from pathlib import Path
import struct
import tempfile


MAGIC = b"PVLCRA1\0"
HEADER = struct.Struct("<8sI")
ENTRY = struct.Struct("<HHQQ")


def collect(root: Path, output: Path):
    files = []
    for path in root.rglob("*"):
        if not path.is_file() or path.resolve() == output.resolve():
            continue
        relative = path.relative_to(root).as_posix()
        encoded = relative.encode("utf-8")
        if not encoded or len(encoded) > 0xFFFF:
            raise ValueError(f"invalid catalogue path: {relative!r}")
        if relative.startswith("/") or ".." in Path(relative).parts:
            raise ValueError(f"unsafe catalogue path: {relative!r}")
        files.append((relative, encoded, path, path.stat().st_size))
    files.sort(key=lambda item: item[0])
    if not files:
        raise ValueError(f"no resources found under {root}")
    return files


def write_catalogue(root: Path, output: Path):
    files = collect(root, output)
    table_size = HEADER.size + sum(ENTRY.size + len(item[1]) for item in files)
    offset = table_size
    entries = []
    for relative, encoded, path, size in files:
        entries.append((relative, encoded, path, size, offset))
        offset += size

    output.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(
        prefix=output.name + ".", suffix=".tmp", dir=str(output.parent))
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(HEADER.pack(MAGIC, len(entries)))
            for _relative, encoded, _path, size, data_offset in entries:
                stream.write(ENTRY.pack(len(encoded), 0, data_offset, size))
                stream.write(encoded)
            for _relative, _encoded, path, _size, _offset in entries:
                with path.open("rb") as source:
                    while True:
                        chunk = source.read(1024 * 1024)
                        if not chunk:
                            break
                        stream.write(chunk)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, output)
    except BaseException:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise
    return entries


def verify_catalogue(output: Path, expected):
    with output.open("rb") as stream:
        magic, count = HEADER.unpack(stream.read(HEADER.size))
        if magic != MAGIC or count != len(expected):
            raise ValueError("catalogue header verification failed")
        actual = []
        for _ in range(count):
            raw = stream.read(ENTRY.size)
            if len(raw) != ENTRY.size:
                raise ValueError("truncated catalogue index")
            path_length, flags, offset, size = ENTRY.unpack(raw)
            encoded = stream.read(path_length)
            if flags or len(encoded) != path_length:
                raise ValueError("invalid catalogue index entry")
            actual.append((encoded.decode("utf-8"), offset, size))
        archive_size = output.stat().st_size
        for index, ((relative, _encoded, path, size, expected_offset),
                    (actual_path, actual_offset, actual_size)) in enumerate(
                        zip(expected, actual)):
            if (actual_path, actual_offset, actual_size) != (
                    relative, expected_offset, size):
                raise ValueError(f"catalogue index mismatch at entry {index}")
            if actual_offset + actual_size > archive_size:
                raise ValueError(f"catalogue entry outside payload: {relative}")
            stream.seek(actual_offset)
            with path.open("rb") as source:
                while True:
                    wanted = source.read(1024 * 1024)
                    if not wanted:
                        break
                    if stream.read(len(wanted)) != wanted:
                        raise ValueError(f"catalogue data mismatch: {relative}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path,
                        help="retroarch-shaders directory to pack")
    parser.add_argument("output", type=Path,
                        help="output retroarch-shaders.pak")
    args = parser.parse_args()
    source = args.source.resolve()
    output = args.output.resolve()
    if not source.is_dir():
        parser.error(f"source is not a directory: {source}")
    entries = write_catalogue(source, output)
    verify_catalogue(output, entries)
    payload = sum(item[3] for item in entries)
    print(f"packed {len(entries)} RetroArch resources "
          f"({payload} bytes) into {output}")


if __name__ == "__main__":
    main()
