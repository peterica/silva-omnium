# silva-omnium 자체호스팅 인프라

M1 Mac mini 8GB 에 silva-omnium 을 24/7 호스팅하기 위한 설정 모음.
Docker 없는 brew + launchd 네이티브 스택.

## 구성

```
Tailscale Funnel (https://<host>.<tailnet>.ts.net)
        │
        ▼
   Caddy :80
   ├── /edit/*   →  code-server :8080  (VS Code in browser)
   └── /         →  web/dist/           (Astro 정적 위키)

   ingest-watcher (fswatch raw/) → make ingest && make build  (백그라운드)
```

모두 launchd 로 부팅 시 자동 시작 + 죽으면 재시작.

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
tail -f /var/log/silva-omnium/code-server.log
tail -f /var/log/silva-omnium/caddy.log
tail -f /var/log/silva-omnium/ingest-watcher.log
```

### 서비스 재시작

```bash
launchctl unload ~/Library/LaunchAgents/com.silva-omnium.code-server.plist
launchctl load   ~/Library/LaunchAgents/com.silva-omnium.code-server.plist
```

### 업데이트 받기

```bash
cd ~/peterica/silva-omnium
git pull
# Caddyfile / plist 가 바뀌면:
bash infra/install-mac-mini.sh
# Python deps 변경:
.venv/bin/pip install -r scripts/requirements.txt
# Astro deps 변경:
cd web && npm install && cd ..
make build
```

### 멈추기

```bash
launchctl unload ~/Library/LaunchAgents/com.silva-omnium.code-server.plist
launchctl unload ~/Library/LaunchAgents/com.silva-omnium.caddy.plist
launchctl unload ~/Library/LaunchAgents/com.silva-omnium.ingest-watcher.plist
sudo tailscale serve reset
```

## 메모리 사용 (M1 8GB 가이드)

| 프로세스 | 평시 RSS |
|---|---|
| code-server (idle) | ~250 MB |
| caddy | ~30 MB |
| ingest-watcher (fswatch + bash) | ~10 MB |
| Astro build (1회 ~5초) | ~600 MB peak |
| ollama (+ gemma4 9.6GB 추론 시) | ~9 GB peak (모델 로딩) |

→ **gemma4 동시 가동 시 swap 발생 가능.** 8GB 환경에선 작은 모델 권장:

```bash
# Phase 1 검증된 대안 (RAM ≤ 5GB)
ollama pull exaone3.5:7.8b               # 4.8 GB
ollama pull hf.co/DevQuasar/kakaocorp.kanana-1.5-8b-instruct-2505-GGUF:Q4_K_M  # 4.9 GB
ollama pull hf.co/DevQuasar/kakaocorp.kanana-1.5-2.1b-instruct-2505-GGUF:Q4_K_M  # 1.5 GB

# 모델 변경 시 ingest 명령에 --model 옵션 명시
.venv/bin/python3 scripts/ingest.py --model exaone3.5:7.8b
```

또는 ingest 시점에만 ollama serve 하고 평시엔 stop:

```bash
brew services stop ollama       # 평시
brew services start ollama      # ingest 직전
```

## 트러블슈팅

`infra/tailscale-setup.md` 의 트러블슈팅 섹션 참조.
