#!/usr/bin/env bash
set -Eeuo pipefail

[[ $EUID -eq 0 ]] || { echo "Run with sudo." >&2; exit 1; }

echo "Starting forced teardown..."

# 1. Kill QEMU
if [[ -f /run/cdci-wannacry-qemu.pid ]]; then
    PID=$(cat /run/cdci-wannacry-qemu.pid)
    echo "Killing QEMU (PID $PID)..."
    kill -15 "$PID" 2>/dev/null || true
    sleep 2
    kill -9 "$PID" 2>/dev/null || true
    rm -f /run/cdci-wannacry-qemu.pid
else
    pkill -9 -f "qemu-system-x86_64.*win7.qcow2" 2>/dev/null || true
fi

# 2. Remove Docker Attacker Container
if docker ps -a --format '{{.Names}}' | grep -q "^mn.attacker$"; then
    echo "Removing Docker container mn.attacker..."
    docker rm -f mn.attacker >/dev/null 2>&1 || true
fi

# 3. Remove OVS Bridge
if ovs-vsctl br-exists s1 2>/dev/null; then
    echo "Deleting OVS bridge s1..."
    ovs-vsctl --if-exists del-br s1
fi

# 4. Delete Tap Interfaces
if ip link show "tap-win7" >/dev/null 2>&1; then
    echo "Deleting tap interface tap-win7..."
    ip link set "tap-win7" down 2>/dev/null || true
    ip link del "tap-win7" 2>/dev/null || true
fi

# 5. Delete stale veth pairs
for intf in attacker-eth0 s1-attacker; do
    if ip link show "$intf" >/dev/null 2>&1; then
        echo "Deleting veth interface $intf..."
        ip link del "$intf" 2>/dev/null || true
    fi
done

# 6. Remove stale lock file
rm -f /run/cdci-wannacry.lock

echo "Teardown complete. The system is clean."