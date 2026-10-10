#!/usr/bin/env python3
"""Retain our own seven-day daily archives and one archive per last four ISO weeks."""
import argparse
from datetime import datetime, timedelta, timezone
from pathlib import Path
import re

parser = argparse.ArgumentParser()
parser.add_argument('--directory', type=Path, default=Path('backups'))
parser.add_argument('--apply', action='store_true', help='Default only lists proposed removals')
args = parser.parse_args()
now = datetime.now(timezone.utc)
archives = []
for path in args.directory.glob('miaoban-*.dump'):
    match = re.fullmatch(r'miaoban-(\d{8}T\d{6}Z)\.dump', path.name)
    if match and path.is_file() and not path.is_symlink():
        archives.append((datetime.strptime(match[1], '%Y%m%dT%H%M%SZ').replace(tzinfo=timezone.utc), path))
archives.sort(reverse=True)
keep = {path for at, path in archives if at >= now - timedelta(days=7)}
weeks = {}
current_week = now.date() - timedelta(days=now.weekday())
for at, path in archives:
    week = at.date() - timedelta(days=at.weekday())
    if 0 <= (current_week - week).days < 28:
        weeks.setdefault(week, path)
keep.update(weeks.values())
for _, path in archives:
    if path not in keep:
        print(('remove' if args.apply else 'would remove'), path.name)
        if args.apply:
            path.unlink()
            checksum = path.with_suffix('.dump.sha256')
            if checksum.is_file() and not checksum.is_symlink():
                checksum.unlink()
