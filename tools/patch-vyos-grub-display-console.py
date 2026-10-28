#!/usr/bin/env python3
"""Add an HDMI console=tty0 next to the serial console in VyOS GRUB entries.

The last console= is the primary one (/dev/console, systemd status). By
default the serial console stays last; --primary display puts tty0 last.
"""

from __future__ import annotations

import argparse
from pathlib import Path


SERIAL = "console=${console_type}${console_num},${console_speed}"
SERIAL_OPTS = f'set console_opts="{SERIAL}"'
PATCHED_OPTS = {
    "serial": f'set console_opts="console=tty0 {SERIAL}"',
    "display": f'set console_opts="{SERIAL} console=tty0"',
}


def patch(path: Path, primary: str) -> bool:
    if not path.is_file():
        raise SystemExit(f"GRUB file is missing: {path}")

    text = path.read_text()
    wanted = PATCHED_OPTS[primary]

    if wanted in text:
        return False

    if text.count(SERIAL_OPTS) != 1:
        raise SystemExit(
            f"GRUB file no longer matches the expected serial console_opts line: {path}"
        )

    path.write_text(text.replace(SERIAL_OPTS, wanted))
    return True


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--primary", choices=sorted(PATCHED_OPTS), default="serial")
    parser.add_argument("files", nargs="+", type=Path)
    args = parser.parse_args()

    for path in args.files:
        state = "patched" if patch(path, args.primary) else "already patched"
        print(f"GRUB display console ({args.primary} primary): {state}: {path}")


if __name__ == "__main__":
    main()
