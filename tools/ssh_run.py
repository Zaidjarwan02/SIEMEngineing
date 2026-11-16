#!/usr/bin/env python3
"""Run a command on the Elastic VM over SSH (password auth).

Usage:
    python ssh_run.py "command"
    python ssh_run.py --sudo "command"
    echo "script" | python ssh_run.py --sudo --stdin

Config via env vars (defaults shown):
    VM_HOST=192.168.1.212
    VM_USER=zaid
    VM_PASS=<SSH_PASSWORD>
"""
import argparse
import os
import sys

import paramiko

HOST = os.environ.get("VM_HOST", "192.168.1.212")
USER = os.environ.get("VM_USER", "zaid")
PASS = os.environ.get("VM_PASS", "<SSH_PASSWORD>")


def connect(host=HOST, user=USER, password=PASS, timeout=15):
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect(
        host,
        port=22,
        username=user,
        password=password,
        timeout=timeout,
        banner_timeout=timeout,
        auth_timeout=timeout,
        look_for_keys=False,
        allow_agent=False,
    )
    return client


def run(command, sudo=False, stdin_data=None, timeout=300, host=HOST, user=USER, password=PASS):
    client = connect(host, user, password)
    try:
        if sudo:
            command = "sudo -S -p '' bash -lc " + _quote(command)
        else:
            command = "bash -lc " + _quote(command)
        stdin, stdout, stderr = client.exec_command(command, timeout=timeout, get_pty=False)
        if sudo:
            stdin.write(password + "\n")
            stdin.flush()
        if stdin_data:
            stdin.write(stdin_data)
            stdin.flush()
        out = stdout.read().decode("utf-8", "replace")
        err = stderr.read().decode("utf-8", "replace")
        rc = stdout.channel.recv_exit_status()
        return rc, out, err
    finally:
        client.close()


def _quote(s):
    return "'" + s.replace("'", "'\\''") + "'"


def main():
    p = argparse.ArgumentParser()
    p.add_argument("command", nargs="?", help="command to run")
    p.add_argument("--sudo", action="store_true")
    p.add_argument("--stdin", action="store_true", help="read stdin and feed it to the command")
    p.add_argument("--timeout", type=int, default=300)
    p.add_argument("--host", default=HOST)
    p.add_argument("--user", default=USER)
    p.add_argument("--password", default=PASS)
    args = p.parse_args()

    cmd = args.command
    if args.stdin and not cmd:
        cmd = sys.stdin.read()
    if not cmd:
        p.error("no command given")

    stdin_data = sys.stdin.read() if args.stdin and args.command else None
    rc, out, err = run(cmd, sudo=args.sudo, stdin_data=stdin_data,
                       timeout=args.timeout, host=args.host, user=args.user, password=args.password)
    sys.stdout.write(out)
    if err:
        sys.stderr.write(err)
    sys.exit(rc)


if __name__ == "__main__":
    main()
