#!/usr/bin/env bash
#
# silva-omnium ingest watcher
#
# raw/ 또는 wiki/_meta 변경 시 디바운스 후 docker compose exec 로
# code-server 컨테이너 안에서 make ingest && make build 실행.
# 호스트 fswatch 사용 (Docker bind mount 위 fswatch 의 macOS 신뢰성 이슈 회피).
# launchd 가 호출하며 SILVA_REPO 환경변수를 주입한다.
#
set -euo pipefail

REPO="${SILVA_REPO:-${HOME}/silva-omnium}"
DEBOUNCE_SECONDS="${SILVA_DEBOUNCE:-5}"
LOG="${SILVA_LOG:-${HOME}/Library/Logs/silva-omnium/ingest-watcher.log}"
COMPOSE_FILE="$REPO/infra/docker-compose.yml"
ENV_FILE="$REPO/infra/.env"

mkdir -p "$(dirname "$LOG")"

log() {
    printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*" >> "$LOG"
}

run_pipeline() {
    log "pipeline start"
    if docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" exec -T code-server \
            bash -c "cd /workspace && make ingest && make build" >> "$LOG" 2>&1; then
        log "pipeline ok"
    else
        log "pipeline FAILED (exit $?)"
    fi
}

if ! command -v fswatch >/dev/null; then
    log "FATAL: fswatch not installed. brew install fswatch"
    exit 1
fi
if ! command -v docker >/dev/null; then
    log "FATAL: docker not installed (brew install --cask docker 또는 orbstack)"
    exit 1
fi
if [[ ! -f "$ENV_FILE" ]]; then
    log "FATAL: env file 없음: $ENV_FILE (install-mac-mini.sh 가 생성)"
    exit 1
fi

log "watcher starting on $REPO/raw → docker compose exec code-server"

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
