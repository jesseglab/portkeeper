#!/usr/bin/env python3
"""Reject local runtime files and absolute home paths in release source or bundles."""
from pathlib import Path
import re
import sys

root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent
skip = {'.git', '.build', '.swiftpm', '.module-cache', 'dist', '__pycache__'}
private_names = {'configs.json', 'portkeeper.json', 'notchwork.json', 'connection.json'}
issues = []
count = 0
for path in root.rglob('*'):
    relative = path.relative_to(root)
    if any(part in skip for part in relative.parts) or not path.is_file():
        continue
    count += 1
    if (path.name in private_names or path.name == '.env' or path.name.startswith('.env.')
            or path.suffix == '.log' or path.name.endswith(('.local.json', '.local.plist'))
            or 'Logs' in relative.parts or 'xcuserdata' in relative.parts):
        issues.append(f'{relative}: local runtime/settings file')
    # Also scan executables: compiler paths must not disclose a developer home directory.
    if re.search(rb'/(?:Users|home)/[^/\s\x00]+/', path.read_bytes()):
        issues.append(f'{relative}: absolute home-directory path')
if issues:
    print('\n'.join(issues), file=sys.stderr)
    sys.exit(1)
print(f'Privacy check passed: {count} files, no runtime settings or absolute home paths.')
