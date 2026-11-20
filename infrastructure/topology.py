import argparse
import fcntl
import os
import subprocess
import sys
import time
from contextlib import ExitStack

DOCKER = ("docker", "--host", "unix:///var/run/docker.sock")
OVS = ("ovs-vsctl", "--timeout=5")
SWITCH = "s1"
ATTACKER_IMAGE = "cdci-wannacry/attacker:local"
ATTACKER_IP = "10.0.0.2"
DEFAULT_VICTIM_IP = "10.0.0.3"
TAP_NAME = "tap-win7"
ATTACKER_LINK = "attacker-eth0"
ATTACKER_PORT = "s1-attacker"
QEMU_PIDFILE = "/run/cdci-wannacry-qemu.pid"
LOCK_FILE = "/run/cdci-wannacry.lock"


class LabError(RuntimeError):
    pass


def run(*args, check=True):
    return subprocess.run(args, check=check, capture_output=True, text=True, timeout=30)


def container(name):
    return f"mn.{name}"


def preflight(windows_image):
    if os.geteuid() != 0:
        raise LabError("Run as root inside the dedicated offline VM.")
    if run("systemd-detect-virt", "--quiet", "--vm", check=False).returncode != 0:
        raise LabError("No VM detected; do not run on the shared host.")
    overrides = {"DOCKER_HOST", "DOCKER_CONTEXT", "DOCKER_TLS_VERIFY", "DOCKER_CERT_PATH"}
    if overrides.intersection(os.environ):
        raise LabError("Unset Docker host, context, and TLS overrides.")
    if run("docker", "context", "show").stdout.strip() != "default":
        raise LabError("Use the VM's local Docker daemon and default context.")
    if run(*DOCKER, "info", "--format", "{{.CgroupDriver}}").stdout.strip() != "systemd":
        raise LabError("Docker must use the systemd cgroup driver.")
    if not os.path.isfile(windows_image):
        raise LabError(f"Windows image not found: {windows_image}")
    return run(*DOCKER, "image", "inspect", "--format", "{{.Id}}", ATTACKER_IMAGE).stdout.strip()


def require_clean_state(phase):
    containers = run(*DOCKER, "ps", "-a", "--format", "{{.Names}}").stdout.splitlines()
    bridges = run(*OVS, "list-br").stdout.splitlines()
    links = run("ip", "link", "show").stdout
    problems = []
    if container("attacker") in containers:
        problems.append(f"container {container('attacker')}")
    if SWITCH in bridges:
        problems.append(f"OVS bridge {SWITCH}")
    if TAP_NAME in links:
        problems.append(f"tap {TAP_NAME}")
    if os.path.exists(QEMU_PIDFILE):
        problems.append(f"qemu pidfile {QEMU_PIDFILE}")
    if problems:
        raise LabError(f"{phase}: stale lab objects ({', '.join(problems)}).")


def setup_tap():
    run("ip", "tuntap", "add", TAP_NAME, "mode", "tap")
    run("ip", "link", "set", TAP_NAME, "up")


def attach_tap():
    run(*OVS, "add-port", SWITCH, TAP_NAME, "--", "set", "Interface", TAP_NAME, "type=internal")


def teardown_tap():
    run("ip", "link", "set", TAP_NAME, "down", check=False)
    run("ip", "tuntap", "del", TAP_NAME, "mode", "tap", check=False)


def launch_windows(windows_image):
    cmd = [
        "qemu-system-x86_64", "-m", "1024", "-smp", "2",
        "-drive", f"file={windows_image},format=qcow2,if=ide",
        "-netdev", f"tap,id=net0,ifname={TAP_NAME},script=no,downscript=no",
        "-device", "e1000,netdev=net0",
        "-nographic", "-daemonize",
        "-pidfile", QEMU_PIDFILE,
    ]
    
    # Check for KVM support and add acceleration flags if available
    if os.path.exists("/dev/kvm"):
        cmd.extend(["-enable-kvm", "-cpu", "host"])
        print("KVM acceleration enabled.")
    else:
        cmd.extend(["-cpu", "qemu64"])
        print("WARNING: /dev/kvm not found. Running with TCG software emulation.")
        
    run(*cmd)


