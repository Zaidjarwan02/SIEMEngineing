# 07 — Hardening Checklist

These are the security gaps found on the test VM. **None of the remediation steps below
have been applied yet** — they are recommendations for turning this test setup into
something safe to expose beyond a lab. Each item lists the evidence and a concrete fix.

Severity: **Critical** / **High** / **Medium** / **Low** / **Info**

---

## 1. Elasticsearch HTTP TLS is disabled — **High**

**Evidence** (`/etc/elasticsearch/elasticsearch.yml`):

```yaml
xpack.security.http.ssl:
  enabled: false
  keystore.path: certs/http.p12
```

`http.host: 0.0.0.0`, `network.host: 192.168.1.212`. Elasticsearch credentials (including
the `elastic` superuser) and all tenant data travel in cleartext over the LAN.

**Fix:**

1. Confirm `certs/http.p12` exists and is valid. If the keystore is password-protected,
   add the password as a secure setting first:

   ```bash
   sudo /usr/share/elasticsearch/bin/elasticsearch-keystore add \
     xpack.security.http.ssl.keystore.secure_password
   ```

2. Set:

   ```yaml
   xpack.security.http.ssl:
     enabled: true
     keystore.path: certs/http.p12
   ```

3. Restart Elasticsearch.
4. Update Kibana to use HTTPS:

   ```yaml
   elasticsearch.hosts: ["https://192.168.1.212:9200"]
   elasticsearch.ssl.certificateAuthorities: ["/etc/kibana/certs/ca.crt"]
   elasticsearch.ssl.verificationMode: certificate
   ```

5. Update any Fleet/agent output URLs to `https://`.
6. Re-run the isolation and login verification.

> Transport TLS (9300) is already enabled with certificate verification, so only the HTTP
> layer needs this change.

---

## 2. Host firewall (UFW) is inactive — **High**

**Evidence:** `ufw status verbose` → `Status: inactive`.

Every service (SSH, Kibana, Elasticsearch) is reachable from the entire LAN.

**Fix (adjust the admin subnet as needed):**

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow from 192.168.1.0/24 to any port 22 proto tcp
sudo ufw allow from 192.168.1.0/24 to any port 5601 proto tcp
sudo ufw allow from 192.168.1.0/24 to any port 9200 proto tcp
sudo ufw enable
sudo ufw status verbose
```

Do **not** expose 9200 to tenants directly; only Kibana (5601) should be user-facing.

---

## 3. Elasticsearch and Kibana bind to all interfaces — **Medium**

**Evidence:**

- `http.host: 0.0.0.0`
- `server.host: "0.0.0.0"`

**Fix:** bind to the specific interface or to localhost behind a reverse proxy:

```yaml
# elasticsearch.yml (if Kibana is on the same host)
http.host: 127.0.0.1
```

```yaml
# kibana.yml
server.host: "192.168.1.212"
```

Or keep Kibana on `127.0.0.1` and put nginx/Caddy with TLS in front of it.

---

## 4. `kibana_system` password is stored in plaintext — **Medium**

**Evidence:** `/etc/kibana/kibana.yml` contains `elasticsearch.password: <plaintext>`.

**Fix:** move it to the Kibana keystore and remove it from the file:

```bash
sudo /usr/share/kibana/bin/kibana-keystore add elasticsearch.password
# enter the password when prompted
sudo sed -i '/^elasticsearch\.password:/d' /etc/kibana/kibana.yml
sudo systemctl restart kibana
```

Then rotate the `kibana_system` password so the old value is no longer valid.

---

## 5. No snapshot repository / backups — **High**

**Evidence:** `GET _snapshot` → `{ }`. There is no backup of tenant data, roles, or spaces.

**Fix:** register a filesystem repository and a snapshot lifecycle policy:

```bash
sudo mkdir -p /var/backups/elasticsearch
sudo chown elasticsearch:elasticsearch /var/backups/elasticsearch

curl -s -u 'elastic:<password>' -H 'Content-Type: application/json' \
  -X PUT 'http://127.0.0.1:9200/_snapshot/fs_backup' \
  -d '{"type":"fs","settings":{"location":"/var/backups/elasticsearch","compress":true}}'

curl -s -u 'elastic:<password>' -H 'Content-Type: application/json' \
  -X PUT 'http://127.0.0.1:9200/_slm/policy/daily-snapshots' \
  -d '{
    "schedule":"0 30 2 * * ?",
    "name":"<daily-snap-{now/d}>",
    "repository":"fs_backup",
    "config":{"indices":"*","include_global_state":true},
    "retention":{"expire_after":"14d","min_count":5,"max_count":50}
  }'
