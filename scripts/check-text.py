#!/usr/bin/env python3
"""Reject non-ASCII text in tracked source, tests and documentation."""
from pathlib import Path
import subprocess
import sys

files = subprocess.check_output(['git', 'ls-files', '-z']).decode().split('\0')
errors = []
for name in filter(None, files):
    for number, line in enumerate(Path(name).read_text(encoding='utf-8').splitlines(), 1):
        if not line.isascii():
            errors.append(f'{name}:{number}: non-ASCII text')
if errors:
    sys.exit('\n'.join(errors))
print('All tracked text is ASCII.')
