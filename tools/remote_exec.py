#!/usr/bin/env python3
"""Upload a local file to the VM and run a command with sudo."""
import os
import sys

import paramiko

HOST = os.environ.get("VM_HOST", "192.168.1.212")
USER = os.environ.get("VM_USER", "user")
PASS = os.environ.get("VM_PASS", "<SSH_PASSWORD>")


def main():
    if len(sys.argv) < 2:
        print("usage: remote_exec.py <local_file_to_upload> [remote_path] [command...]")
        sys.exit(2)
    local = sys.argv[1]
    remote = sys.argv[2] if len(sys.argv) > 2 else "/tmp/" + os.path.basename(local)
    cmd = " ".join(sys.argv[3:]) if len(sys.argv) > 3 else "bash " + remote

    c = paramiko.SSHClient()
    c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    c.connect(HOST, 22, username=USER, password=PASS, timeout=15,
              look_for_keys=False, allow_agent=False)
    sftp = c.open_sftp()
    sftp.put(local, remote)
    sftp.close()
    full = "sudo -S -p '' bash -lc " + repr(cmd)
    stdin, stdout, stderr = c.exec_command(full, timeout=600)
    stdin.write(PASS + "\n")
    stdin.flush()
    out = stdout.read().decode("utf-8", "replace")
    err = stderr.read().decode("utf-8", "replace")
    rc = stdout.channel.recv_exit_status()
    sys.stdout.buffer.write(out.encode("utf-8", "replace"))
    sys.stdout.buffer.flush()
    if err.strip():
        sys.stderr.buffer.write(("\n--- STDERR ---\n" + err).encode("utf-8", "replace"))
        sys.stderr.buffer.flush()
    c.close()
    sys.exit(rc)


if __name__ == "__main__":
    main()
