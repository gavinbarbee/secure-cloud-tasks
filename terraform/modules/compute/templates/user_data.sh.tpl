#!/bin/bash
# -----------------------------------------------------------------------------
# Bootstrap private EC2 for AL2023 behind an S3 gateway + interface endpoints.
#
# Logs: /var/log/user-data.log (also tee to logger). Health probe script:
#   /usr/local/bin/secure-cloud-tasks-health.sh
#
# Notes:
# - AL2023 dnf: rewrite s3.dualstack -> s3 in shipped repo files so traffic can use the
#   regional S3 hostname (VPC gateway endpoint + ip_resolve=4). No aws s3 cp of mirror.list:
#   the regional al2023-repos buckets reject normal IAM Head/Get for many accounts.
# - Python deps: install from vendored wheels shipped in app.zip (no PyPI; NAT path to
#   public PyPI was unreliable/timeouts in this VPC).
# -----------------------------------------------------------------------------
set -euo pipefail
exec > >(tee -a /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

REGION="${region}"
BUCKET="${bucket}"
OBJECT_KEY="${object_key}"
SECRET_ARN="${secret_arn}"
APP_PORT="${app_port}"

export AWS_DEFAULT_REGION="$${REGION}"
export AWS_EC2_METADATA_SERVICE_ENDPOINT_MODE="ipv4"

export CURL_LOW_SPEED_LIMIT=1000
export CURL_LOW_SPEED_TIME=900

export PIP_DISABLE_PIP_VERSION_CHECK=1
export PIP_NO_INDEX=1
export PYTHONUNBUFFERED=1

log() {
  echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") [user-data] $*"
}

log "starting secure-cloud-tasks bootstrap (APP_PORT=$${APP_PORT})"

run_with_retries() {
  local desc="$${1}"
  local max="$${2}"
  local wait_s="$${3}"
  shift 3
  local n=0
  until "$@"; do
    local rc=$?
    let n=n+1
    log "WARN: $${desc} exit_code=$${rc} (attempt $${n} of $${max})"
    if [[ "$${n}" -ge "$${max}" ]]; then
      log "ERROR: $${desc} failed after $${max} attempt(s)."
      return 1
    fi
    sleep "$${wait_s}"
  done
  log "OK: $${desc}"
}

# Give interface endpoint + Route53 private zones a moment to converge.
log "waiting for VPC endpoint DNS / routes to settle"
sleep 25

install -d -m 0755 /etc/dnf/dnf.conf.d
cat >/etc/dnf/dnf.conf.d/99-secure-cloud-tasks.conf <<'EOF'
[main]
timeout=900
retries=15
minrate=0
ip_resolve=4
fastestmirror=False
max_parallel_downloads=3
EOF

patch_yum_repos_for_ipv4_s3() {
  log "patching yum repo files: s3.dualstack -> s3 (IPv4 regional S3; works with S3 gateway endpoint)"
  shopt -s nullglob
  local f
  for f in /etc/yum.repos.d/*.repo; do
    if grep -q 's3\.dualstack\.' "$f" 2>/dev/null; then
      sed -i.bak-secure-cloud-tasks 's/s3\.dualstack\./s3./g' "$f"
      log "patched $f"
    fi
  done
  shopt -u nullglob
}

if ! command -v aws >/dev/null 2>&1; then
  log "ERROR: aws CLI not found on AMI"
  exit 1
fi

patch_yum_repos_for_ipv4_s3

shopt -s nullglob
for repo_file in /etc/yum.repos.d/*.repo; do
  if grep -q "^\[kernel-livepatch\]" "$repo_file" 2>/dev/null; then
    log "disabling kernel-livepatch repo where possible ($repo_file)"
    dnf config-manager --set-disabled kernel-livepatch >/dev/null 2>&1 || true
  fi
done
shopt -u nullglob

run_with_retries "dnf clean all" 8 20 dnf -y clean all
run_with_retries "dnf makecache" 15 30 dnf -y makecache
# Do not install full `curl` — it conflicts with AL2023's default curl-minimal (dnf error).
run_with_retries "dnf install (bootstrap packages)" 18 35 \
  dnf -y install python3 python3-pip jq unzip

install -d -m 0755 /opt/secure-cloud-tasks
cd /opt/secure-cloud-tasks
log "working directory: $(pwd)"

run_with_retries "aws s3 cp (app bundle)" 20 25 \
  aws s3 cp "s3://$${BUCKET}/$${OBJECT_KEY}" /tmp/app.zip --region "$${REGION}"

log "app zip size: $(wc -c </tmp/app.zip) bytes"

if command -v unzip >/dev/null 2>&1; then
  unzip -o /tmp/app.zip -d /opt/secure-cloud-tasks
else
  python3 - <<'PY'
import zipfile

zipfile.ZipFile("/tmp/app.zip").extractall("/opt/secure-cloud-tasks")
PY
fi

log "extracted app files (top-level): $(ls -la /opt/secure-cloud-tasks | head)"

log "creating venv"
python3 -m venv .venv
# shellcheck source=/dev/null
source .venv/bin/activate

WHEEL_DIR="/opt/secure-cloud-tasks/wheels"
if [[ ! -d "$${WHEEL_DIR}" ]] || [[ -z "$(ls -A "$${WHEEL_DIR}"/*.whl 2>/dev/null)" ]]; then
  log "ERROR: vendored wheels missing under $${WHEEL_DIR} (expected app.zip to include ./wheels/*.whl)"
  exit 1
fi

log "installing Python packages from vendored wheels only (PIP_NO_INDEX=$${PIP_NO_INDEX})"
run_with_retries "pip install pip/setuptools/wheel from wheels" 6 10 \
  python -m pip install --no-cache-dir --no-index --find-links="$${WHEEL_DIR}" --upgrade pip setuptools wheel

run_with_retries "pip install -r requirements.txt from wheels" 10 15 \
  python -m pip install --no-cache-dir --no-index --find-links="$${WHEEL_DIR}" -r requirements.txt

log "pip freeze (first 30 lines):"
(.venv/bin/python -m pip freeze || true) | head -n 30

log "python import smoke test (Flask/SQLAlchemy/psycopg2/gunicorn)"
.venv/bin/python - <<'PY'
import importlib

for mod in ("flask", "sqlalchemy", "psycopg2", "gunicorn"):
    importlib.import_module(mod)
    print("import ok:", mod)
PY

SECRET_JSON=$(aws secretsmanager get-secret-value \
  --secret-id "$${SECRET_ARN}" --region "$${REGION}" \
  --query SecretString --output text)
export SECRET_JSON

HOST_FOR_WAIT=$(python3 -c "import json, os; print(json.loads(os.environ['SECRET_JSON'])['host'])")
log "waiting for RDS TCP connectivity: $${HOST_FOR_WAIT}:5432"

for attempt in $(seq 1 90); do
  if timeout 3 bash -c "cat < /dev/null > /dev/tcp/$${HOST_FOR_WAIT}/5432" 2>/dev/null; then
    log "RDS is reachable (attempt $${attempt})"
    break
  fi
  log "RDS not ready yet (attempt $${attempt}/90)"
  sleep 10
done

log "writing /etc/sysconfig/secure-cloud-tasks"
python3 <<'PY'
import json, os, subprocess, urllib.parse

region = "${region}"
secret_arn = "${secret_arn}"
raw = subprocess.check_output(
    [
        "aws",
        "secretsmanager",
        "get-secret-value",
        "--secret-id",
        secret_arn,
        "--region",
        region,
        "--query",
        "SecretString",
        "--output",
        "text",
    ],
    text=True,
)
d = json.loads(raw)
user = urllib.parse.quote_plus(d["username"])
pw = urllib.parse.quote_plus(d["password"])
host = d["host"]
port = int(d.get("port", 5432))
dbname = d["dbname"]
url = "postgresql+psycopg2://" + user + ":" + pw + "@" + host + ":" + str(port) + "/" + dbname
escaped = url.replace("\\", "\\\\").replace('"', '\\"')
with open("/etc/sysconfig/secure-cloud-tasks", "w", encoding="utf-8") as f:
    # Quote DATABASE_URL so systemd EnvironmentFile parsing survives odd characters.
    f.write('DATABASE_URL="' + escaped + '"\n')
    f.write("FLASK_ENV=production\n")
PY

chmod 640 /etc/sysconfig/secure-cloud-tasks

log "preflight: import app with DATABASE_URL (may take up to ~5 minutes if RDS is slow)"
set -a
# shellcheck disable=SC1091
source /etc/sysconfig/secure-cloud-tasks
set +a
export FLASK_APP=app:app

run_with_retries "python import app (creates tables)" 35 20 \
  bash -ec 'set -a; . /etc/sysconfig/secure-cloud-tasks; set +a; cd /opt/secure-cloud-tasks && .venv/bin/python -c "import app; print(\"app import ok\")"'

install -d -m 0755 /usr/local/bin
cat >/usr/local/bin/secure-cloud-tasks-health.sh <<'HEALTH'
#!/bin/bash
set -euo pipefail
PORT="${app_port}"
curl -fsS --connect-timeout 3 --max-time 10 "http://127.0.0.1:$${PORT}/health" >/tmp/secure-cloud-tasks-health.json
echo "OK $(date -u +"%Y-%m-%dT%H:%M:%SZ")" >>/var/log/secure-cloud-tasks-health.log
HEALTH
chmod 0755 /usr/local/bin/secure-cloud-tasks-health.sh

log "writing systemd unit"
cat >/etc/systemd/system/secure-cloud-tasks.service <<UNIT
[Unit]
Description=secure-cloud-tasks Flask API (Gunicorn)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/secure-cloud-tasks
EnvironmentFile=/etc/sysconfig/secure-cloud-tasks
Environment=PYTHONUNBUFFERED=1
Environment=FLASK_APP=app:app

ExecStartPre=/bin/bash -ec 'test -x /opt/secure-cloud-tasks/.venv/bin/gunicorn'
ExecStartPre=/bin/bash -ec 'test -f /etc/sysconfig/secure-cloud-tasks'

ExecStart=/opt/secure-cloud-tasks/.venv/bin/gunicorn \\
  --workers 2 \\
  --threads 1 \\
  --timeout 120 \\
  --graceful-timeout 30 \\
  --bind 0.0.0.0:${app_port} \\
  --access-logfile - \\
  --error-logfile - \\
  app:app

Restart=always
RestartSec=3
StartLimitIntervalSec=0

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable secure-cloud-tasks.service

log "starting secure-cloud-tasks.service"
if ! systemctl restart secure-cloud-tasks.service; then
  log "ERROR: systemctl restart failed"
  systemctl status secure-cloud-tasks.service --no-pager -l || true
  journalctl -u secure-cloud-tasks.service --no-pager -n 200 || true
  exit 1
fi

log "waiting for gunicorn to listen on 0.0.0.0:${app_port}"
listener_ok=0
for attempt in $(seq 1 90); do
  if ss -lntp 2>/dev/null | grep -q ":${app_port}"; then
    listener_ok=1
    log "listener detected on :${app_port} (attempt $${attempt})"
    break
  fi
  if ! systemctl is-active --quiet secure-cloud-tasks.service; then
    log "ERROR: service became inactive while waiting for listener"
    systemctl status secure-cloud-tasks.service --no-pager -l || true
    journalctl -u secure-cloud-tasks.service --no-pager -n 200 || true
    exit 1
  fi
  sleep 2
done
if [[ "$listener_ok" -ne 1 ]]; then
  log "ERROR: timed out waiting for a listener on :${app_port}"
  ss -lntp || true
  journalctl -u secure-cloud-tasks.service --no-pager -n 200 || true
  exit 1
fi

log "running local health probe (/usr/local/bin/secure-cloud-tasks-health.sh)"
if ! /usr/local/bin/secure-cloud-tasks-health.sh; then
  log "ERROR: health probe failed"
  journalctl -u secure-cloud-tasks.service --no-pager -n 200 || true
  exit 1
fi

log "bootstrap complete"
