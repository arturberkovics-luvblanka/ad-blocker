#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
echo 'A tesztoldal címe: http://127.0.0.1:8765/'
echo 'Nyisd meg Safariban, vagy kattints az alkalmazás Tesztoldal megnyitása gombjára.'
echo 'Leállítás: Ctrl+C vagy ennek az ablaknak a bezárása.'
python3 "$PROJECT_DIR/code/scripts/serve_fixture.py"
