#!/usr/bin/env python3
"""Run the native SSH acceptance against an owned loopback sshd and synthetic workspace.

The fixture never writes ~/.ssh/config or known_hosts. The production bootstrap may reuse
its content-addressed helper installation cache; no user projects or credentials are read.
"""
import argparse
import getpass
import hashlib
import json
import os
from pathlib import Path
import selectors
import signal
import socket
import subprocess
import tempfile
import threading
import time


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--helper', type=Path, required=True)
    parser.add_argument('--validator', type=Path, default=Path('target/debug/examples/ssh_remote_validation'))
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--bytes', type=int, default=1024 * 1024 * 1024)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    helper = args.helper.resolve()
    validator = args.validator.resolve()
    digest = hashlib.sha256(helper.read_bytes()).hexdigest()
    expected = helper.with_suffix('.sha256').read_text().split()[0]
    if digest != expected:
        raise RuntimeError('helper checksum mismatch')
    # Keep the entire authorized_keys ancestry private/owned; OpenSSH StrictModes
    # correctly rejects an authorization file underneath the shared /tmp directory.
    with tempfile.TemporaryDirectory(prefix='fixture-', dir=output) as temporary:
        fixture = Path(temporary)
        workspace = fixture / 'workspace'
        workspace.mkdir()
        for name in ['host', 'client']:
            subprocess.run(['ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-f', str(fixture/name)], check=True)
        authorized = fixture/'authorized_keys'
        authorized.write_bytes((fixture/'client.pub').read_bytes())
        authorized.chmod(0o600)
        with socket.socket() as reservation:
            reservation.bind(('127.0.0.1', 0))
            port = reservation.getsockname()[1]
        known_hosts = fixture/'known_hosts'
        known_hosts.write_text(f'[127.0.0.1]:{port} '+(fixture/'host.pub').read_text())
        config = fixture/'sshd_config'
        config.write_text(f'''Port {port}
ListenAddress 127.0.0.1
HostKey {fixture}/host
PidFile {fixture}/sshd.pid
AuthorizedKeysFile {authorized}
AllowUsers {getpass.getuser()}
PasswordAuthentication no
KbdInteractiveAuthentication no
UsePAM no
PermitTTY no
X11Forwarding no
AllowTcpForwarding no
AllowAgentForwarding no
LogLevel VERBOSE
''')
        server = subprocess.Popen(['/usr/sbin/sshd', '-D', '-e', '-f', str(config)],
                                  stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                  stderr=subprocess.PIPE, start_new_session=True)
        started = time.monotonic()
        log = output.joinpath('sshd.log').open('wb')
        draining = None
        try:
            with selectors.DefaultSelector() as ready:
                ready.register(server.stderr, selectors.EVENT_READ)
                while True:
                    events = ready.select(timeout=10)
                    if not events:
                        raise TimeoutError('owned sshd did not announce readiness')
                    line = server.stderr.readline()
                    log.write(line)
                    log.flush()
                    if not line:
                        raise RuntimeError('owned sshd exited before readiness')
                    if b'Server listening on' in line:
                        break
            def drain():
                for line in server.stderr:
                    log.write(line)
                    log.flush()
            draining = threading.Thread(target=drain, daemon=True)
            draining.start()
            environment = os.environ.copy()
            environment.update({
                'PURE_SSH_TEST_SERVER': '127.0.0.1', 'PURE_SSH_TEST_PORT': str(port),
                'PURE_SSH_TEST_USERNAME': getpass.getuser(),
                'PURE_SSH_TEST_WORKSPACE': str(workspace),
                'PURE_SSH_TEST_IDENTITY': str(fixture/'client'),
                'PURE_SSH_TEST_KNOWN_HOSTS': str(known_hosts),
                'PURE_REMOTE_HELPER_X86_64': str(helper),
                'PURE_SSH_TEST_TRANSFER_BYTES': str(args.bytes),
            })
            with output.joinpath('stdout.log').open('w') as stdout, output.joinpath('stderr.log').open('w') as stderr:
                result = subprocess.run([str(validator)], env=environment, stdout=stdout, stderr=stderr, timeout=600)
            report = {'validator': str(validator), 'helper': str(helper), 'helperSha256': digest,
                      'platform': os.uname().sysname+' '+os.uname().machine, 'port': port,
                      'bytes': args.bytes, 'seconds': time.monotonic()-started, 'exitCode': result.returncode}
            output.joinpath('report.json').write_text(json.dumps(report, indent=2))
            print(json.dumps(report, indent=2))
            print(output.joinpath('stdout.log').read_text()[-6000:])
            print(output.joinpath('stderr.log').read_text()[-3000:])
            if result.returncode:
                raise SystemExit(result.returncode)
        finally:
            if server.poll() is None:
                os.killpg(server.pid, signal.SIGTERM)
                try:
                    server.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    os.killpg(server.pid, signal.SIGKILL)
                    server.wait()
            if draining is not None:
                draining.join(timeout=5)
            server.stderr.close()
            log.close()


if __name__ == '__main__':
    main()
