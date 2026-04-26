#!/usr/bin/env bash
#
# silva-omnium M1 Mac mini 1회 부트스트랩 (Docker 모드).
#
# 호스트(Mac mini): ollama·fswatch·tailscale·docker(orbstack 권장) 만 brew/cask
# 컨테이너: code-server + caddy (docker compose)
# 워처: 호스트 launchd → docker compose exec
#
# 전제: macOS Sonoma+, brew 설치됨, Xcode CLT, 인터넷.
# 실행: bash infra/install-mac-mini.sh   (repo 루트에서)
#
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
USER_NAME="$(id -un)"
HOME_DIR="$HOME"
LOG_DIR="/var/log/silva-omnium"
ENV_FILE="$REPO/infra/.env"

say() { printf '\n\033[1;32m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33mWARN: %s\033[0m\n' "$*" >&2; }
fatal() { printf '\033[1;31mFATAL: %s\033[0m\n' "$*" >&2; exit 1; }

# ---------- preflight ----------
say "1/7  preflight"
[[ "$(uname -s)" == "Darwin" ]] || fatal "macOS 만 지원"
[[ "$(uname -m)" == "arm64" ]] || warn "Apple Silicon 가정. Intel 에선 brew prefix 가 다름"
command -v brew >/dev/null || fatal "Homebrew 필요. https://brew.sh"

# ---------- brew (호스트 도구만) ----------
say "2/7  brew install (호스트 전용: fswatch, tailscale, ollama)"
brew install fswatch || true
brew install --cask tailscale || true
brew install ollama || true

# ---------- Docker 런타임 ----------
say "3/7  Docker 런타임 확인"
if command -v docker >/dev/null && docker info >/dev/null 2>&1; then
    say "    이미 docker 동작 중 — 그대로 사용"
elif command -v orbctl >/dev/null || [[ -d "/Applications/OrbStack.app" ]]; then
    say "    OrbStack 설치됨 — 시작"
    open -a OrbStack
    sleep 3
elif [[ -d "/Applications/Docker.app" ]]; then
    say "    Docker Desktop 설치됨 — 시작"
    open -a Docker
    sleep 5
else
    say "    OrbStack 설치 (8GB RAM 권장 — Docker Desktop 보다 가벼움)"
    brew install --cask orbstack
    open -a OrbStack
    say "    OrbStack 첫 실행 시 권한 다이얼로그 → 승인 후 다시 이 스크립트 재실행"
    fatal "OrbStack 첫 실행 후 다시 실행하세요"
fi

# Docker 가 응답할 때까지 잠깐 대기
for i in {1..30}; do
    docker info >/dev/null 2>&1 && break
    [[ $i -eq 30 ]] && fatal "Docker 가 응답하지 않음 (30초 초과)"
    sleep 1
done

# ---------- ollama: 호스트 외부 인터페이스 LISTEN ----------
say "4/7  ollama 외부 인터페이스 LISTEN 설정 (컨테이너에서 host.docker.internal 으로 접근 가능)"
mkdir -p "$HOME_DIR/Library/LaunchAgents"
OLLAMA_PLIST="$HOME_DIR/Library/LaunchAgents/com.silva-omnium.ollama.plist"
if [[ ! -f "$OLLAMA_PLIST" ]]; then
    cat > "$OLLAMA_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.silva-omnium.ollama</string>
    <key>ProgramArguments</key>
    <array>
        <string>/opt/homebrew/bin/ollama</string>
        <string>serve</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$LOG_DIR/ollama.log</string>
    <key>StandardErrorPath</key>
    <string>$LOG_DIR/ollama.err</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>OLLAMA_HOST</key>
        <string>0.0.0.0:11434</string>
        <key>HOME</key>
        <string>$HOME_DIR</string>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/bin:/bin</string>
    </dict>
</dict>
</plist>
EOF
    plutil -lint "$OLLAMA_PLIST" >/dev/null
    say "    ollama plist 생성"
fi

