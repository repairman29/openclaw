#!/usr/bin/env bash
# Copy last 200 lines of Chump log into Maclawd so the agent can read it.
# Run from anywhere: bash scripts/snapshot-chump-log.sh
# Override: CHUMP_LOG_DIR=/path/to/repo/logs bash scripts/snapshot-chump-log.sh

OUT="$HOME/Projects/Maclawd/chump-log-snapshot.txt"
DEFAULT_LOGS="$HOME/Projects/Chump/logs"
mkdir -p "$DEFAULT_LOGS"

# Use CHUMP_LOG_DIR if set and has chump.log; else first candidate that has chump.log
CANDIDATES=(
  "$HOME/Projects/Chump/logs"
  "$HOME/Projects/Maclawd/chump-repo/logs"
)
[[ -n "$CHUMP_LOG_DIR" ]] && CANDIDATES=("$CHUMP_LOG_DIR" "${CANDIDATES[@]}")

LOG_DIR=
for dir in "${CANDIDATES[@]}"; do
  [[ -z "$dir" ]] && continue
  if [[ -f "$dir/chump.log" ]]; then
    LOG_DIR="$dir"
    break
  fi
done

{
  echo "Chump log dir: ${LOG_DIR:-none found}"
  echo ""

  if [[ -n "$LOG_DIR" ]]; then
    echo "--- chump.log (last 200 lines) ---"
    tail -200 "$LOG_DIR/chump.log" 2>&1
    echo ""
    echo "--- discord.log (last 100 lines) ---"
    [[ -f "$LOG_DIR/discord.log" ]] && tail -100 "$LOG_DIR/discord.log" 2>&1 || echo "(no discord.log yet)"
  else
    echo "No chump.log found yet. Logs appear when Chump runs from ~/Projects/Chump."
    echo "ChumpMenu default is now ~/Projects/Chump. Start Chump from the menu or:"
    echo "  cd ~/Projects/Chump && ./run-discord.sh"
    echo "Then run this script again to capture logs."
  fi
} > "$OUT"

echo "Wrote $OUT"
