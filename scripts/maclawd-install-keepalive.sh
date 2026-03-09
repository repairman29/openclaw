#!/usr/bin/env bash
# Install Maclawd keep-online: gateway LaunchAgent + watchdog for MLX/memory.
# ONE build: this repo. Run from repo root: pnpm build && ./scripts/maclawd-install-keepalive.sh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="${OPENCLAW_MACLAWD_STATE:-${HOME}/.openclaw-maclawd}"
CONFIG_PATH="${STATE_DIR}/openclaw.json"
LOG_DIR="${STATE_DIR}/logs"
PATH="${ROOT_DIR}/node_modules/.bin:${PATH}"

# Always use repo build so the LaunchAgent plist points at this repo (one source of truth).
if [[ -f "${ROOT_DIR}/dist/index.js" ]]; then
  OPENCLAW_CMD=("node" "${ROOT_DIR}/dist/index.js" "--profile" "maclawd")
else
  OPENCLAW_CMD=("node" "${ROOT_DIR}/openclaw.mjs" "--profile" "maclawd")
  if [[ ! -f "${ROOT_DIR}/openclaw.mjs" ]]; then
    echo "ERROR: No dist/index.js or openclaw.mjs. Run: pnpm build" >&2
    exit 1
  fi
fi

GATEWAY_LABEL="ai.openclaw.maclawd"
WATCHDOG_LABEL="ai.openclaw.maclawd.watchdog"
LEGACY_ORCHESTRATOR_LABEL="ai.maclawd.orchestrator"
DEFAULT_GATEWAY_LABEL="ai.openclaw.gateway"
WATCHDOG_INTERVAL="${OPENCLAW_MACLAWD_WATCHDOG_INTERVAL:-900}"
SESSIONS_CLEANUP_INTERVAL="${OPENCLAW_MACLAWD_SESSIONS_CLEANUP_INTERVAL:-21600}"
CRON_TUNE_INTERVAL="${OPENCLAW_MACLAWD_CRON_TUNE_INTERVAL:-3600}"
CONFIG_TUNE_INTERVAL="${OPENCLAW_MACLAWD_CONFIG_TUNE_INTERVAL:-3600}"
PREFERRED_AGENT_MODEL="${OPENCLAW_MACLAWD_PREFERRED_AGENT_MODEL:-openai/mlx-community/Qwen2.5-7B-Instruct-4bit}"
PREFERRED_CRON_MODEL="${OPENCLAW_MACLAWD_PREFERRED_CRON_MODEL:-ollama/llama3.2:1b}"
CRON_TIMEOUT_CAP="${OPENCLAW_MACLAWD_CRON_TIMEOUT_CAP:-90}"
CRON_STUCK_ERRORS="${OPENCLAW_MACLAWD_CRON_STUCK_ERRORS:-2}"
MLX_WORKHORSE_ENABLED="${OPENCLAW_MACLAWD_ENABLE_WORKHORSE:-1}"
MLX_SCOUT_ENABLED="${OPENCLAW_MACLAWD_ENABLE_SCOUT:-0}"
MLX_TRIAGE_ENABLED="${OPENCLAW_MACLAWD_ENABLE_TRIAGE:-0}"
MLX_WORKHORSE_MODEL="${MLX_WORKHORSE_MODEL:-mlx-community/Qwen2.5-7B-Instruct-4bit}"
MLX_SCOUT_MODEL="${MLX_SCOUT_MODEL:-mlx-community/Qwen2.5-3B-Instruct-4bit}"
MLX_TRIAGE_MODEL="${MLX_TRIAGE_MODEL:-mlx-community/Qwen2.5-3B-Instruct-4bit}"
MLX_MAX_TOKENS="${OPENCLAW_MACLAWD_MLX_MAX_TOKENS:-256}"
MLX_PROMPT_CONCURRENCY="${OPENCLAW_MACLAWD_MLX_PROMPT_CONCURRENCY:-1}"
MLX_DECODE_CONCURRENCY="${OPENCLAW_MACLAWD_MLX_DECODE_CONCURRENCY:-1}"
MLX_LOG_LEVEL="${OPENCLAW_MACLAWD_MLX_LOG_LEVEL:-WARNING}"
MLX_READY_RETRIES="${OPENCLAW_MACLAWD_MLX_READY_RETRIES:-45}"
MLX_STABILITY_SECONDS="${OPENCLAW_MACLAWD_MLX_STABILITY_SECONDS:-8}"

