#!/usr/bin/env bash
set -Eeuo pipefail

[[ $EUID -eq 0 ]] || { echo "Run with sudo." >&2; exit 1; }

echo "Starting forced teardown..."

# 1. Kill QEMU (Windows VM)
if [[ -f /run/cdci-wannacry-qemu.pid ]]; then
    PID=$(cat /run/cdci-wannacry-qemu.pid)
    echo "Killing QEMU (PID $PID)..."
    kill -15 "$PID" 2>/dev/null || true
    sleep 2
    kill -9 "$PID" 2>/dev/null || true
    rm -f /run/cdci-wannacry-qemu.pid
else
    # Fallback: Kill any QEMU process using our specific image
    echo "No QEMU PID file found. Searching for processes..."
    pkill -9 -f "qemu-system-x86_64.*win7.qcow2" 2>/dev/null || true
fi

# 2. Kill dnsmasq (DHCP server)
if [[ -f /run/cdci-dnsmasq.pid ]]; then
    PID=$(cat /run/cdci-dnsmasq.pid)
    echo "Killing dnsmasq (PID $PID)..."
    kill -15 "$PID" 2>/dev/null || true
    rm -f /run/cdci-dnsmasq.pid
else
    pkill -9 -f "dnsmasq.*tap-dhcp" 2>/dev/null || true
fi

# 3. Remove Docker Attacker Container
if docker ps -a --format '{{.Names}}' | grep -q "^mn.attacker$"; then
    echo "Removing Docker container mn.attacker..."
    docker rm -f mn.attacker >/dev/null 2>&1 || true
fi

# 4. Remove OVS Bridge
if ovs-vsctl br-exists s1 2>/dev/null; then
    echo "Deleting OVS bridge s1..."
    ovs-vsctl --if-exists del-br s1
fi

# 5. Delete Tap Interfaces
for tap in tap-win7 tap-dhcp; do
    if ip link show "$tap" >/dev/null 2>&1; then
        echo "Deleting tap interface $tap..."
        ip link set "$tap" down 2>/dev/null || true
        ip link del "$tap" 2>/dev/null || true
    fi
done

# 6. Remove stale lock file
rm -f /run/cdci-wannacry.lock

echo "Teardown complete. The system is clean."