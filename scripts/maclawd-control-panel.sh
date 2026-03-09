#!/usr/bin/env bash
# Maclawd stack control: start, stop, restart, status.
# ONE build: this repo. Run from repo root: ./scripts/maclawd-control-panel.sh start|stop|restart|status
#
# Gateway and cron:
# - Gateway runs via LaunchAgent ai.openclaw.maclawd (or in foreground via start_gateway).
#   It binds to port 18789 and starts the cron service inside the same process.
# - Cron jobs are stored at ${STATE_DIR}/cron/jobs.json (OPENCLAW_STATE_DIR/cron/jobs.json).
#   The gateway loads this file on start; use "openclaw cron" with OPENCLAW_PROFILE=maclawd
#   to add/list/run jobs. Watchdog runs "control-panel start" periodically and can tune
#   cron job timeouts (maybe_tune_cron_jobs) when OPENCLAW_MACLAWD_ENABLE_CRON_TUNE=1.
# - To manage cron from CLI: OPENCLAW_PROFILE=maclawd OPENCLAW_CONFIG_PATH=$STATE_DIR/openclaw.json \
#   OPENCLAW_STATE_DIR=$STATE_DIR pnpm openclaw cron list

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="${OPENCLAW_MACLAWD_STATE:-${HOME}/.openclaw-maclawd}"
CONFIG_PATH="${STATE_DIR}/openclaw.json"
CRON_JOBS_PATH="${STATE_DIR}/cron/jobs.json"
LOG_DIR="${STATE_DIR}/logs"
PATH="${ROOT_DIR}/node_modules/.bin:${PATH}"

# Use repo build only (same as maclawd-install-keepalive.sh).
if [[ -f "${ROOT_DIR}/dist/index.js" ]]; then
  OPENCLAW_CMD=("node" "${ROOT_DIR}/dist/index.js" "--profile" "maclawd")
else
  OPENCLAW_CMD=("node" "${ROOT_DIR}/openclaw.mjs" "--profile" "maclawd")
fi

# PID file names (relative to STATE_DIR)
PIDS=(gateway.pid memory.pid mlx-workhorse.pid mlx-scout.pid mlx-triage.pid)

