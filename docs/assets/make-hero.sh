#!/usr/bin/env bash
# Regenerates docs/assets/hero.png from a fake session registry, without touching ~/.claude.
#
#   docs/assets/make-hero.sh [hover-row]
#
# Builds the debug binary, starts four `sleep` processes as live pids, writes a registry file for
# each (made-up names, cwd under /Users/demo), runs the bare binary with --snapshot, then composes
# the snapshot with make-hero.swift. One session finishes during the run, so the mint "just
# finished" face shows. The sleeps are killed by pid at the end; no other process is touched.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOVER="${1:-0}"
WORK="$(mktemp -d)"
SESSIONS="$WORK/sessions"
mkdir -p "$SESSIONS"
PIDS=()
cleanup() {
    for pid in ${PIDS[@]+"${PIDS[@]}"}; do kill "$pid" 2>/dev/null || true; done
    rm -rf "$WORK"
}
trap cleanup EXIT

cd "$ROOT"
swift build
BIN_DIR="$(swift build --show-bin-path)"
BIN="$BIN_DIR/Wallflower"   # the executable product
[[ -x "$BIN" ]] || BIN="$BIN_DIR/AgentOverview"   # older checkouts

now_ms() { echo $(($(date +%s) * 1000)); }
NOW=$(now_ms)

# write_session <pid> <name> <project> <status> <waitingFor or -> <minutes in state>
write_session() {
    local pid=$1 name=$2 project=$3 status=$4 waiting=$5 minutes=$6
    local since=$((NOW - minutes * 60000))
    local waiting_line=""
    [[ "$waiting" != "-" ]] && waiting_line=$',\n  "waitingFor": "'"$waiting"'"'
    cat > "$SESSIONS/$pid.json" <<JSON
{
  "pid": $pid,
  "sessionId": "$(uuidgen | tr 'A-Z' 'a-z')",
  "cwd": "/Users/demo/Developer/$project",
  "startedAt": $((since - 1200000)),
  "version": "2.1.295",
  "kind": "interactive",
  "entrypoint": "claude-desktop",
  "hostSessionId": "local_$(uuidgen | tr 'A-Z' 'a-z')",
  "name": "$name",
  "nameSource": "user",
  "status": "$status",
  "updatedAt": $since,
  "statusUpdatedAt": $since$waiting_line
}
JSON
}

start_sleep() { sleep 1200 & PIDS+=("$!"); }

start_sleep; write_session "${PIDS[0]}" "Plan the migration" backend waiting "input needed" 2
start_sleep; write_session "${PIDS[1]}" "Refactor auth flow" api busy - 6
start_sleep; write_session "${PIDS[2]}" "Write release notes" docs busy - 10
start_sleep; write_session "${PIDS[3]}" "Fix flaky tests" web-app idle - 14

cat > "$WORK/actions.json" <<'JSON'
[{"id": "review", "name": "Review open PRs", "cwd": "/Users/demo/Developer/api", "prompt": "/review"}]
JSON

"$BIN" --sessions-folder "$SESSIONS" --actions-file "$WORK/actions.json" --vertical-offset 0 \
    --hover "$HOVER" --snapshot "$WORK/panel.png" --snapshot-delay 3.5 &
APP=$!

# "Write release notes" finishes a second in: busy to idle is the "just finished" moment.
sleep 1
FINISHED_PID="${PIDS[2]}"
NOW=$(now_ms)
write_session "$FINISHED_PID" "Write release notes" docs idle - 0

wait "$APP"
swift "$ROOT/docs/assets/make-hero.swift" "$WORK/panel.png" "$ROOT/docs/assets/hero.png"
