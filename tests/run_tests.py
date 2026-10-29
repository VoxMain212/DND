"""Run Godot rules and two-process ENet tests. Python 3 standard library only."""
import argparse
import json
from pathlib import Path
import socket
import subprocess
import tempfile
import time
from mock_ai_server import MockAI

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", default="godot")
    args = parser.parse_args()
    command = [args.godot, "--headless", "--path", str(ROOT)]
    for script in ["test_rules.gd", "test_combat.gd", "test_table.gd"]:
        result = subprocess.run(command + ["--script", f"res://tests/{script}"],
                                capture_output=True, text=True, timeout=25)
        print(result.stdout, end="")
        if result.returncode or "SCRIPT ERROR" in result.stderr or "ERROR:" in result.stderr:
            raise SystemExit(result.stderr or f"{script} failed")
    with MockAI() as mock, tempfile.TemporaryDirectory(prefix="dndfun-generation-") as directory:
        result = subprocess.run(command + ["--script", "res://tests/test_generation.gd", "--",
                                f"--mock-url={mock.url}", f"--cache-dir={directory}/unit"],
                                capture_output=True, text=True, timeout=35)
        print(result.stdout, end="")
        if result.returncode or "SCRIPT ERROR" in result.stderr or "ERROR:" in result.stderr:
            raise SystemExit(result.stderr or "Generation test failed")
        mock.check_contract()
        result = subprocess.run(command + ["--script", "res://tests/test_director_saves.gd", "--",
                                f"--mock-url={mock.url}", f"--cache-dir={directory}/director"],
                                capture_output=True, text=True, timeout=30)
        print(result.stdout, end="")
        if result.returncode or "SCRIPT ERROR" in result.stderr or "ERROR:" in result.stderr:
            raise SystemExit(result.stderr or "Director/save tests failed")
        run_portrait_network(command, Path(directory))
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]
    with tempfile.TemporaryDirectory(prefix="dndfun-tests-") as directory:
        host_log = Path(directory) / "host.log"
        peers = []
        try:
            with host_log.open("w") as output:
                host = subprocess.Popen(command + ["--script", "res://tests/network_peer.gd",
                    "--", "--role=host", f"--port={port}"], stdout=output, stderr=output)
                peers.append(host)
                deadline = time.monotonic() + 8
                while "HOST_READY" not in host_log.read_text():
                    if host.poll() is not None or time.monotonic() > deadline:
                        raise RuntimeError("Host failed to start:\n" + host_log.read_text())
                    time.sleep(0.05)
                client = subprocess.Popen(command + ["--script", "res://tests/network_peer.gd",
                    "--", "--role=client", f"--port={port}"],
                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
                peers.append(client)
                client_output, _ = client.communicate(timeout=18)
                host.wait(timeout=5)
            host_output = host_log.read_text()
            print(host_output, end="")
            print(client_output, end="")
            if (host.returncode or client.returncode or "NETWORK_HOST_PASS" not in host_output
                    or "NETWORK_CLIENT_PASS" not in client_output
                    or "ERROR" in host_output or "ERROR" in client_output):
                raise RuntimeError("Network integration failed")
            host_roll = next(line.removeprefix("HOST_ROLL:") for line in host_output.splitlines() if line.startswith("HOST_ROLL:"))
            client_roll = next(line.removeprefix("CLIENT_ROLL:") for line in client_output.splitlines() if line.startswith("CLIENT_ROLL:"))
            if json.loads(host_roll) != json.loads(client_roll):
                raise RuntimeError("Host and client received different dice results")
        finally:
            for peer in peers:
                if peer.poll() is None:
                    peer.kill()
                    peer.wait()
    print("ALL TESTS PASSED")


def run_portrait_network(command, directory):
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]
    peers = []
    host_log = directory / "portrait-host.log"
    try:
        with host_log.open("w") as output:
            host = subprocess.Popen(command + ["--script", "res://tests/generation_peer.gd", "--",
                "--role=host", f"--port={port}", f"--cache-dir={directory}/host"], stdout=output, stderr=output)
            peers.append(host)
            deadline = time.monotonic() + 8
            while "HOST_READY" not in host_log.read_text():
                if host.poll() is not None or time.monotonic() > deadline:
                    raise RuntimeError(host_log.read_text())
                time.sleep(0.05)
            client = subprocess.Popen(command + ["--script", "res://tests/generation_peer.gd", "--",
                "--role=client", f"--port={port}", f"--cache-dir={directory}/client"],
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            peers.append(client)
            client_output, _ = client.communicate(timeout=20)
            host.wait(timeout=5)
        host_output = host_log.read_text()
        print(host_output, end="")
        print(client_output, end="")
        if (host.returncode or client.returncode or "GEN_NETWORK_HOST_PASS" not in host_output
                or "GEN_NETWORK_CLIENT_PASS" not in client_output or "ERROR" in host_output or "ERROR" in client_output):
            raise RuntimeError("Portrait network test failed")
        host_key = next(line.split(":", 1)[1] for line in host_output.splitlines() if line.startswith("GEN_HOST_TOKEN:"))
        client_key = next(line.split(":", 1)[1] for line in client_output.splitlines() if line.startswith("GEN_CLIENT_TOKEN:"))
        if host_key != client_key:
            raise RuntimeError("Portrait hashes differ across the network")
    finally:
        for peer in peers:
            if peer.poll() is None:
                peer.kill()
                peer.wait()


if __name__ == "__main__":
    main()
