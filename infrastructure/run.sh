#!/usr/bin/env bash
set -Eeuo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
PYTHON=/opt/cdci-wannacry/venv/bin/python
WIN7_IMAGE=/opt/cdci-wannacry/win7.qcow2
VICTIM_IP="${VICTIM_IP:-10.0.0.3}"

[[ $EUID -eq 0 ]] || { echo "Run with sudo." >&2; exit 1; }
[[ -x "$PYTHON" ]] || { echo "Run install.sh first (no venv at $PYTHON)." >&2; exit 1; }
[[ -f "$WIN7_IMAGE" ]] || { echo "Windows image missing: $WIN7_IMAGE. Run install.sh." >&2; exit 1; }

exec "$PYTHON" -u "$ROOT/infrastructure/topology.py" \
    --offline \
    --windows-image "$WIN7_IMAGE" \
    --victim-ip "$VICTIM_IP" \
    "$@"