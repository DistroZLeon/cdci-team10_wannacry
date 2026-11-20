#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# == 1 && $1 == --help ]]; then
    printf 'Usage: bash infrastructure/test.sh\n'
    printf 'Validates script syntax and topology arguments without starting the lab.\n'
    exit 0
fi
if [[ $# != 0 ]]; then
    printf 'ERROR: test.sh takes no arguments.\n' >&2
    exit 2
fi

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

fail=0

# 1. Bash syntax of every script
for script in "$ROOT"/infrastructure/*.sh; do
    if ! bash -n "$script"; then
        printf 'FAIL syntax: %s\n' "$script" >&2
        fail=1
    else
        printf 'PASS syntax: %s\n' "$(basename "$script")"
    fi
done

# 2. topology.py must expose the flags run.sh passes
TOPO="$ROOT/infrastructure/topology.py"
[[ -f "$TOPO" ]] || { echo "FAIL: topology.py missing" >&2; exit 1; }

for flag in --offline --windows-image --victim-ip --hold; do
    if python3 - "$TOPO" "$flag" <<'PY'
import sys
src = open(sys.argv[1]).read()
sys.exit(0 if sys.argv[2] in src else 1)
PY
    then
        printf 'PASS flag present: %s\n' "$flag"
    else
        printf 'FAIL flag missing in topology.py: %s\n' "$flag" >&2
        fail=1
    fi
done

# 3. Dockerfile must include the exploit path
DF="$ROOT/infrastructure/Dockerfile"
if grep -q 'AutoBlue-MS17-010' "$DF"; then
    printf 'PASS Dockerfile references AutoBlue\n'
else
    printf 'FAIL Dockerfile does not clone AutoBlue\n' >&2
    fail=1
fi

# 4. QEMU command must contain no duplicate -cpu flag
if python3 - "$TOPO" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
# find the qemu cmd list literal
m = re.search(r'cmd\s*=\s*\[(.*?)\]', src, re.S)
if not m:
    sys.exit(1)
cpu_count = m.group(1).count('"-cpu"')
sys.exit(0 if cpu_count <= 1 else 1)
PY
then
    printf 'PASS no duplicate -cpu in qemu command\n'
else
    printf 'FAIL duplicate -cpu flag in launch_windows\n' >&2
    fail=1
fi

if [[ $fail -ne 0 ]]; then
    printf '\nOne or more checks failed.\n' >&2
    exit 1
fi

printf '\nAll static checks passed.\n'

# 5. Unit tests, only if the suite exists
if [[ -d "$ROOT/tests" ]]; then
    cd "$ROOT"
    if ! python3 -B -m unittest discover -s tests -v; then
        fail=1
    fi
fi

if [[ $fail -ne 0 ]]; then
    printf '\nOne or more checks failed.\n' >&2
    exit 1
fi

printf '\nAll checks passed.\n'