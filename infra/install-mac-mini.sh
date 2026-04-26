#!/usr/bin/env bash
#
# silva-omnium M1 Mac mini 1회 부트스트랩.
#
# 전제: macOS Sonoma+, 사용자 셸 zsh, 인터넷 가능, brew 설치됨.
# 실행: bash infra/install-mac-mini.sh  (repo 루트에서)
#
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
USER_NAME="$(id -un)"
HOME_DIR="$HOME"
LOG_DIR="/var/log/silva-omnium"

say() { printf '\n\033[1;32m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33mWARN: %s\033[0m\n' "$*" >&2; }
fatal() { printf '\033[1;31mFATAL: %s\033[0m\n' "$*" >&2; exit 1; }

# ---------- preflight ----------
say "1/8  preflight"
[[ "$(uname -s)" == "Darwin" ]] || fatal "macOS 만 지원"
[[ "$(uname -m)" == "arm64" ]] || warn "Apple Silicon 가정. Intel 에선 brew prefix 가 다름"
command -v brew >/dev/null || fatal "Homebrew 필요. https://brew.sh"

# ---------- brew packages ----------
say "2/8  brew install"
brew install caddy fswatch tailscale code-server node@20 python@3.12 || true

# ---------- python venv ----------
say "3/8  python venv + deps"
python3 -m venv "$REPO/.venv"
"$REPO/.venv/bin/python3" -m pip install --quiet --upgrade pip
"$REPO/.venv/bin/python3" -m pip install --quiet -r "$REPO/scripts/requirements.txt"

# ---------- node (web/) ----------
say "4/8  npm install (web)"
(cd "$REPO/web" && npm install --silent)
test -L "$REPO/web/src/content/docs" || (cd "$REPO/web/src/content" && ln -s ../../../wiki docs)

# ---------- log directory ----------
say "5/8  log directory"
sudo mkdir -p "$LOG_DIR"
sudo chown "$USER_NAME":staff "$LOG_DIR"

# ---------- secrets: code-server password ----------
say "6/8  code-server config (비밀번호 자동 생성)"
mkdir -p "$HOME_DIR/.config/code-server"
if [[ -f "$HOME_DIR/.config/code-server/config.yaml" ]]; then
    warn "$HOME_DIR/.config/code-server/config.yaml 이미 존재 — 보존"
else
    PASSWORD="$(openssl rand -base64 18 | tr -d '/+=' | head -c 24)"
    sed "s|PASSWORD_PLACEHOLDER|$PASSWORD|" \
        "$REPO/infra/code-server-config.yaml.example" \
        > "$HOME_DIR/.config/code-server/config.yaml"
    chmod 600 "$HOME_DIR/.config/code-server/config.yaml"
    say "    code-server 비밀번호 생성됨 → $HOME_DIR/.config/code-server/config.yaml"
    say "    >>> 비밀번호: $PASSWORD"
    say "    >>> 위 비밀번호를 비밀번호 매니저에 즉시 저장하세요."
fi

# ---------- Caddyfile.runtime ----------
say "7/8  Caddyfile.runtime 생성 (path 치환)"
sed "s|/Users/silva/silva-omnium|$REPO|g" \
    "$REPO/infra/Caddyfile" \
    > "$REPO/infra/Caddyfile.runtime"
caddy adapt --config "$REPO/infra/Caddyfile.runtime" --adapter caddyfile > /dev/null

# ---------- launchd plists ----------
say "8/8  launchd 등록"
mkdir -p "$HOME_DIR/Library/LaunchAgents"
for src in "$REPO"/infra/launchd/*.plist; do
    name="$(basename "$src")"
    dst="$HOME_DIR/Library/LaunchAgents/$name"
    sed -e "s|__USER__|$USER_NAME|g" \
        -e "s|__HOME__|$HOME_DIR|g" \
        -e "s|__REPO__|$REPO|g" \
        "$src" > "$dst"
    plutil -lint "$dst" >/dev/null
    launchctl unload "$dst" 2>/dev/null || true
    launchctl load "$dst"
    say "    loaded: $name"
done

cat <<NEXT

==> 다음 단계 (수동):

1. 첫 build (이미 wiki/index.md 가 있으므로 즉시 가능):

      cd "$REPO" && make build

2. Tailscale 설정:

      open -a Tailscale     # GUI 로그인 (Google/GitHub)
      sudo tailscale up

3. Funnel 활성화 (Caddy 가 :80 에서 듣고 있다고 가정):

      sudo tailscale serve --bg --https=443 --set-path / http://localhost:80

   완료되면 다음 URL 이 출력됨:
      https://<machine>.<tailnet>.ts.net

4. 같은 URL 의 /edit/ 로 들어가면 code-server 비밀번호 입력 화면.
   루트 / 는 위키.

5. 회사 노트북·Galaxy S23·외부 디바이스 모두 위 URL 로 접근 가능.
   개인 디바이스는 Tailscale 앱 로그인 후 사설 IP 로도 접근 가능.

자세한 사항: $REPO/infra/tailscale-setup.md, $REPO/infra/README.md
NEXT
