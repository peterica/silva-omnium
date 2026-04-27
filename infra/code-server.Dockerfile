# silva-omnium 용 code-server 이미지.
# 베이스 이미지에 python3 + node 20 + make 를 추가해 컨테이너 안에서
# `make ingest && make build` 가 그대로 동작하게 한다.

FROM codercom/code-server:latest

USER root

# 시스템 도구
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl gnupg \
        python3 python3-venv python3-pip \
        make git \
    && rm -rf /var/lib/apt/lists/*

# Node 22 (Astro 6 가 ≥22.12 요구; NodeSource 공식 저장소)
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# silva-omnium python deps 사전 설치 (이미지 빌드 시 한 번)
COPY scripts/requirements.txt /tmp/requirements.txt
RUN python3 -m pip install --break-system-packages --no-cache-dir -r /tmp/requirements.txt \
    && rm /tmp/requirements.txt

# Claude Code CLI — 컨테이너 안에서 직접 `claude` 명령 사용 가능.
# 인증은 첫 실행 시 ANTHROPIC_API_KEY env 또는 OAuth (브라우저 코드 페어링).
# 인증 캐시는 ~/.claude → docker-compose.yml 의 silva-claude-home volume 으로 보존.
RUN npm install -g @anthropic-ai/claude-code

# macOS 호스트 사용자 UID 501 과 일치시켜 bind mount 파일 양방향 쓰기 권한 확보.
# 베이스 이미지의 coder 사용자(UID 1000) 를 501 로 재설정하고 home 권한도 갱신.
# (debian 에서 UID 501 은 보통 비어있음 — 충돌 시 502 시도)
RUN if id -u 501 >/dev/null 2>&1; then \
        usermod -u 502 coder; \
    else \
        usermod -u 501 coder; \
    fi \
    && chown -R coder:coder /home/coder

USER coder
WORKDIR /workspace

# 베이스 이미지의 ENTRYPOINT(/usr/bin/entrypoint.sh) 와 CMD(code-server) 는 그대로 사용.
# config 는 ${HOME}/.config/code-server/config.yaml 에서 자동 로드되며, 호스트
# ~/.config/code-server 디렉토리를 컨테이너의 /home/coder/.config/code-server 로
# bind mount 한다 (docker-compose.yml).
