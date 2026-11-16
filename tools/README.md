# Tools

These scripts are the operational part of the lab. They were written for the
Windows workstation + Ubuntu VM pair, but the HTTP calls are portable.

## Before running anything

1. **Set your own credentials.** Every script in this public copy has had the
   original lab secrets replaced with placeholders such as
   `<ADMIN_PASSWORD>`, `<TENANT1_PASSWORD>`, `<TENANT2_PASSWORD>`, and
   `<SSH_PASSWORD>`. Replace them locally; never commit a filled-in copy.
2. **Set the host.** The scripts default to `127.0.0.1` when they run on the VM.
   From Windows, set the host to your Elasticsearch/Kibana address.
3. **Use the right identity for the task.** Install/enable tenant rules as the
   tenant user; install/enable the shared Default rule set as `elastic`.

## Key scripts

| Script | Purpose |
|--------|---------|
| `remote_exec.py` | Upload a local script to the VM and run it with sudo (SSH) |
| `ssh_run.py` | Run a command over SSH |
| `audit.sh` | Read-only host/stack audit |
| `es_discover.sh` | Elasticsearch/Kibana discovery |
| `es_roles.sh` | Roles/spaces/users inspection |
| `es_fleet.sh` | Fleet/detection/heap inspection |
| `fix_kibana_keys.sh` | Add the three Kibana encryption keys and restart Kibana |
| `provision_tenants.sh` | Create the original lab roles, users, and data views |
| `restore_roles_default_shared.sh` | Canonical role restore + shared Default read-only grant + Default alert read |
| `dr_install_package.sh` | Install the `security_detection_engine` package |
| `dr_sync_space.sh` | Install + upgrade prebuilt rules for one space |
| `enable_all_rules_http.py` | Enable all rules in a space, 100 ids per batch |
| `enable_verify_http.py` | Rule/enabled/execution-status/alert-count summary |
| `state_after_enable.py` | Write the post-enablement evidence file |
| `verify_isolation_final.sh` | 53-check data/space/alert isolation suite |
| `dr_verify_isolation.sh` | 15-check rule isolation + enablement suite |
| `verify_login.sh` | Login, redirect, space visibility, negative auth |
| `snapshot_final.sh` | Full final-state snapshot (read-only) |

## Typical order

```bash
# 1. Onboarding a tenant
bash provision_tenants.sh              # or follow docs/11-add-new-tenant.md
bash dr_install_package.sh             # package only
bash dr_sync_space.sh <space> <user:pass>
python enable_all_rules_http.py <space> --user <user> --password <pass>

# 2. Verification
bash verify_isolation_final.sh
bash dr_verify_isolation.sh
bash verify_login.sh

# 3. Evidence
python state_after_enable.py
```

## Safety

- `verify_isolation_final.sh` creates and then removes test data streams,
  indices, and dashboards. Run it only in a lab.
- `dr_disable_all.sh` disables every enabled rule in the configured spaces. Do
  not run it on the current all-enabled deployment unless you intend to turn
  detections off.
- `cleanup_final.sh` deletes lab test objects. Read it before running.
- The scripts contain `--max-time` limits. Long rule installs/enables should be
  run over direct HTTP (as `enable_all_rules_http.py` does), not through an SSH
  command timeout.
