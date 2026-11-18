"""Accent selection and rendering for installer-managed files."""
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tomllib

# Main accent, text, and secondary accent.
PALETTES = {
    'teal': ('77D7CF', 'B0E4E1', '63C4F0'),
    'blue': ('68ADFF', 'B3D6FF', '508FF0'),
    'cyan': ('68D6F4', 'B4EDFB', '4EB7DD'),
    'green': ('83D899', 'BCEAC7', '59BA78'),
    'lime': ('B9D775', 'DFEBB0', '91B650'),
    'yellow': ('EAD078', 'F5E6AE', 'D5B34E'),
    'orange': ('F6A675', 'FFD4B8', 'E88655'),
    'red': ('F58F98', 'FAC3C8', 'D66C79'),
    'purple': ('BDABFF', 'DDD3FF', 'A68CEB'),
}

MINI_CONFIG = Path('.config/fastfetch/mini.jsonc')
MINI_PANEL = Path('.config/fastfetch/mini-panel.py')
CODEX_THEME = Path('.codex/themes/omarchy-tweaks.tmTheme')
CODEX_CONFIG = Path('.codex/config.toml')


def choose_accent():
    if not (sys.stdin.isatty() and sys.stdout.isatty()):
        return 'teal'
    if shutil.which('gum'):
        result = subprocess.run(
            ['gum', 'choose', '--header', 'Accent for Fastfetch and Codex', '--selected', 'teal', *PALETTES],
            stdout=subprocess.PIPE, text=True,
        )
        if result.returncode == 0 and result.stdout.strip() in PALETTES:
            return result.stdout.strip()
        raise SystemExit('Accent selection cancelled. No files changed.')
    options = list(PALETTES)
    for number, name in enumerate(options, 1):
        print(f'{number}. {name}')
    while True:
        answer = input('Accent [1 = teal]: ').strip() or '1'
        if answer in [str(n) for n in range(1, len(options) + 1)]:
            return options[int(answer) - 1]


def rgb(hex_color):
    return ';'.join(str(value) for value in bytes.fromhex(hex_color))


def render_accent(rel, text, accent):
    main, light, secondary = PALETTES[accent]
    if rel == MINI_CONFIG:
        return text.replace('#68adff', '#' + main).replace('#b3d6ff', '#' + light).replace('#508ff0', '#' + secondary)
    if rel == MINI_PANEL:
        return text.replace('104;173;255', rgb(main)).replace('179;214;255', rgb(light))
    return text.replace('Omarchy Blue-Green', f'Omarchy Tweaks ({accent})').replace('#77D7CF', '#' + main).replace('#8DE2DA', '#' + light).replace('#63C4F0', '#' + secondary)


def codex_config(text):
    current = tomllib.loads(text)
    setting = 'theme = "omarchy-tweaks"'
    if 'tui' not in current:
        result = text.rstrip() + '\n\n[tui]\n' + setting + '\n'
    else:
        section = re.search(r'(?m)^[ \t]*\[tui\][ \t]*(?:#.*)?\n?(.*?)(?=^[ \t]*\[|\Z)', text, re.S | re.M)
        if section is None:
            raise ValueError('Expected a [tui] table in Codex config')
        body = section[1]
        if 'theme' in current['tui']:
            body, count = re.subn(r'(?m)^[ \t]*(?:theme|"theme"|\'theme\')[ \t]*=.*$', setting, body, count=1)
            if not count:
                raise ValueError('Expected a theme setting in the Codex [tui] table')
        else:
            body = body.rstrip() + '\n' + setting + '\n'
        result = text[:section.start(1)].rstrip('\n') + '\n' + body.lstrip('\n') + text[section.end(1):]
    current.setdefault('tui', {})['theme'] = 'omarchy-tweaks'
    if tomllib.loads(result) != current:
        raise ValueError('Updating the Codex theme would change other settings')
    return result.lstrip('\n')
