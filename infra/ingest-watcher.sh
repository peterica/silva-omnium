#!/usr/bin/env bash
#
# silva-omnium ingest watcher
#
# raw/ 변경 시 디바운스 후 make ingest && make build 실행.
# launchd 가 호출하며 SILVA_REPO 환경변수를 주입한다.
#
set -euo pipefail

REPO="${SILVA_REPO:-${HOME}/silva-omnium}"
DEBOUNCE_SECONDS="${SILVA_DEBOUNCE:-5}"
LOG="${SILVA_LOG:-/var/log/silva-omnium/ingest-watcher.log}"

mkdir -p "$(dirname "$LOG")"

log() {
    printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*" >> "$LOG"
}

run_pipeline() {
    log "pipeline start"
    if (cd "$REPO" && make ingest && make build) >> "$LOG" 2>&1; then
        log "pipeline ok"
    else
        log "pipeline FAILED (exit $?)"
    fi
}

if ! command -v fswatch >/dev/null; then
    log "FATAL: fswatch not installed. brew install fswatch"
    exit 1
fi

log "watcher starting on $REPO/raw"

# fswatch 가 변경을 보내면 debounce_pid 를 기록하고, 새 변경이 들어오면
# 기존 sleep 을 죽인 뒤 새로 잠재운다. sleep 이 끝나야 run_pipeline 이 호출된다.
debounce_pid=""

fswatch -o "$REPO/raw" "$REPO/wiki/_meta" | while read -r _; do
    log "change detected"
    if [[ -n "$debounce_pid" ]] && kill -0 "$debounce_pid" 2>/dev/null; then
        kill "$debounce_pid" 2>/dev/null || true
    fi
    (
        sleep "$DEBOUNCE_SECONDS"
        run_pipeline
    ) &
    debounce_pid=$!
done
