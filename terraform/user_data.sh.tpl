#!/bin/bash
# Bootstrap for the Xora Resolve CloudWatch test lab (Amazon Linux 2023).
# NOTE: this is a Terraform template, so a literal shell "dollar-brace" must be written as $${...}
set -euxo pipefail
exec > >(tee /var/log/xora-bootstrap.log) 2>&1

dnf install -y amazon-cloudwatch-agent stress-ng

mkdir -p /opt/demo-app /opt/chaos
touch /var/log/demo-app.log

# ---------------------------------------------------------------- demo app
cat > /opt/demo-app/app.py <<'EOF'
import logging
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

logging.basicConfig(
    filename="/var/log/demo-app.log",
    level=logging.INFO,
    format="%(asctime)s %(levelname)s demo-app %(message)s",
)
log = logging.getLogger("demo-app")


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, body):
        self.send_response(code)
        self.send_header("Content-Type", "text/plain")
        self.end_headers()
        self.wfile.write(body.encode())

    def do_GET(self):
        if self.path == "/health":
            self._send(200, "ok\n")
        elif self.path == "/error":
            log.error("GET /error 500 - OrderService: db connection refused host=orders-db port=5432 (simulated)")
            self._send(500, "internal error\n")
        else:
            log.info("GET %s 200", self.path)
            self._send(200, "hello from xora demo-app\n")

    def log_message(self, *args):
        pass


log.info("demo-app starting on :8080")
ThreadingHTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
EOF

cat > /etc/systemd/system/demo-app.service <<'EOF'
[Unit]
Description=Xora test demo app
After=network-online.target

[Service]
ExecStart=/usr/bin/python3 /opt/demo-app/app.py
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# ---------------------------------------------- app health -> custom metric
# Publishes XoraTest/AppHealthy (1 = up, 0 = down) every minute.
# Dimension Service=<fixed name> (not InstanceId) so Xora's "service" stays the same when the EC2 is replaced.
cat > /opt/chaos/health-metric.sh <<'EOF'
#!/bin/bash
if curl -sf -m 5 http://localhost:8080/health > /dev/null; then V=1; else V=0; fi
aws cloudwatch put-metric-data --region ${region} --namespace XoraTest \
  --metric-name AppHealthy --dimensions Service=${service_name} --value $V
EOF

cat > /etc/systemd/system/health-metric.service <<'EOF'
[Unit]
Description=Publish demo-app health metric

[Service]
Type=oneshot
ExecStart=/bin/bash /opt/chaos/health-metric.sh
EOF

cat > /etc/systemd/system/health-metric.timer <<'EOF'
[Unit]
Description=Publish demo-app health metric every minute

[Timer]
OnBootSec=60
OnUnitActiveSec=60
AccuracySec=5

[Install]
WantedBy=timers.target
EOF

# ----------------------------------------------------------- chaos scripts
cat > /opt/chaos/flap.sh <<'EOF'
#!/bin/bash
# 3 cycles: 6 min CPU load, then 6 min idle (longer than the 5-min basic-monitoring period)
for i in 1 2 3; do
  stress-ng --cpu 0 --cpu-load 100 --timeout 360s > /dev/null 2>&1
  sleep 360
done
EOF

cat > /opt/chaos/chaos.sh <<'EOF'
#!/bin/bash
# Usage: chaos.sh <cpu|errors|disk|memory|service-down|correlated|flap|stop|status>
set -u
SCENARIO="$1"

bg() { setsid nohup "$@" > /dev/null 2>&1 < /dev/null & }

start_cpu()    { bg stress-ng --cpu 0 --cpu-load 100 --timeout 900s; }
start_errors() { bg bash -c 'for i in $(seq 1 180); do curl -s -o /dev/null http://localhost:8080/error; sleep 1; done'; }

case "$SCENARIO" in
  cpu)          start_cpu ;;
  errors)       start_errors ;;
  disk)
    read -r SIZE USED <<< "$(df --output=size,used -k / | tail -1)"
    TARGET=$(( SIZE * 92 / 100 - USED ))
    if [ "$TARGET" -gt 0 ]; then fallocate -l "$TARGET"K /var/tmp/xora-fill.bin; fi
    ;;
  memory)       bg stress-ng --vm 1 --vm-bytes 85% --vm-keep --timeout 900s ;;
  service-down) systemctl stop demo-app ;;
  correlated)   start_cpu; start_errors ;;
  flap)         bg /bin/bash /opt/chaos/flap.sh ;;
  stop)
    pkill -f flap.sh || true
    pkill -f stress-ng || true
    pkill -f "8080/error" || true
    rm -f /var/tmp/xora-fill.bin
    systemctl start demo-app
    ;;
  status) ;;
  *) echo "unknown scenario: $SCENARIO"; exit 1 ;;
esac

sleep 2
echo "=== scenario: $SCENARIO ==="
echo "--- demo-app: $(systemctl is-active demo-app)"
echo "--- load:"; uptime
echo "--- memory:"; free -m
echo "--- disk /:"; df -h /
echo "--- top processes:"; ps -eo pid,comm,%cpu,%mem --sort=-%cpu | head -6
echo "--- last app log lines:"; tail -n 5 /var/log/demo-app.log
EOF
chmod +x /opt/chaos/*.sh

# ------------------------------------------------------- CloudWatch Agent
cat > /opt/aws/amazon-cloudwatch-agent/etc/config.json <<'EOF'
{
  "agent": { "metrics_collection_interval": 60, "run_as_user": "root" },
  "metrics": {
    "namespace": "CWAgent",
    "append_dimensions": { "InstanceId": "$${aws:InstanceId}" },
    "aggregation_dimensions": [["InstanceId"]],
    "metrics_collected": {
      "mem":  { "measurement": ["mem_used_percent"] },
      "disk": { "measurement": ["used_percent"], "resources": ["/"] }
    }
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/demo-app.log",
            "log_group_name": "${log_group}",
            "log_stream_name": "{instance_id}"
          }
        ]
      }
    }
  }
}
EOF

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 -s -c file:/opt/aws/amazon-cloudwatch-agent/etc/config.json

systemctl daemon-reload
systemctl enable --now demo-app.service
systemctl enable --now health-metric.timer

echo "xora bootstrap complete"