# MLX server config: port model
MLX_WORKHORSE_PORT=8000
MLX_WORKHORSE_MODEL="${MLX_WORKHORSE_MODEL:-mlx-community/Qwen2.5-7B-Instruct-4bit}"
MLX_WORKHORSE_ENABLED="${OPENCLAW_MACLAWD_ENABLE_WORKHORSE:-1}"
MLX_SCOUT_PORT=8001
MLX_SCOUT_MODEL="${MLX_SCOUT_MODEL:-mlx-community/Qwen2.5-3B-Instruct-4bit}"
MLX_SCOUT_ENABLED="${OPENCLAW_MACLAWD_ENABLE_SCOUT:-0}"
MLX_TRIAGE_PORT=8003
MLX_TRIAGE_MODEL="${MLX_TRIAGE_MODEL:-mlx-community/Qwen2.5-3B-Instruct-4bit}"
MLX_TRIAGE_ENABLED="${OPENCLAW_MACLAWD_ENABLE_TRIAGE:-0}"
MLX_MAX_TOKENS="${OPENCLAW_MACLAWD_MLX_MAX_TOKENS:-256}"
MLX_PROMPT_CONCURRENCY="${OPENCLAW_MACLAWD_MLX_PROMPT_CONCURRENCY:-1}"
MLX_DECODE_CONCURRENCY="${OPENCLAW_MACLAWD_MLX_DECODE_CONCURRENCY:-1}"
MLX_LOG_LEVEL="${OPENCLAW_MACLAWD_MLX_LOG_LEVEL:-WARNING}"
MLX_READY_RETRIES="${OPENCLAW_MACLAWD_MLX_READY_RETRIES:-45}"
MLX_STABILITY_SECONDS="${OPENCLAW_MACLAWD_MLX_STABILITY_SECONDS:-8}"
MEMORY_PORT=8002
GATEWAY_PORT=18789
SESSIONS_CLEANUP_INTERVAL="${OPENCLAW_MACLAWD_SESSIONS_CLEANUP_INTERVAL:-21600}"
CRON_TUNE_INTERVAL="${OPENCLAW_MACLAWD_CRON_TUNE_INTERVAL:-3600}"
CRON_TUNE_ENABLED="${OPENCLAW_MACLAWD_ENABLE_CRON_TUNE:-1}"
CONFIG_TUNE_INTERVAL="${OPENCLAW_MACLAWD_CONFIG_TUNE_INTERVAL:-3600}"
CONFIG_TUNE_ENABLED="${OPENCLAW_MACLAWD_ENABLE_CONFIG_TUNE:-1}"
FORCE_FINAL_STREAMING="${OPENCLAW_MACLAWD_FORCE_FINAL_STREAMING:-1}"
DISABLE_MODEL_FALLBACKS="${OPENCLAW_MACLAWD_DISABLE_MODEL_FALLBACKS:-1}"
PREFERRED_AGENT_MODEL="${OPENCLAW_MACLAWD_PREFERRED_AGENT_MODEL:-openai/mlx-community/Qwen2.5-7B-Instruct-4bit}"
PREFERRED_CRON_MODEL="${OPENCLAW_MACLAWD_PREFERRED_CRON_MODEL:-ollama/llama3.2:1b}"
FORCE_AGENT_MODEL="${OPENCLAW_MACLAWD_FORCE_AGENT_MODEL:-1}"
CRON_TIMEOUT_CAP="${OPENCLAW_MACLAWD_CRON_TIMEOUT_CAP:-90}"
AUTO_DISABLE_STUCK_CRON="${OPENCLAW_MACLAWD_AUTO_DISABLE_STUCK_CRON:-1}"
CRON_STUCK_ERRORS="${OPENCLAW_MACLAWD_CRON_STUCK_ERRORS:-2}"

