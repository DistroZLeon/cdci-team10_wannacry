import subprocess
from unittest.mock import patch
import unittest

from infrastructure import topology

def result(code=0, stdout="", stderr=""):
    return subprocess.CompletedProcess(args=[], returncode=code, stdout=stdout, stderr=stderr)

class LaunchWindowsTests(unittest.TestCase):
    def test_no_kvm_uses_qemu64_only(self):
        with (
            patch("os.path.exists", return_value=False),
            patch.object(topology, "run") as run,
        ):
            topology.launch_windows("/fake/image.qcow2")
        cmd = run.call_args.args
        cpu_flags = [cmd[i + 1] for i, a in enumerate(cmd) if a == "-cpu"]
        self.assertEqual(cpu_flags, ["qemu64"])
        self.assertNotIn("-enable-kvm", cmd)

    def test_kvm_uses_host_cpu_only(self):
        with (
            patch("os.path.exists", return_value=True),
            patch.object(topology, "run") as run,
        ):
            topology.launch_windows("/fake/image.qcow2")
        cmd = run.call_args.args
        cpu_flags = [cmd[i + 1] for i, a in enumerate(cmd) if a == "-cpu"]
        self.assertEqual(cpu_flags, ["host"])
        self.assertIn("-enable-kvm", cmd)


class WaitForSmbTests(unittest.TestCase):
    def test_returns_when_port_445_opens(self):
        with patch.object(
            topology.subprocess, "run",
            return_value=result(code=0)
        ):
            topology.wait_for_smb("10.0.0.3", timeout=1)

    def test_raises_on_timeout(self):
        with patch.object(
            topology.subprocess, "run",
            return_value=result(code=1)
        ):
            with self.assertRaises(topology.LabError):
                topology.wait_for_smb("10.0.0.3", timeout=1)