def stop_windows():
    if not os.path.exists(QEMU_PIDFILE):
        return
    try:
        with open(QEMU_PIDFILE) as f:
            pid = int(f.read().strip())
        os.kill(pid, 15)
        for _ in range(20):
            try:
                os.kill(pid, 0)
            except OSError:
                break
            time.sleep(0.5)
    except (OSError, ValueError):
        pass


def wait_for_smb(victim_ip, timeout=180):
    deadline = time.time() + timeout
    while time.time() < deadline:
        result = subprocess.run(
            [*DOCKER, "exec", container("attacker"),
             "nmap", "-p", "445", "--open", "-Pn", victim_ip],
            capture_output=True, text=True,
        )
        if "445/tcp open" in result.stdout:
            return
        time.sleep(2)
    raise LabError(f"Port 445 on {victim_ip} did not open within {timeout}s.")


def run_lab(windows_image, victim_ip, hold):
    from mininet.net import Containernet
    from mininet.node import OVSSwitch

    require_clean_state("Preflight")
    with ExitStack() as cleanup:
        net = Containernet(controller=None, switch=OVSSwitch, build=False)
        cleanup.callback(stop_windows)
        cleanup.callback(teardown_tap)
        cleanup.callback(net.stop)
        cleanup.callback(require_clean_state, "Teardown")

        switch = net.addSwitch(SWITCH, failMode="standalone")
        attacker = net.addDocker(
            "attacker", ip=f"{ATTACKER_IP}/24", dimage=ATTACKER_IMAGE,
            network_mode="none", publish_all_ports=False, dcmd="/bin/bash",
        )
        net.addLink(attacker, switch, intfName1=ATTACKER_LINK, intfName2=ATTACKER_PORT)
        net.start()

        setup_tap()
        attach_tap()
        launch_windows(windows_image)

        print(f"Attacker: {ATTACKER_IP}/24  (container {container('attacker')})")
        print(f"Victim:   {victim_ip}/24  (Windows 7 under QEMU)")
        print("Waiting for port 445 on victim...")
        wait_for_smb(victim_ip)

        print("")
        print("Demo ready.")
        print(f"  Enter attacker:  sudo docker exec -it {container('attacker')} bash")
        print(f"  Then run:        cd /opt/AutoBlue-MS17-010")
        print(f"                   python3 zzz_exploit.py {victim_ip}")
        print(f"  This spawns a SYSTEM shell directly (no Metasploit module).")
        if hold:
            input("Press Enter to tear down: ")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--offline", action="store_true", required=True,
                        help="confirm this is the authorized offline VM")
    parser.add_argument("--windows-image", required=True,
                        help="path to the Windows 7 SP1 qcow2 image")
    parser.add_argument("--victim-ip", default=DEFAULT_VICTIM_IP,
                        help=f"IP configured inside the Windows VM (default {DEFAULT_VICTIM_IP})")
    parser.add_argument("--hold", action="store_true",
                        help="keep the lab up until Enter is pressed")
    args = parser.parse_args()

    try:
        image_id = preflight(args.windows_image)
        print(f"Attacker image: {ATTACKER_IMAGE} ({image_id})", flush=True)
        with open(LOCK_FILE, "a", encoding="utf-8") as lock:
            try:
                fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError as error:
                raise LabError("Another lab run is already active.") from error
            run_lab(args.windows_image, args.victim_ip, hold=args.hold)
    except subprocess.CalledProcessError as error:
        print(f"ERROR: {error}\n{(error.stderr or '').strip()}", file=sys.stderr)
        return 1
    except (LabError, OSError, ImportError, subprocess.TimeoutExpired) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("\nInterrupted; verify teardown before reconnecting the VM.", file=sys.stderr)
        return 130
    return 0


if __name__ == "__main__":
    sys.exit(main())