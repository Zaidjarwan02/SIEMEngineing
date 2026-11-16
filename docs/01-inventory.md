# 01 — Environment Inventory

Captured 2026-11-11 from the running test VM. Raw output: [`evidence/01-system-audit.txt`](evidence/01-system-audit.txt).

## Host

| Item | Value |
|------|-------|
| Hostname | `ubuntu` |
| OS | Ubuntu 26.04.1 LTS (codename `resolute`) |
| Kernel | `7.0.0-43-generic` |
| Architecture | x86_64 |
| Virtualization | Oracle VirtualBox (KVM hypervisor type), bridged NIC |
| Machine ID | `01e540661ee5452499a3022888fefb2d` |
| Product UUID | `d0de995e-7931-8e49-a6db-955322ae3ffd` |

## Compute / memory / disk

| Resource | Value |
|----------|-------|
| vCPU | 4 (Intel Core i7-8665U, 1 thread/core, 1 socket) |
| RAM | 9.2 GiB total; ~7.3 GiB used; **0 B swap** |
| Root disk | `/dev/sda2`, ext4, 89 G total, ~75 G available (11% used) |
| Elasticsearch heap | `-Xms4664m -Xmx4664m` (about 50% of RAM) |

> Memory is tight. With no swap, the Elasticsearch heap plus Kibana plus the OS leaves
> little headroom. See [hardening](07-hardening-checklist.md) (item 6).

## Network

| Item | Value |
|------|-------|
| Interface | `enp0s3` |
| IPv4 | `192.168.1.212/24` (DHCP reservation) |
| MAC | `08:00:27:17:56:d7` |
| Gateway / DNS | `192.168.1.1` |
| Domain | `lan` |

## Open ports (host)

| Port | Process | Notes |
|------|---------|-------|
| 22/tcp | `sshd` | SSH, password authentication enabled |
| 5601/tcp | Kibana | bound `0.0.0.0` |
| 9200/tcp | Elasticsearch HTTP | bound `*` (all interfaces), **HTTP TLS disabled** |
| 9300/tcp | Elasticsearch transport | TLS + mutual auth enabled |
| 631/tcp | CUPS | localhost only |
| 53/udp/tcp | systemd-resolved | localhost/stub |
| 5353/udp | avahi | mDNS |
| 323/udp | chronyd | NTP |

Port `8220` (Fleet Server) was **not** listening during the audit.

## Elastic stack

| Component | Version | Package |
|-----------|---------|---------|
| Elasticsearch | 8.19.24 | deb |
| Kibana | 8.19.24 | deb |
| License | Basic | active, no expiry |
| Cluster name | `grcico.SIEM` | |
| Cluster UUID | `qLpz5Y1MSxqOucWlV9vndg` | |
| Node | `node-1` | single node |

No Docker, Logstash, Beats, or additional Elastic Agents are installed on this host
(a Fleet Server / agent is configured but the agent `GC-LD-002` is offline).

> A leftover `metricbeat-8.19.24-amd64.deb` package file sits in `/etc/elasticsearch/`.
> Metricbeat itself is not installed; the file can be removed.

## Services

Running services of interest (full list in the audit evidence):

| Service | State | Purpose |
|---------|-------|---------|
| `elasticsearch.service` | running, enabled | Elasticsearch |
| `kibana.service` | running, enabled | Kibana |
| `ssh.service` / `ssh.socket` | running, enabled | Remote shell |
| `chrony.service` | running | NTP |
| `unattended-upgrades.service` | running | Automatic security updates |
| `systemd-oomd.service` | running | Userspace OOM killer |
| `cron.service` | running | Scheduled jobs |
| `gdm.service` | running | GNOME display manager (console login) |

No failed systemd units were reported.

## Packages and scheduled work

| Item | Value |
|------|-------|
| `elasticsearch` | 8.19.24 |
| `kibana` | 8.19.24 |
| Docker / containerd | not installed |
| Logstash / Beats | not installed |
| Java | bundled with Elasticsearch (`/usr/share/elasticsearch/jdk`) |
| Snap packages | standard Ubuntu desktop snaps only |
| User crontab | none captured |
| System timers | standard systemd timers only (no Elastic jobs) |

## Local accounts

| Account | UID | Notes |
|---------|-----|-------|
| `root` | 0 | |
| `user` | 1000 | Human login, member of `sudo`, home `/home/user` |
| `elasticsearch` | system | Service account, `/bin/false` |
| `kibana` | system | Service account, `/bin/false` |

SSH password authentication is enabled for `user`. The `elastic` superuser is an
Elasticsearch-native account (not a Linux account).

## Key configuration files

| File | Purpose |
|------|---------|
| `/etc/elasticsearch/elasticsearch.yml` | ES node, network, security, TLS |
| `/etc/elasticsearch/jvm.options` + `jvm.options.d/` | ES heap |
| `/etc/kibana/kibana.yml` | Kibana host, ES connection, encryption keys |
| `/etc/kibana/node.options` | Kibana Node heap (if set) |
| `/var/log/elasticsearch/` | ES logs |
| `/var/log/kibana/` | Kibana logs |
