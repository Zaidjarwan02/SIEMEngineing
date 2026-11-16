#!/usr/bin/env bash
# Full machine audit for the Elastic MSSP test VM.
# Read-only. Safe to run repeatedly.
set +e
export LC_ALL=C
sec() { printf '\n\n========== %s ==========\n' "$1"; }

sec "IDENTITY"
hostnamectl 2>/dev/null
echo "--- lsb_release ---"; lsb_release -a 2>/dev/null
echo "--- uname ---"; uname -a
echo "--- uptime ---"; uptime
echo "--- date ---"; date -Is

sec "HARDWARE / RESOURCES"
echo "--- cpu ---"; lscpu | grep -Ei 'model name|^cpu\(s\)|thread|core|socket|virtualization|hypervisor'
echo "--- memory ---"; free -h
echo "--- loadavg ---"; cat /proc/loadavg

sec "DISK"
df -hT -x tmpfs -x devtmpfs
echo "--- lsblk ---"; lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT,TYPE

sec "NETWORK"
echo "--- addresses ---"; ip -brief address
echo "--- routes ---"; ip route
echo "--- dns ---"; (resolvectl status 2>/dev/null || cat /etc/resolv.conf)
echo "--- listening tcp/udp ---"; ss -tulpn

sec "USERS / GROUPS (human accounts)"
awk -F: '$3>=1000 && $3<65534 {print $1" uid="$3" gid="$4" home="$6" shell="$7}' /etc/passwd
echo "--- sudo group ---"; getent group sudo
echo "--- last logins ---"; last -n 15 2>/dev/null

sec "INSTALLED ELASTIC / JAVA / DOCKER PACKAGES"
dpkg -l 2>/dev/null | awk '/^ii/ && $2 ~ /(elastic|kibana|logstash|beats|filebeat|metricbeat|auditbeat|packetbeat|heartbeat|agent|endpoint|docker|containerd|java|jdk|jre|nginx|redis|postgres)/ {print $2"  "$3}'
echo "--- snap ---"; snap list 2>/dev/null

sec "SERVICES"
systemctl list-units --type=service --state=running --no-pager --no-legend 2>/dev/null
echo "--- unit files of interest ---"
systemctl list-unit-files --no-pager --no-legend 2>/dev/null | grep -Ei 'elastic|kibana|logstash|beats|filebeat|metricbeat|auditbeat|packetbeat|heartbeat|fleet|agent|docker|containerd|nginx|redis|postgres|ssh'

sec "FAILED UNITS"
systemctl --failed --no-pager --no-legend 2>/dev/null

sec "ELASTIC STACK DIRECTORIES"
for d in /etc/elasticsearch /usr/share/elasticsearch /var/lib/elasticsearch /var/log/elasticsearch \
         /etc/kibana /usr/share/kibana /var/lib/kibana /var/log/kibana \
         /etc/logstash /usr/share/logstash /var/lib/logstash /var/log/logstash \
         /etc/filebeat /var/lib/filebeat /etc/metricbeat /var/lib/metricbeat \
         /etc/auditbeat /var/lib/auditbeat /etc/packetbeat /var/lib/packetbeat \
         /opt/elastic /opt/elk /usr/share/elastic-agent /etc/elastic-agent; do
  if [ -e "$d" ]; then echo "PRESENT $d"; ls -la "$d" 2>/dev/null | head -n 15; else echo "absent  $d"; fi
done

sec "DOCKER"
if command -v docker >/dev/null 2>&1; then
  docker version 2>&1 | head -n 20
  echo "--- containers ---"; docker ps -a 2>&1
  echo "--- images ---"; docker images 2>&1
  echo "--- compose projects ---"; docker compose ls 2>&1
else
  echo "docker not installed"
fi

sec "PORTS OF INTEREST (probe)"
for p in 22 80 443 5601 9200 9300 5044 5000 8080 8443 3000 5432 6379 8220 9600; do
  timeout 1 bash -c "</dev/tcp/127.0.0.1/$p" 2>/dev/null && echo "OPEN  $p" || echo "closed $p"
done

sec "ELASTICSEARCH API"
curl -sk --max-time 5 http://127.0.0.1:9200/ 2>&1 | head -n 40
echo "--- cluster health ---"
curl -sk --max-time 5 http://127.0.0.1:9200/_cluster/health?pretty 2>&1 | head -n 30
echo "--- indices ---"
curl -sk --max-time 5 "http://127.0.0.1:9200/_cat/indices?v&s=index" 2>&1 | head -n 60

sec "KIBANA API"
curl -sk --max-time 5 http://127.0.0.1:5601/api/status 2>&1 | head -c 2000
echo

sec "SECURITY POSTURE"
echo "--- ufw ---"; ufw status verbose 2>/dev/null
echo "--- apparmor ---"; aa-status 2>/dev/null | head -n 10
echo "--- sshd effective ---"; sshd -T 2>/dev/null | grep -Ei 'port |passwordauthentication|permitrootlogin|usepam|allowusers|denyusers|pubkeyauthentication|kbdinteractive'
echo "--- nsswitch ---"; grep -E '^(passwd|group|shadow|sudoers):' /etc/nsswitch.conf
echo "--- pam sss ---"; grep -rl sss /etc/pam.d/ 2>/dev/null

sec "LOGS (recent errors)"
journalctl -p err -b --no-pager 2>/dev/null | tail -n 40
echo "--- elasticsearch log tail ---"; tail -n 30 /var/log/elasticsearch/*.log 2>/dev/null
echo "--- kibana log tail ---"; tail -n 20 /var/log/kibana/*.log 2>/dev/null

sec "AUTOSTART / CRON"
crontab -l 2>/dev/null; ls -la /etc/cron.d 2>/dev/null
systemctl list-timers --no-pager --no-legend 2>/dev/null | head -n 20

sec "END OF AUDIT"
