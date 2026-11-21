#!/usr/bin/env bash
set -Eeuo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
STATE=/opt/cdci-wannacry

[[ $EUID -eq 0 ]] || { echo "Run with sudo in the dedicated VM." >&2; exit 1; }

# --- system packages ---
apt-get update
apt-get install -y \
    python3-venv docker.io openvswitch-switch \
    qemu-system-x86 qemu-utils cpu-checker dnsmasq unzip p7zip-full \
    net-tools iproute2 curl jq gdown make build-essential

# --- venv + requirements ---
install -d -m 0755 "$STATE"
[[ -d "$STATE/venv" ]] || python3 -m venv "$STATE/venv"
"$STATE/venv/bin/pip" install --upgrade pip
"$STATE/venv/bin/pip" install -r "$ROOT/infrastructure/requirements.txt"

# --- compile mnexec from the editable Containernet checkout ---
# pip -e git+... installs the source into $VENV/src/mininet
MININET_SRC="$STATE/venv/src/mininet"
[[ -d "$MININET_SRC" ]] || { echo "Containernet source not found at $MININET_SRC" >&2; exit 1; }
make -C "$MININET_SRC" PYTHON="$STATE/venv/bin/python" mnexec
install -m 0755 "$MININET_SRC/mnexec" /usr/local/bin/mnexec

# --- build attacker image from Dockerfile ---
docker build -t cdci-wannacry/attacker:local \
    -f "$ROOT/infrastructure/Dockerfile" "$ROOT/infrastructure"

# --- Windows 7 victim image ---
if [[ ! -f "$STATE/win7.qcow2" ]]; then
    # Check for enough disk space (need ~12GB)
    AVAIL=$(df --output=avail "$STATE" | tail -1)
    if [[ $AVAIL -lt 12000000 ]]; then
        echo "ERROR: Not enough disk space in $STATE. Need at least 12GB free." >&2
        exit 1
    fi

    if [[ ! -f "$STATE/win7.ova" ]]; then
        echo "Downloading Windows 7 lab OVA..."
        gdown 1YPFRlCmJdtO08CDZLDZf0HyHAPElzNDj -O "$STATE/win7.ova"
    fi
    
    echo "Extracting OVA (this takes about a minute)..."
    rm -rf "$STATE/win7-extracted"
    mkdir -p "$STATE/win7-extracted"
    
    if file "$STATE/win7.ova" | grep -q "Zip archive"; then
        if ! 7z x -y -o"$STATE/win7-extracted" "$STATE/win7.ova"; then
            echo "ERROR: 7z extraction failed! The file may be corrupted or disk is full." >&2
            exit 1
        fi
    else
        if ! tar -xvf "$STATE/win7.ova" -C "$STATE/win7-extracted"; then
            echo "ERROR: tar failed!" >&2
            exit 1
        fi
    fi
    
    DISK=$(find "$STATE/win7-extracted" -type f \
             \( -name '*.vmdk' -o -name '*.vdi' -o -name '*.qcow2' \) | head -n1)
    [[ -n "$DISK" ]] || { echo "ERROR: No virtual disk found in OVA." >&2; exit 1; }
    
    FMT="${DISK##*.}"
    echo "Converting $DISK (format $FMT) -> qcow2..."
    if ! qemu-img convert -f "$FMT" -O qcow2 "$DISK" "$STATE/win7.qcow2"; then
        echo "ERROR: qemu-img conversion failed." >&2
        exit 1
    fi

    echo "Cleaning up temporary OVA files..."
    rm -f "$STATE/win7.ova"
    rm -rf "$STATE/win7-extracted"

    echo "Windows 7 image ready: $STATE/win7.qcow2"
fi

# --- version record ---
{
    docker version
    ovs-vsctl --version
    qemu-system-x86_64 --version
    "$STATE/venv/bin/pip" freeze
} > "$STATE/versions.txt"

echo ""
echo "Online stage complete."
echo "Next:"
echo "  Run the lab: sudo bash infrastructure/run.sh --hold"
echo "  (The DHCP server will automatically assign 10.0.0.3 to the Windows VM.)"