```

Store a copy off the VM. Back up `/etc/elasticsearch`, `/etc/kibana`, and the Kibana
encryption keys as well.

---

## 6. No swap and high memory pressure — **Medium**

**Evidence:** `Swap: 0B`; RAM ~92% used; ES heap `-Xms4664m -Xmx4664m`; Kibana also uses
memory. No swap means the OOM killer can terminate Elasticsearch/Kibana under load.

**Fix (choose one or both):**

- Increase VM RAM (e.g., 12–16 GB) and keep ES heap at ~50% of RAM.
- Add a swap file (2–4 GB) for the OS, but keep ES heap locked in RAM:

  ```bash
  sudo fallocate -l 4G /swapfile
  sudo chmod 600 /swapfile
  sudo mkswap /swapfile
  sudo swapon /swapfile
  echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
  ```

- Keep `bootstrap.memory_lock: true` and the matching `LimitMEMLOCK=infinity` in the
  systemd unit if you rely on locked heap.

---

## 7. Elasticsearch audit logging is not configured — **Medium**

**Evidence:** no `xpack.security.audit.*` settings in `elasticsearch.yml`.

**Fix:**

```yaml
xpack.security.audit.enabled: true
xpack.security.audit.outputs: [ logfile ]
```

Restart Elasticsearch. Ship the audit log to a separate protected location. Keep an eye
on disk usage.

---

## 8. Fleet Server port 8220 is closed and the only agent is offline — **Medium**

**Evidence:** port 8220 not listening; Fleet agent `GC-LD-002` on policy `greencircle` is
`offline`.

**Fix:**

- Confirm the Fleet Server service is running and listening on 8220.
- Check the agent on `GC-LD-002` (`systemctl status elastic-agent`, agent logs).
- Confirm the enrollment token and Fleet Server host URL.
- Enroll a TKT agent for the `tkt` policy if that tenant is expected to send data.

---

## 9. SSH password authentication is enabled — **Medium**

**Evidence:** SSH accepts password login for `user` (a sudo member).

**Fix:** deploy SSH keys and disable password auth:

```bash
# in /etc/ssh/sshd_config.d/99-hardening.conf
PasswordAuthentication no
PermitRootLogin no
```

Test key login in a second session before restarting `sshd`.

---

## 10. Automation uses the `elastic` superuser — **Medium**

The provisioning and verification scripts authenticate as `elastic`. For day-to-day
operations, create scoped API keys or a dedicated automation user with only the privileges
it needs, and store the key in a secret manager.

```bash
curl -s -u 'elastic:<password>' -H 'Content-Type: application/json' \
  -X POST 'http://127.0.0.1:9200/_security/api_key' \
  -d '{"name":"mssp-automation","role_descriptors":{"provisioner":{"cluster":["manage_security"],"indices":[]}}}'
```

Rotate the `elastic` password after moving automation off it.

---

## 11. Stale `cluster.initial_master_nodes` — **Low**

**Evidence:** `cluster.initial_master_nodes: ["ubuntu"]` while the node is named `node-1`.

This setting is only for bootstrapping a brand-new cluster. On a formed single-node
cluster it is unnecessary and can confuse future joins.

**Fix:** remove the line (single-node) or set it to the real node names and keep it
consistent across all master-eligible nodes. Restart one node at a time.

---

## 12. Basic license — **Info**

Basic is active and sufficient for the current isolation model. Advanced features
(e.g., some detection rule actions, advanced DLS/FLS workflows) require a higher tier.
Document the license boundary so nobody designs around a feature that is unavailable.

---

## 13. Kibana encryption keys exist but are not backed up — **Info**

The three keys were added to `/etc/kibana/kibana.yml` to fix alerting/detections. If they
are lost, encrypted saved objects (alert rules, connectors, reports) become unreadable.

**Fix:** back up `/etc/kibana/kibana.yml` (or just the three key values) to a secure
secret store. Do not commit them to git.

---

## 14. Default space is shared read-only — **Info**

The `default` space holds 40 pre-existing dashboards and the shared 2,062-rule detection
set. Tenant users have **read-only** access (`space_read`), so they can view shared content
but cannot create, edit or delete it (verified `403`). Tenant data is still isolated at the
Elasticsearch layer, so shared dashboards cannot surface another tenant's documents.

**Consider:** if any Default content must stay confidential, move it to an admin-only space.
Anything left in Default is visible to both tenants.

---

## Verification after hardening

After any change, re-run:

```powershell
$env:PYTHONIOENCODING="utf-8"
python tools\remote_exec.py tools\verify_isolation_final.sh /tmp/verify_isolation_final.sh "bash /tmp/verify_isolation_final.sh"
python tools\remote_exec.py tools\verify_login.sh /tmp/verify_login.sh "bash /tmp/verify_login.sh"
```

Also re-check:

```bash
curl -s http://127.0.0.1:5601/api/status | python3 -m json.tool | head
curl -s -u 'elastic:<password>' 'http://127.0.0.1:9200/_cluster/health?pretty'
sudo ufw status verbose
ss -tulpn | grep -E ':(5601|9200|9300|8220)\b'
```
