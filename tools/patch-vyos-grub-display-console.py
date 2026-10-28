#!/usr/bin/env python3
"""Keep an HDMI console=tty0 ahead of the serial console in VyOS GRUB entries.

The serial console stays last, so it remains /dev/console.
"""

from __future__ import annotations

import argparse
from pathlib import Path


SERIAL_OPTS = (
    'set console_opts="console=${console_type}${console_num},${console_speed}"'
)
DISPLAY_SERIAL_OPTS = (
    'set console_opts="console=tty0 console=${console_type}${console_num},${console_speed}"'
)


def patch(path: Path) -> bool:
    if not path.is_file():
        raise SystemExit(f"GRUB file is missing: {path}")

    text = path.read_text()

    if DISPLAY_SERIAL_OPTS in text:
        return False

    if text.count(SERIAL_OPTS) != 1:
        raise SystemExit(
            f"GRUB file no longer matches the expected serial console_opts line: {path}"
        )

    path.write_text(text.replace(SERIAL_OPTS, DISPLAY_SERIAL_OPTS))
    return True


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("files", nargs="+", type=Path)
    args = parser.parse_args()

    for path in args.files:
        state = "patched" if patch(path) else "already patched"
        print(f"GRUB display console: {state}: {path}")


if __name__ == "__main__":
    main()