log() { printf '%s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

is_port_listening() {
  local port="$1"
  lsof -nP -iTCP:"${port}" -sTCP:LISTEN >/dev/null 2>&1
}

pid_for_listening_port() {
  local port="$1"
  lsof -nP -iTCP:"${port}" -sTCP:LISTEN -t 2>/dev/null | head -n 1
}

wait_for_http_ready() {
  local url="$1"
  local retries="${2:-20}"
  local i
  for ((i = 0; i < retries; i += 1)); do
    if curl -fsS --max-time 2 "${url}" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}

is_truthy() {
  local v="${1:-}"
  v="$(printf '%s' "${v}" | tr '[:upper:]' '[:lower:]')"
  case "${v}" in
    1|true|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

read_lock_pid() {
  local lock_path="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -r '.pid // empty' "${lock_path}" 2>/dev/null || true
    return 0
  fi
  sed -n 's/.*"pid"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "${lock_path}" | head -n 1
}

cleanup_dead_session_locks() {
  local removed=0
  local active=0
  local lock pid
  shopt -s nullglob
  for lock in "${STATE_DIR}"/agents/*/sessions/*.jsonl.lock; do
    pid="$(read_lock_pid "${lock}")"
    if [[ -z "${pid}" ]] || ! kill -0 "${pid}" 2>/dev/null; then
      rm -f "${lock}"
      removed=$((removed + 1))
      continue
    fi
    active=$((active + 1))
  done
  shopt -u nullglob
  if (( removed > 0 )); then
    log "  cleaned stale session locks: removed=${removed}, active=${active}"
  fi
}

should_run_periodic_task() {
  local stamp_file="$1"
  local interval_s="$2"
  local now last
  if ! [[ "${interval_s}" =~ ^[0-9]+$ ]] || (( interval_s <= 0 )); then
    return 1
  fi
  now="$(date +%s)"
  if [[ -f "${stamp_file}" ]]; then
    last="$(cat "${stamp_file}" 2>/dev/null || true)"
  else
    last=""
  fi
  if ! [[ "${last}" =~ ^[0-9]+$ ]]; then
    return 0
  fi
  (( now - last >= interval_s ))
}

maybe_tune_runtime_config() {
  local stamp_file="${STATE_DIR}/.last-config-bandwidth-tune"
  local tune_result=""
  if ! is_truthy "${CONFIG_TUNE_ENABLED}"; then
    return 0
  fi
  if [[ ! -f "${CONFIG_PATH}" ]]; then
    return 0
  fi
  if ! should_run_periodic_task "${stamp_file}" "${CONFIG_TUNE_INTERVAL}"; then
    return 0
  fi
  tune_result="$(
    OPENCLAW_MACLAWD_PREFERRED_AGENT_MODEL="${PREFERRED_AGENT_MODEL}" \
    OPENCLAW_MACLAWD_FORCE_AGENT_MODEL="${FORCE_AGENT_MODEL}" \
    OPENCLAW_MACLAWD_FORCE_FINAL_STREAMING="${FORCE_FINAL_STREAMING}" \
    OPENCLAW_MACLAWD_DISABLE_MODEL_FALLBACKS="${DISABLE_MODEL_FALLBACKS}" \
    node - "${CONFIG_PATH}" <<'NODE'
const fs = require("node:fs");

const configPath = process.argv[2];
const preferredAgentModel =
  process.env.OPENCLAW_MACLAWD_PREFERRED_AGENT_MODEL || "openai/mlx-community/Qwen2.5-7B-Instruct-4bit";
const forceStreamingOff = /^(1|true|yes|on)$/i.test(
  process.env.OPENCLAW_MACLAWD_FORCE_FINAL_STREAMING || "1",
);
const disableFallbacks = /^(1|true|yes|on)$/i.test(
  process.env.OPENCLAW_MACLAWD_DISABLE_MODEL_FALLBACKS || "1",
);
const forceAgentModel = /^(1|true|yes|on)$/i.test(
  process.env.OPENCLAW_MACLAWD_FORCE_AGENT_MODEL || "1",
);

const raw = fs.readFileSync(configPath, "utf8");
const cfg = JSON.parse(raw);
let changed = false;

function asObject(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : null;
}

function ensureObject(parent, key) {
  const current = asObject(parent[key]);
  if (current) {
    return current;
  }
  parent[key] = {};
  changed = true;
  return parent[key];
}

const agents = ensureObject(cfg, "agents");
const defaults = ensureObject(agents, "defaults");
if (defaults.maxConcurrent !== 1) {
  defaults.maxConcurrent = 1;
  changed = true;
}
const model = ensureObject(defaults, "model");
const currentPrimary = typeof model.primary === "string" ? model.primary.trim() : "";
// Only set primary when empty or when forceAgentModel and different from preferred.
// Do not overwrite a valid MLX workhorse primary (we prefer MLX for dogfooding).
const isMlxWorkhorse =
  /^openai\/mlx-community\/Qwen2\.5-(7B|3B)-Instruct-4bit$/.test(currentPrimary) ||
  currentPrimary.startsWith("mlx-workhorse/");
if (currentPrimary.length === 0) {
  model.primary = preferredAgentModel;
  changed = true;
} else if (forceAgentModel && currentPrimary !== preferredAgentModel && !isMlxWorkhorse) {
  model.primary = preferredAgentModel;
  changed = true;
}
if (disableFallbacks) {
  if (!Array.isArray(model.fallbacks) || model.fallbacks.length !== 0) {
    model.fallbacks = [];
    changed = true;
  }
}

if (defaults.verboseDefault !== "off") {
  defaults.verboseDefault = "off";
  changed = true;
}

if (forceStreamingOff) {
  const channels = asObject(cfg.channels);
  if (channels) {
    for (const channelName of ["discord", "telegram"]) {
      const channelCfg = asObject(channels[channelName]);
      if (!channelCfg) continue;
      if (channelCfg.streaming !== "off") {
        channelCfg.streaming = "off";
        changed = true;
      }
    }
  }
}

if (!changed) {
  process.stdout.write("unchanged");
  process.exit(0);
}

const stats = fs.statSync(configPath);
fs.writeFileSync(configPath, `${JSON.stringify(cfg, null, 2)}\n`, { mode: stats.mode });
process.stdout.write("changed");
NODE
  )"
  if [[ "${tune_result}" == "changed" ]]; then
    log "  tuned runtime config for low-bandwidth defaults (${CONFIG_PATH})"
  fi
  date +%s >"${stamp_file}"
}

maybe_tune_cron_jobs() {
  local stamp_file="${STATE_DIR}/.last-cron-bandwidth-tune"
  local tune_result=""
  if ! is_truthy "${CRON_TUNE_ENABLED}"; then
    return 0
  fi
  if [[ ! -f "${CRON_JOBS_PATH}" ]]; then
    return 0
  fi
  if ! should_run_periodic_task "${stamp_file}" "${CRON_TUNE_INTERVAL}"; then
    return 0
  fi
  tune_result="$(
    OPENCLAW_MACLAWD_PREFERRED_CRON_MODEL="${PREFERRED_CRON_MODEL}" \
    OPENCLAW_MACLAWD_CRON_TIMEOUT_CAP="${CRON_TIMEOUT_CAP}" \
    OPENCLAW_MACLAWD_AUTO_DISABLE_STUCK_CRON="${AUTO_DISABLE_STUCK_CRON}" \
    OPENCLAW_MACLAWD_CRON_STUCK_ERRORS="${CRON_STUCK_ERRORS}" \
    node - "${CRON_JOBS_PATH}" <<'NODE'
const fs = require("node:fs");

const jobsPath = process.argv[2];
const preferredCronModel = process.env.OPENCLAW_MACLAWD_PREFERRED_CRON_MODEL || "ollama/llama3.2:1b";
const timeoutCap = Number.parseInt(process.env.OPENCLAW_MACLAWD_CRON_TIMEOUT_CAP || "90", 10);
const cronTimeoutCap = Number.isFinite(timeoutCap) && timeoutCap > 0 ? timeoutCap : 90;
const stuckErrorsRaw = Number.parseInt(process.env.OPENCLAW_MACLAWD_CRON_STUCK_ERRORS || "2", 10);
const stuckErrorsThreshold = Number.isFinite(stuckErrorsRaw) && stuckErrorsRaw > 0 ? stuckErrorsRaw : 2;
const autoDisableStuckCron = /^(1|true|yes|on)$/i.test(
  process.env.OPENCLAW_MACLAWD_AUTO_DISABLE_STUCK_CRON || "1",
);

const raw = fs.readFileSync(jobsPath, "utf8");
const doc = JSON.parse(raw);
if (!Array.isArray(doc.jobs)) {
  process.stdout.write("unchanged");
  process.exit(0);
}
let changed = false;
for (const job of doc.jobs) {
  if (!job || typeof job !== "object") continue;
  if (typeof job.agentId === "string" && job.agentId.trim() && job.agentId !== "main") {
    job.agentId = "main";
    changed = true;
  }
  const payload = job.payload;
  if (!payload || payload.kind !== "agentTurn") continue;
  const payloadModel = typeof payload.model === "string" ? payload.model.trim() : "";
  if (
    payloadModel.length === 0 ||
    payloadModel.startsWith("mlx-community/") ||
    payloadModel.startsWith("mlx-triage/") ||
    payloadModel.startsWith("mlx-scout/") ||
    payloadModel.startsWith("mlx-workhorse/")
  ) {
    payload.model = preferredCronModel;
    changed = true;
  }
  if (payload.lightContext !== true) {
    payload.lightContext = true;
    changed = true;
  }
  if (payload.thinking !== "off") {
    payload.thinking = "off";
    changed = true;
  }
  if (
    typeof payload.timeoutSeconds !== "number" ||
    !Number.isFinite(payload.timeoutSeconds) ||
    payload.timeoutSeconds <= 0 ||
    payload.timeoutSeconds > cronTimeoutCap
  ) {
    payload.timeoutSeconds = cronTimeoutCap;
    changed = true;
  }
  const consecutiveErrors =
    typeof job?.state?.consecutiveErrors === "number" && Number.isFinite(job.state.consecutiveErrors)
      ? job.state.consecutiveErrors
      : 0;
  const everyMs =
    job?.schedule?.kind === "every" &&
    typeof job.schedule.everyMs === "number" &&
    Number.isFinite(job.schedule.everyMs)
      ? job.schedule.everyMs
      : null;
  const lastDurationMs =
    typeof job?.state?.lastDurationMs === "number" && Number.isFinite(job.state.lastDurationMs)
      ? job.state.lastDurationMs
      : 0;
  const timeoutMs = payload.timeoutSeconds * 1000;
  const lastError =
    typeof job?.state?.lastError === "string" ? job.state.lastError.toLowerCase() : "";
  const timedOutRecently =
    (lastError.includes("timed out") || lastError.includes("timeout")) &&
    (lastDurationMs === 0 || lastDurationMs >= Math.max(5_000, Math.floor(timeoutMs * 0.9)));

  if (job.enabled === true && consecutiveErrors >= 3 && everyMs != null && everyMs <= 30 * 60 * 1000) {
    job.enabled = false;
    changed = true;
    continue;
  }
  if (job.enabled === true && autoDisableStuckCron && consecutiveErrors >= stuckErrorsThreshold && timedOutRecently) {
    job.enabled = false;
    changed = true;
  }
}
if (!changed) {
  process.stdout.write("unchanged");
  process.exit(0);
}
const stats = fs.statSync(jobsPath);
fs.writeFileSync(jobsPath, `${JSON.stringify(doc, null, 2)}\n`, { mode: stats.mode });
process.stdout.write("changed");
NODE
  )"
  if [[ "${tune_result}" == "changed" ]]; then
    log "  tuned cron jobs for low-bandwidth defaults (${CRON_JOBS_PATH})"
  fi
  date +%s >"${stamp_file}"
}

maybe_run_sessions_cleanup() {
  local stamp_file="${STATE_DIR}/.last-sessions-cleanup"
  local cleanup_log="${LOG_DIR}/sessions-cleanup.log"
  if [[ ! -f "${CONFIG_PATH}" ]]; then
    return 0
  fi
  if ! should_run_periodic_task "${stamp_file}" "${SESSIONS_CLEANUP_INTERVAL}"; then
    return 0
  fi
  log "  running sessions cleanup (all agents)"
  if "${OPENCLAW_CMD[@]}" sessions cleanup --all-agents --enforce --fix-missing --json \
      >>"${cleanup_log}" 2>&1; then
    date +%s >"${stamp_file}"
    log "  sessions cleanup complete"
  else
    warn "sessions cleanup failed; see ${cleanup_log}"
  fi
}

warn_if_recent_telegram_conflicts() {
  local gateway_log="/tmp/openclaw/openclaw-$(date +%F).log"
  local age_s
  if [[ ! -f "${gateway_log}" ]]; then
    return 0
  fi
  age_s="$(python3 - "${gateway_log}" <<'PY'
import datetime as dt
import json
import sys

path = sys.argv[1]
last = None
try:
    with open(path, "r", encoding="utf-8", errors="ignore") as fh:
        lines = fh.readlines()[-2500:]
except OSError:
    print("")
    raise SystemExit(0)

for line in lines:
    if "Telegram getUpdates conflict" not in line:
        continue
    try:
        payload = json.loads(line)
    except Exception:
        continue
    raw_ts = payload.get("time") or payload.get("_meta", {}).get("date")
    if not isinstance(raw_ts, str) or not raw_ts:
        continue
    try:
        ts = dt.datetime.fromisoformat(raw_ts.replace("Z", "+00:00"))
    except Exception:
        continue
    if last is None or ts > last:
        last = ts

if last is None:
    print("")
    raise SystemExit(0)

now = dt.datetime.now(last.tzinfo) if last.tzinfo else dt.datetime.now()
age = int((now - last).total_seconds())
print(str(max(age, 0)))
PY
)"
  if [[ "${age_s}" =~ ^[0-9]+$ ]] && (( age_s <= 1800 )); then
    warn "telegram getUpdates conflicts detected in the last $((age_s / 60))m; verify this bot token is not used by another instance"
  fi
}

warn_if_legacy_orchestrator_running() {
  if pgrep -f "${HOME}/.maclawd/agent/index.js" >/dev/null 2>&1; then
    warn "legacy ai.maclawd.orchestrator is running; it can duplicate polling and waste bandwidth"
    warn "disable with: launchctl bootout gui/\$UID/ai.maclawd.orchestrator && launchctl disable gui/\$UID/ai.maclawd.orchestrator"
  fi
}

kill_by_pidfile() {
  local pf="$1"
  local pid
  if [[ -f "${pf}" ]]; then
    pid="$(cat "${pf}" 2>/dev/null || true)"
    if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
      kill "${pid}" 2>/dev/null || kill -9 "${pid}" 2>/dev/null || true
      log "Stopped pid ${pid} (${pf})"
    fi
    rm -f "${pf}"
  fi
}

cmd_stop() {
  log "==> Stopping Maclawd stack..."
  for name in "${PIDS[@]}"; do
    kill_by_pidfile "${STATE_DIR}/${name}"
  done
  log "==> Stopped."
}

cmd_status() {
  log "==> Maclawd stack status"
  warn_if_legacy_orchestrator_running
  warn_if_recent_telegram_conflicts
  printf '%-20s %-8s %s\n' "COMPONENT" "PID" "STATUS"
  printf '%-20s %-8s %s\n' "--------" "---" "------"
  for name in "${PIDS[@]}"; do
    local pf="${STATE_DIR}/${name}"
    local pid=""
    local status="stopped"
    if [[ -f "${pf}" ]]; then
      pid="$(cat "${pf}" 2>/dev/null || true)"
      if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
        status="running"
      else
        status="stale"
      fi
    fi
    # Gateway may be launchd-managed (no pid file, port in use)
    if [[ "${name}" == "gateway.pid" ]] && [[ -z "${pid}" || "${status}" == "stale" ]]; then
      if is_port_listening "${GATEWAY_PORT}"; then
        status="running (launchd)"
        pid="—"
      fi
    fi
    printf '%-20s %-8s %s\n' "${name%.pid}" "${pid:-—}" "${status}"
  done
}

start_mlx() {
  local name="$1" port="$2" model="$3"
  local pidfile="${STATE_DIR}/mlx-${name}.pid"
  local logfile="${LOG_DIR}/mlx-${name}.log"
  local existing_pid=""
  local spawned_pid=""
  local listener_pid=""
  existing_pid="$(cat "${pidfile}" 2>/dev/null || true)"
  if [[ -n "${existing_pid}" ]] && kill -0 "${existing_pid}" 2>/dev/null; then
    log "  ${name} already running (port ${port}, pid ${existing_pid})"
    return 0
  fi
  if is_port_listening "${port}"; then
    existing_pid="$(pid_for_listening_port "${port}" || true)"
    if [[ -n "${existing_pid}" ]]; then
      printf '%s\n' "${existing_pid}" >"${pidfile}"
    fi
    log "  ${name} already listening on port ${port}${existing_pid:+ (pid ${existing_pid})}"
    return 0
  fi
  mkdir -p "${LOG_DIR}"
  if ! command -v mlx_lm.server &>/dev/null; then
    fail "mlx_lm.server not found: install mlx or mlx-lm"
  fi
  log "  Starting ${name} on port ${port} (max_tokens=${MLX_MAX_TOKENS}, prompt_concurrency=${MLX_PROMPT_CONCURRENCY}, decode_concurrency=${MLX_DECODE_CONCURRENCY})..."
  nohup mlx_lm.server --model "${model}" --host 127.0.0.1 --port "${port}" \
    --max-tokens "${MLX_MAX_TOKENS}" \
    --prompt-concurrency "${MLX_PROMPT_CONCURRENCY}" \
    --decode-concurrency "${MLX_DECODE_CONCURRENCY}" \
    --log-level "${MLX_LOG_LEVEL}" \
    >>"${logfile}" 2>&1 &
  spawned_pid="$!"
  echo "${spawned_pid}" >"${pidfile}"
  if ! wait_for_http_ready "http://127.0.0.1:${port}/v1/models" "${MLX_READY_RETRIES}"; then
    if ! kill -0 "${spawned_pid}" 2>/dev/null; then
      warn "  ${name} crashed before readiness; tail ${logfile}"
    fi
    log "  ${name} failed to start; check ${logfile}"
    rm -f "${pidfile}"
    return 1
  fi
  # Probe for brief warm-up stability to avoid stale pid files after fast OOM crashes.
  sleep "${MLX_STABILITY_SECONDS}"
  if ! kill -0 "${spawned_pid}" 2>/dev/null; then
    warn "  ${name} crashed during warm-up; tail ${logfile}"
    rm -f "${pidfile}"
    return 1
  fi
  listener_pid="$(pid_for_listening_port "${port}" || true)"
  if [[ -n "${listener_pid}" ]] && [[ "${listener_pid}" != "${spawned_pid}" ]]; then
    echo "${listener_pid}" >"${pidfile}"
  fi
  log "  ${name} started (pid $(cat "${pidfile}"), model ${model})"
}

start_memory() {
  local pidfile="${STATE_DIR}/memory.pid"
  local logfile="${LOG_DIR}/memory.log"
  local script="${ROOT_DIR}/scripts/maclawd-memory-server.py"
  local existing_pid=""
  existing_pid="$(cat "${pidfile}" 2>/dev/null || true)"
  if [[ -n "${existing_pid}" ]] && kill -0 "${existing_pid}" 2>/dev/null; then
    log "  memory already running (port ${MEMORY_PORT}, pid ${existing_pid})"
    return 0
  fi
  if is_port_listening "${MEMORY_PORT}"; then
    existing_pid="$(pid_for_listening_port "${MEMORY_PORT}" || true)"
    if [[ -n "${existing_pid}" ]]; then
      printf '%s\n' "${existing_pid}" >"${pidfile}"
    fi
    log "  memory already listening on port ${MEMORY_PORT}${existing_pid:+ (pid ${existing_pid})}"
    return 0
  fi
  if [[ ! -f "${script}" ]]; then
    warn "  memory server script not found: ${script}; skipping"
    return 0
  fi
  mkdir -p "${LOG_DIR}"
  log "  Starting memory service on port ${MEMORY_PORT}..."
  nohup python3 "${script}" >>"${logfile}" 2>&1 &
  echo $! >"${pidfile}"
  if ! wait_for_http_ready "http://127.0.0.1:${MEMORY_PORT}/health" 12; then
    log "  memory failed to start; check ${logfile}"
    rm -f "${pidfile}"
    return 1
  fi
  log "  memory started (pid $(cat "${pidfile}"))"
}

start_gateway() {
  local pidfile="${STATE_DIR}/gateway.pid"
  local logfile="${LOG_DIR}/gateway.log"
  local existing_pid=""
  existing_pid="$(cat "${pidfile}" 2>/dev/null || true)"
  if [[ -n "${existing_pid}" ]] && kill -0 "${existing_pid}" 2>/dev/null; then
    log "  gateway already running (port ${GATEWAY_PORT}, pid ${existing_pid})"
    return 0
  fi
  # Skip if port in use (e.g. launchd-managed gateway)
  if is_port_listening "${GATEWAY_PORT}"; then
    existing_pid="$(pid_for_listening_port "${GATEWAY_PORT}" || true)"
    log "  gateway already running on port ${GATEWAY_PORT}${existing_pid:+ (pid ${existing_pid})} (launchd?)"
    return 0
  fi
  if [[ ! -f "${CONFIG_PATH}" ]]; then
    fail "Config not found: ${CONFIG_PATH}; run openclaw onboard or create config first"
  fi
  mkdir -p "${LOG_DIR}"
  log "  Starting gateway on port ${GATEWAY_PORT}..."
  export OPENCLAW_CONFIG_PATH="${CONFIG_PATH}"
  export OPENCLAW_STATE_DIR="${STATE_DIR}"
  export OPENCLAW_PROFILE=maclawd
  nohup "${OPENCLAW_CMD[@]}" gateway run --bind loopback --port "${GATEWAY_PORT}" \
    >>"${logfile}" 2>&1 &
  echo $! >"${pidfile}"
  if ! wait_for_http_ready "http://127.0.0.1:${GATEWAY_PORT}/" 20; then
    log "  gateway failed to start; check ${logfile}"
    rm -f "${pidfile}"
    return 1
  fi
  log "  gateway started (pid $(cat "${pidfile}"))"
}

disable_mlx_if_needed() {
  local enabled="$1"
  local name="$2"
  local pidfile="${STATE_DIR}/mlx-${name}.pid"
  local env_key=""
  if [[ "${enabled}" == "1" ]]; then
    return 0
  fi
  if [[ -f "${pidfile}" ]]; then
    kill_by_pidfile "${pidfile}"
  fi
  case "${name}" in
    workhorse) env_key="OPENCLAW_MACLAWD_ENABLE_WORKHORSE" ;;
    scout) env_key="OPENCLAW_MACLAWD_ENABLE_SCOUT" ;;
    triage) env_key="OPENCLAW_MACLAWD_ENABLE_TRIAGE" ;;
    *) env_key="OPENCLAW_MACLAWD_ENABLE_COMPONENT" ;;
  esac
  log "  ${name} disabled (set ${env_key}=1 to enable)"
}

cmd_start() {
  log "==> Starting Maclawd stack..."
  warn_if_legacy_orchestrator_running
  mkdir -p "${STATE_DIR}" "${LOG_DIR}"
  cleanup_dead_session_locks
  maybe_tune_runtime_config
  maybe_tune_cron_jobs
  maybe_run_sessions_cleanup
  if is_truthy "${MLX_WORKHORSE_ENABLED}"; then
    start_mlx workhorse "${MLX_WORKHORSE_PORT}" "${MLX_WORKHORSE_MODEL}"
  else
    disable_mlx_if_needed "${MLX_WORKHORSE_ENABLED}" "workhorse"
  fi
  if is_truthy "${MLX_SCOUT_ENABLED}"; then
    start_mlx scout "${MLX_SCOUT_PORT}" "${MLX_SCOUT_MODEL}"
  else
    disable_mlx_if_needed "${MLX_SCOUT_ENABLED}" "scout"
  fi
  if is_truthy "${MLX_TRIAGE_ENABLED}"; then
    start_mlx triage "${MLX_TRIAGE_PORT}" "${MLX_TRIAGE_MODEL}"
  else
    disable_mlx_if_needed "${MLX_TRIAGE_ENABLED}" "triage"
  fi
  start_memory
  start_gateway
  log "==> Started. Run: ./scripts/maclawd-control-panel.sh status"
}

cmd_restart() {
  cmd_stop
  sleep 2
  cmd_start
}

usage() {
  printf 'Usage: %s <start|stop|restart|status>\n' "$(basename "$0")"
  exit 1
}

case "${1:-}" in
  start)   cmd_start ;;
  stop)    cmd_stop ;;
  restart) cmd_restart ;;
  status)  cmd_status ;;
  *)       usage ;;
esac