log() { printf '%s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# 1. Install gateway LaunchAgent (KeepAlive, RunAtLoad)
install_gateway() {
  if [[ ! -f "${CONFIG_PATH}" ]]; then
    fail "Config not found: ${CONFIG_PATH}; run openclaw onboard or create config first"
  fi
  log "==> Installing gateway LaunchAgent (${GATEWAY_LABEL})..."
  export OPENCLAW_CONFIG_PATH="${CONFIG_PATH}"
  export OPENCLAW_STATE_DIR="${STATE_DIR}"
  export OPENCLAW_PROFILE=maclawd
  (cd "${ROOT_DIR}" && "${OPENCLAW_CMD[@]}" gateway install --port 18789 --force) \
    || fail "Gateway install failed"
  log "  Gateway LaunchAgent installed. Start with: launchctl kickstart -k gui/\$UID/${GATEWAY_LABEL}"
}

# 2. Install watchdog LaunchAgent (runs control panel start every N min)
install_watchdog() {
  mkdir -p "${LOG_DIR}"
  local plist_path="${HOME}/Library/LaunchAgents/${WATCHDOG_LABEL}.plist"
  local stdout_path="${LOG_DIR}/watchdog.log"
  local stderr_path="${LOG_DIR}/watchdog.err.log"

  log "==> Installing watchdog LaunchAgent (${WATCHDOG_LABEL})..."
  cat > "${plist_path}" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>Label</key>
    <string>${WATCHDOG_LABEL}</string>
    <key>Comment</key>
    <string>Maclawd watchdog: ensure MLX + memory are running (gateway managed by ai.openclaw.maclawd)</string>
    <key>RunAtLoad</key>
    <true/>
    <key>StartInterval</key>
    <integer>${WATCHDOG_INTERVAL}</integer>
    <key>AbandonProcessGroup</key>
    <true/>
    <key>ProgramArguments</key>
    <array>
      <string>/bin/bash</string>
      <string>-lc</string>
      <string>cd ${ROOT_DIR} &amp;&amp; OPENCLAW_PROFILE=maclawd OPENCLAW_MACLAWD_STATE=${STATE_DIR} OPENCLAW_MACLAWD_SESSIONS_CLEANUP_INTERVAL=${SESSIONS_CLEANUP_INTERVAL} OPENCLAW_MACLAWD_CRON_TUNE_INTERVAL=${CRON_TUNE_INTERVAL} OPENCLAW_MACLAWD_ENABLE_CRON_TUNE=1 OPENCLAW_MACLAWD_CONFIG_TUNE_INTERVAL=${CONFIG_TUNE_INTERVAL} OPENCLAW_MACLAWD_ENABLE_CONFIG_TUNE=1 OPENCLAW_MACLAWD_FORCE_FINAL_STREAMING=1 OPENCLAW_MACLAWD_DISABLE_MODEL_FALLBACKS=1 OPENCLAW_MACLAWD_PREFERRED_AGENT_MODEL=${PREFERRED_AGENT_MODEL} OPENCLAW_MACLAWD_FORCE_AGENT_MODEL=1 OPENCLAW_MACLAWD_PREFERRED_CRON_MODEL=${PREFERRED_CRON_MODEL} OPENCLAW_MACLAWD_CRON_TIMEOUT_CAP=${CRON_TIMEOUT_CAP} OPENCLAW_MACLAWD_AUTO_DISABLE_STUCK_CRON=1 OPENCLAW_MACLAWD_CRON_STUCK_ERRORS=${CRON_STUCK_ERRORS} OPENCLAW_MACLAWD_ENABLE_WORKHORSE=${MLX_WORKHORSE_ENABLED} OPENCLAW_MACLAWD_ENABLE_SCOUT=${MLX_SCOUT_ENABLED} OPENCLAW_MACLAWD_ENABLE_TRIAGE=${MLX_TRIAGE_ENABLED} MLX_WORKHORSE_MODEL=${MLX_WORKHORSE_MODEL} MLX_SCOUT_MODEL=${MLX_SCOUT_MODEL} MLX_TRIAGE_MODEL=${MLX_TRIAGE_MODEL} OPENCLAW_MACLAWD_MLX_MAX_TOKENS=${MLX_MAX_TOKENS} OPENCLAW_MACLAWD_MLX_PROMPT_CONCURRENCY=${MLX_PROMPT_CONCURRENCY} OPENCLAW_MACLAWD_MLX_DECODE_CONCURRENCY=${MLX_DECODE_CONCURRENCY} OPENCLAW_MACLAWD_MLX_LOG_LEVEL=${MLX_LOG_LEVEL} OPENCLAW_MACLAWD_MLX_READY_RETRIES=${MLX_READY_RETRIES} OPENCLAW_MACLAWD_MLX_STABILITY_SECONDS=${MLX_STABILITY_SECONDS} ./scripts/maclawd-control-panel.sh start</string>
    </array>
    <key>StandardOutPath</key>
    <string>${stdout_path}</string>
    <key>StandardErrorPath</key>
    <string>${stderr_path}</string>
    <key>EnvironmentVariables</key>
    <dict>
      <key>PATH</key>
      <string>${ROOT_DIR}/node_modules/.bin:${HOME}/Library/pnpm:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
    </dict>
  </dict>
</plist>
EOF
  log "  Wrote ${plist_path}"

  # Reload to ensure updated ProgramArguments/environment are applied.
  if launchctl print "gui/$(id -u)/${WATCHDOG_LABEL}" &>/dev/null; then
    log "  Reloading watchdog..."
    launchctl bootout "gui/$(id -u)/${WATCHDOG_LABEL}" || true
  else
    log "  Loading watchdog..."
  fi
  launchctl bootstrap "gui/$(id -u)" "${plist_path}" || fail "Watchdog load failed"
  launchctl kickstart -k "gui/$(id -u)/${WATCHDOG_LABEL}" || true
  log "  Watchdog runs every ${WATCHDOG_INTERVAL}s. Logs: ${stdout_path}"
}

disable_conflicting_agents() {
  local uid
  uid="$(id -u)"

  if launchctl print "gui/${uid}/${LEGACY_ORCHESTRATOR_LABEL}" &>/dev/null; then
    log "==> Stopping legacy orchestrator (${LEGACY_ORCHESTRATOR_LABEL}) to avoid duplicate channel polling..."
    launchctl bootout "gui/${uid}/${LEGACY_ORCHESTRATOR_LABEL}" || true
    launchctl disable "gui/${uid}/${LEGACY_ORCHESTRATOR_LABEL}" || true
  fi

  if launchctl print "gui/${uid}/${DEFAULT_GATEWAY_LABEL}" &>/dev/null; then
    log "==> Stopping default gateway agent (${DEFAULT_GATEWAY_LABEL}) to avoid port/token drift..."
    launchctl bootout "gui/${uid}/${DEFAULT_GATEWAY_LABEL}" || true
    launchctl disable "gui/${uid}/${DEFAULT_GATEWAY_LABEL}" || true
  fi
}

# 3. Start gateway if not running
start_gateway() {
  if launchctl print "gui/$(id -u)/${GATEWAY_LABEL}" 2>/dev/null | grep -q 'state = running'; then
    log "  Gateway already running"
    return 0
  fi
  log "==> Starting gateway..."
  launchctl kickstart -k "gui/$(id -u)/${GATEWAY_LABEL}" || warn "Gateway kickstart failed (may need manual start)"
}

main() {
  log "Maclawd keep-online install"
  log "  Config: ${CONFIG_PATH}"
  log "  State:  ${STATE_DIR}"
  install_gateway
  install_watchdog
  disable_conflicting_agents
  start_gateway
  log ""
  log "Done. Verify with:"
  log "  ./scripts/maclawd-control-panel.sh status"
  log "  launchctl print gui/\$UID/${GATEWAY_LABEL}"
}

main "$@"