# ---------- log directory ----------
say "5/7  log directory"
sudo mkdir -p "$LOG_DIR"
sudo chown "$USER_NAME":staff "$LOG_DIR"

# ---------- .env (비밀번호 자동 생성) ----------
say "6/7  infra/.env (비밀번호 자동 생성)"
if [[ -f "$ENV_FILE" ]]; then
    warn "$ENV_FILE 이미 존재 — 보존. 비밀번호 변경하려면 파일 삭제 후 재실행"
else
    PASSWORD="$(openssl rand -base64 18 | tr -d '/+=' | head -c 24)"
    cat > "$ENV_FILE" <<EOF
SILVA_REPO=$REPO
SILVA_CODE_SERVER_PASSWORD=$PASSWORD
EOF
    chmod 600 "$ENV_FILE"
    say "    >>> code-server 비밀번호: $PASSWORD"
    say "    >>> 위 비밀번호를 비밀번호 매니저에 즉시 저장하세요."
fi

# ---------- docker compose + launchd ----------
say "7/7  docker compose up + launchd 등록"

# 1) Ollama launchd (외부 인터페이스 listen 적용)
launchctl unload "$OLLAMA_PLIST" 2>/dev/null || true
launchctl load "$OLLAMA_PLIST"

# 2) docker compose
(cd "$REPO/infra" && docker compose up -d --build)
sleep 3

# 2a) node_modules 볼륨 소유권 + Linux 바이너리 설치 (첫 실행 또는 안 되어 있을 때만)
say "    container web/node_modules 초기화 (idempotent)"
docker compose -f "$REPO/infra/docker-compose.yml" --env-file "$ENV_FILE" \
    exec -T --user root code-server chown -R coder:coder /workspace/web/node_modules || true
docker compose -f "$REPO/infra/docker-compose.yml" --env-file "$ENV_FILE" \
    exec -T code-server bash -c "cd /workspace/web && test -d node_modules/astro || npm install --silent"

# 3) Watcher launchd
WATCHER_SRC="$REPO/infra/launchd/com.silva-omnium.ingest-watcher.plist"
WATCHER_DST="$HOME_DIR/Library/LaunchAgents/com.silva-omnium.ingest-watcher.plist"
sed -e "s|__USER__|$USER_NAME|g" \
    -e "s|__HOME__|$HOME_DIR|g" \
    -e "s|__REPO__|$REPO|g" \
    "$WATCHER_SRC" > "$WATCHER_DST"
plutil -lint "$WATCHER_DST" >/dev/null
launchctl unload "$WATCHER_DST" 2>/dev/null || true
launchctl load "$WATCHER_DST"
say "    loaded watcher: $WATCHER_DST"

# 4) 첫 build (선택: wiki/ 가 비어있지 않다면 페이지 1개라도 빌드)
say "    첫 build (컨테이너 안)"
docker compose -f "$REPO/infra/docker-compose.yml" --env-file "$ENV_FILE" \
    exec -T code-server bash -c "cd /workspace && make build" || warn "build 실패 (수동 실행 권장)"

cat <<NEXT

==> 다음 단계 (수동):

1. 동작 확인 (이 머신 안에서):

      curl -s http://localhost/ | head -3       # 위키 HTML
      curl -sI http://localhost/edit/           # code-server 응답 (302 또는 200)

2. Tailscale 가입 + Funnel:

      open -a Tailscale     # GUI 로그인 (Google/GitHub)
      sudo tailscale up
      sudo tailscale serve --bg --https=443 --set-path / http://localhost:80

   출력된 https://<machine>.<tailnet>.ts.net URL 을 비밀번호 매니저에 같이 저장.

3. 외부 디바이스에서:
   - 회사 노트북·다른 사람의 디바이스: 위 URL → /edit/ 로그인 (위 비밀번호)
   - Galaxy S23: Tailscale 앱 설치 → 사설 100.x.x.x 접근

자세한 사항: $REPO/infra/tailscale-setup.md, $REPO/infra/README.md
NEXT
