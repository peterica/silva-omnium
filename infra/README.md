# silva-omnium 자체호스팅 인프라

M1 Mac mini 8GB 에 silva-omnium 을 24/7 호스팅하기 위한 설정 모음.
**호스트는 ollama·watcher 만, 나머지는 Docker** — sibling 프로젝트와 brew 의존 격리.

## 구성

```
호스트 (M1 Mac mini, peterseo)
├── ollama (brew, launchd, OLLAMA_HOST=0.0.0.0:11434)
├── tailscale (brew cask, GUI + CLI)
└── ingest-watcher (launchd, fswatch raw/ → docker compose exec)
                                    │
                                    ▼
        ┌─── docker compose (silva-omnium 네트워크) ───┐
        │                                              │
   silva-caddy (caddy:2-alpine, host:80)        silva-code-server
        │                                              │
        ├── /edit/*  → reverse_proxy ────────────────► :8080 (VS Code in browser)
        └── /        → file_server /srv (= web/dist 마운트)
                                                       │
                                                       └── host.docker.internal:11434 → ollama
                                                       (workspace = host /Users/peterseo/.../silva-omnium)
```

Tailscale Funnel 이 호스트 :443 → :80 (Caddy 컨테이너) 로 라우팅, 외부 디바이스(회사 노트북, Galaxy S23 등)가 같은 URL 로 접근.

## 1회 셋업 (M1 mini 에서)

```bash
# 1. repo clone
git clone https://github.com/peterica/silva-omnium.git ~/peterica/silva-omnium
cd ~/peterica/silva-omnium

# 2. brew 가 깔려 있다면 ↓ 한 줄로 끝
bash infra/install-mac-mini.sh
```

스크립트가 출력하는 비밀번호를 비밀번호 매니저에 즉시 저장.

## 그 다음 (Tailscale)

`infra/tailscale-setup.md` 참조.

## 평소 운영

### 로그 확인

```bash
# 컨테이너 로그 (real-time)
cd ~/peterica/silva-omnium/infra
docker compose logs -f code-server
docker compose logs -f caddy

# 호스트 로그 (watcher / ollama)
tail -f ~/Library/Logs/silva-omnium/ingest-watcher.log
tail -f ~/Library/Logs/silva-omnium/ollama.log
```

### 컨테이너 재시작

```bash
cd ~/peterica/silva-omnium/infra
docker compose restart code-server     # 또는 caddy
```

### 업데이트 받기

```bash
cd ~/peterica/silva-omnium
git pull

# 컨테이너 이미지 / 호스트 도구 변경이면:
bash infra/install-mac-mini.sh         # 멱등 (.env, password 보존, 첫 build 까지)

# Dockerfile 만 바뀐 경우:
cd infra && docker compose up -d --build
docker compose --env-file .env exec -T code-server bash -c "cd /workspace && make build"
```

> **중요**: `git pull` 만으로는 `web/dist` 가 갱신되지 않는다. Watcher 는 `raw/` 와
> `wiki/_meta` 변경만 감지하므로, `web/`·테마·Astro 설정 등이 바뀌면 위처럼
> 명시적 build 필요. 안 그러면 위키가 stale 한 상태로 보임. (Codex 리뷰 P2#7)

### 멈추기

```bash
# 컨테이너만:
cd ~/peterica/silva-omnium/infra
docker compose down

# 워처도:
launchctl unload ~/Library/LaunchAgents/com.silva-omnium.ingest-watcher.plist

# Tailscale 외부 노출 끄기:
sudo tailscale serve reset
```

### 완전 정리 (재시작 시 자동 시작도 막기)

```bash
launchctl unload ~/Library/LaunchAgents/com.silva-omnium.*.plist
rm ~/Library/LaunchAgents/com.silva-omnium.*.plist
cd ~/peterica/silva-omnium/infra && docker compose down -v
```

## 메모리 사용 (M1 8GB 가이드)

| 프로세스 | 평시 RSS |
|---|---|
| Docker (OrbStack VM) | ~800 MB |
| caddy 컨테이너 | ~30 MB |
| code-server 컨테이너 (idle) | ~250 MB |
| ingest-watcher (호스트, fswatch+bash) | ~10 MB |
| Astro build (컨테이너 안, 1회 ~5초) | ~600 MB peak |
| ollama (호스트) + gemma4 9.6GB 추론 시 | ~9 GB peak (모델 로딩) |

→ **gemma4 동시 가동 시 swap 발생 가능.** 8GB 환경에선 작은 모델 권장:

```bash
# 호스트에서:
ollama pull exaone3.5:7.8b               # 4.8 GB
ollama pull hf.co/DevQuasar/kakaocorp.kanana-1.5-2.1b-instruct-2505-GGUF:Q4_K_M  # 1.5 GB

# infra/.env 에 OLLAMA_MODEL 추가:
echo 'OLLAMA_MODEL=exaone3.5:7.8b' >> infra/.env
cd infra && docker compose up -d         # 재기동으로 적용
```

또는 ingest 시점에만 ollama serve, 평시 stop:

```bash
launchctl unload ~/Library/LaunchAgents/com.silva-omnium.ollama.plist     # 평시
launchctl load ~/Library/LaunchAgents/com.silva-omnium.ollama.plist       # ingest 직전
```

## Claude Code in container

이미지에 `@anthropic-ai/claude-code` 사전 설치돼 있음. code-server 통합 터미널에서 바로:

```bash
claude        # 첫 실행 시 인증 (브라우저 코드 또는 ANTHROPIC_API_KEY env)
```

인증 캐시는 named volume `silva-claude-home` 에 보존돼 컨테이너 재빌드해도 휘발 안 됨.

API key 방식 사용 시 `infra/.env` 에 추가:

```
ANTHROPIC_API_KEY=sk-ant-...
```

후 `cd infra && docker compose --env-file .env up -d` 로 재기동. compose 가 자동으로 컨테이너에 주입.

이 워크플로우의 가치: 회사 노트북 브라우저에서 code-server 열고 → 통합 터미널 → `claude` → 모든 git push·AI 호출이 mini 의 네트워크에서 발생.

## 트러블슈팅

`infra/tailscale-setup.md` 트러블슈팅 섹션 참조. 추가 항목:

- **컨테이너에서 ollama 못 찾음** (`host.docker.internal: name resolution failed`):
  - install 스크립트가 ollama plist 를 등록했는지 확인: `launchctl list | grep ollama`
  - `lsof -nP -iTCP:11434 -sTCP:LISTEN` — `*:11434` 표시 필요 (127.0.0.1 만이면 OLLAMA_HOST=0.0.0.0 적용 안 됨)
  - 컨테이너 안에서: `docker compose exec code-server curl -s http://host.docker.internal:11434/api/version`
- **Docker compose 가 SILVA_REPO 못 읽음**:
  - `infra/.env` 존재 + 경로 절대 경로인지 확인
  - 명시적: `docker compose --env-file ../.env up`
- **Watcher 가 동작 안 함**:
  - `tail -f ~/Library/Logs/silva-omnium/ingest-watcher.log` — `FATAL: docker not installed` 등 표시
  - launchctl: `launchctl list com.silva-omnium.ingest-watcher`
