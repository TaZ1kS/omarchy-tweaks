#!/usr/bin/env python3
"""Install reviewed desktop customization files with a reversible backup."""
import argparse
import datetime
import json
import os
from pathlib import Path
import shutil
import subprocess

from accents import CODEX_CONFIG, CODEX_THEME, MINI_CONFIG, MINI_PANEL, PALETTES
from accents import choose_accent, codex_config, render_accent

ROOT = Path(__file__).resolve().parent

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--hardware', action='store_true', help='Also install the original physical monitor layout and Sunshine unit')
    parser.add_argument('--target-home', type=Path, default=Path.home(), help='Alternative home directory, e.g. for testing')
    parser.add_argument('--restore', type=Path, help='Restore a backup created by this installer')
    parser.add_argument('--accent', choices=PALETTES, help='Accent for Fastfetch and Codex CLI (default: teal)')
    args = parser.parse_args()
    target = args.target_home.expanduser().resolve()
    if args.restore:
        backup = args.restore.expanduser().resolve()
        manifest = json.loads((backup / 'manifest.json').read_text())
        if manifest['home'] != str(target):
            parser.error('Backup belongs to another target home')
        for record in reversed(manifest['files']):
            rel = Path(record['path'])
            if rel.is_absolute() or '..' in rel.parts:
                parser.error('Invalid path in backup')
            dest = target / rel
            print('restore', rel)
            if args.dry_run:
                continue
            if record['existed']:
                source = backup / 'files' / rel
                if dest.is_symlink():
                    dest.unlink()
                dest.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source, dest, follow_symlinks=False)
            elif dest.exists() or dest.is_symlink():
                dest.unlink()
        return
    if target == Path.home().resolve() and not shutil.which('omarchy'):
        parser.error('This installer requires Omarchy with the Lua Hyprland/Quickshell shell')
    files = {f.relative_to(ROOT / 'payload'): f for f in (ROOT / 'payload').rglob('*') if f.is_file()}
    if args.hardware:
        files.update({f.relative_to(ROOT / 'hardware'): f for f in (ROOT / 'hardware').rglob('*') if f.is_file()})
    # A clean system still needs this module; preserve existing monitor layout otherwise.
    monitor = Path('.config/hypr/monitors.lua')
    if monitor not in files and not (target / monitor).exists():
        files[monitor] = ROOT / 'portable-monitors.lua'
    files[CODEX_CONFIG] = None
    # Check all destinations before changing anything; reject links into another tree.
    for rel in files:
        dest = target / rel
        if not dest.parent.resolve().is_relative_to(target):
            parser.error(f'Destination escapes target home: {rel}')
        if dest.exists() and dest.is_dir():
            parser.error(f'Destination is a directory: {rel}')
    accent = args.accent or (None if args.dry_run else choose_accent()) or 'teal'
    print(f'Accent: {accent}')
    rendered = {
        rel: render_accent(rel, files[rel].read_text(), accent)
        for rel in (MINI_CONFIG, MINI_PANEL, CODEX_THEME)
    }
    config = target / CODEX_CONFIG
    try:
        rendered[CODEX_CONFIG] = codex_config(config.read_text() if config.exists() else '')
    except ValueError as error:
        parser.error(f'{CODEX_CONFIG}: {error}')
    stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f')
    backup = target / '.local/state/omarchy-tweaks/backups' / stamp
    manifest = {'home': str(target), 'files': []}
    if not args.dry_run:
        backup.mkdir(parents=True)
    for rel, source in sorted(files.items()):
        dest = target / rel
        print('install', rel)
        if args.dry_run:
            continue
        existed = dest.exists() or dest.is_symlink()
        if existed:
            saved = backup / 'files' / rel
            saved.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(dest, saved, follow_symlinks=False)
        manifest['files'].append({'path': str(rel), 'existed': existed})
        (backup / 'manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
        dest.parent.mkdir(parents=True, exist_ok=True)
        if dest.is_symlink():
            dest.unlink()
        if rel in rendered:
            dest.write_text(rendered[rel])
            if rel == CODEX_CONFIG:
                dest.chmod(0o600)
        else:
            shutil.copy2(source, dest)
    if args.dry_run:
        print('Dry run: no files changed.')
        return
    print(f'Backup: {backup}')
    print(f'Restore: python3 install.py --restore {backup}')
    if target == Path.home().resolve():
        for command in (['hyprctl', 'reload'], ['hyprctl', 'configerrors'], ['omarchy-shell', 'shell', 'rescanPlugins']):
            if shutil.which(command[0]):
                result = subprocess.run(command, capture_output=True, text=True)
                print(' '.join(command)+': '+(result.stdout+result.stderr).strip())
                if result.returncode:
                    print('Live reload unavailable; log out and back in to load all changes.')
    print('Installed. See README.md for optional dependencies and hardware settings.')

if __name__ == '__main__':
    main()
