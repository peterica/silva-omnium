# silva-omnium 사용자 가이드

`git clone` 직후 가장 많이 받는 두 질문:

> **"왜 Docker 를 띄워야 하나요?"**
> **"제 노트가 Docker 안에 들어가는 건가요?"**

두 질문 모두 **"실은 그렇지 않다"** 가 답이지만 그 이유가 어디에도 적혀 있지 않았다. 이 문서가 그 빈자리를 채운다.

## 한 줄 결정 트리

| 상황 | 갈래 | Docker |
|---|---|---|
| 노트북 한 대에서 잠깐 써본다 | **로컬** | 불필요 |
| 항상 켜진 머신(예: Mac mini) 에 띄우고 폰·다른 노트북에서도 접속한다 | **자체호스팅** | 사용 |

로컬로 시작했다가 마음에 들면 자체호스팅으로 넘어가도 된다 (저장소째 옮기면 끝, 아래 FAQ 참고).

## 핵심 사실 3가지

오해의 90% 는 이 셋 중 하나를 모를 때 생긴다.

1. **Docker 는 선택이다.** 로컬 사용은 `make setup → make ingest → make dev` 만으로 끝. Docker 는 한 번도 등장하지 않는다.
2. **저장소는 항상 호스트에 산다.** 자체호스팅 경로에서도 `raw/`·`wiki/`·`scripts/` 는 사용자 노트북/Mac mini 의 파일시스템에 그대로 있다. Docker 컨테이너는 그것을 `/workspace` 경로로 들여다볼 뿐 (bind mount). 컨테이너를 지워도 노트는 그대로다.
3. **Docker 가 담는 건 도구 두 개뿐.** `code-server` (브라우저로 여는 VS Code) 와 `caddy` (웹서버). ollama 와 ingest-watcher 는 호스트에 네이티브로 산다.

## 갈래 A — 로컬 사용 (Docker 없음)

```
사용자 노트북
├─ raw/        ← 노트를 떨어뜨리는 곳
├─ wiki/       ← ingest 가 만들어내는 영속 위키
└─ web/        ← make dev 가 띄우는 정적 사이트
```

명령은 [README Quick start](../README.md#quick-start) 그대로:

```bash
git clone https://github.com/peterica/silva-omnium.git
cd silva-omnium
make setup

mkdir -p raw/2026
echo "# 첫 노트" > raw/2026/test.md

make ingest && make build && make dev
# → http://localhost:4321
```

끝나면 종료. 다음에 또 쓰려면 같은 명령 반복.

### 언제 답답해지나

다음 셋 중 하나라도 필요해지면 **갈래 B** 로:

- 노트북을 꺼두면 위키가 떠 있지 않다 — 24/7 접근 불가
- 폰이나 다른 노트북에서 같은 위키를 보고 싶다
- `raw/` 에 노트만 떨어뜨리면 알아서 ingest 되길 바란다 (자동화)

## 갈래 B — 자체호스팅 (Docker 등장)

### 호스트 / Docker 경계

```
┌─ 호스트 (M1 Mac mini, 항상 켜져 있음) ───────────────────┐
│                                                          │
│   📁 silva-omnium/        ← 저장소는 여기 산다           │
│      raw/  wiki/  scripts/  web/  ...                    │
│                                                          │
│   🟢 ollama (brew, native)                               │
│   🟢 ingest-watcher (launchd, native)                    │
│                                                          │
│   ┌─ Docker ────────────────────────────────────────┐    │
│   │  📦 code-server  ← /workspace 로 위 저장소 mount │    │
│   │  📦 caddy        ← web/dist 를 :80 으로 서빙     │    │
│   └─────────────────────────────────────────────────┘    │
│                                                          │
└──────────────────────────────────────────────────────────┘
        ▲
        │ Tailscale Funnel (외부 디바이스가 같은 URL 로 접근)
```

핵심을 다시: **Docker 박스 안에 `raw/` 가 없다.** 박스 *바깥*에 있는 저장소를 박스 *안*에서 들여다보는 구조다. `docker compose down` 해도 호스트의 노트는 한 줄도 사라지지 않는다.

### 왜 Docker 를 쓰나

세 가지 이유:

1. **brew 의존 격리** — code-server 가 깔리려면 Node·Python·시스템 패키지가 같이 와야 한다. Mac mini 에 다른 프로젝트도 함께 살고 있다면 brew 버전이 충돌한다. Docker 가 도구 일체를 한 박스에 가둔다 (구체는 `infra/code-server.Dockerfile`).
2. **재시작·재현 가능성** — 컨테이너는 `docker compose up -d` 한 줄로 정확히 같은 환경이 다시 뜬다. 호스트 OS 가 업데이트돼도, 다른 머신에서 다시 깔아도 동일.
3. **자동 시작** — `restart: unless-stopped` 로 Mac mini 가 재부팅돼도 컨테이너가 알아서 올라온다. launchd 등록 같은 호스트 설정이 따로 필요 없다.

### 왜 ollama 와 watcher 는 Docker 가 아닌가

같은 박스에 다 넣지 않은 이유:

- **ollama** — Apple Silicon GPU 가속을 쓰려면 컨테이너 밖에 있어야 한다. 컨테이너 안의 ollama 는 CPU only 라 느리다.
- **ingest-watcher (fswatch)** — 호스트의 `raw/` 변경을 감지하려면 호스트 launchd 에 등록되는 게 가장 단순하다. 컨테이너 안에서 호스트 파일시스템 이벤트를 보는 건 우회로가 많이 필요하다.

### 셋업

1회 부트스트랩(`bash infra/install-mac-mini.sh`) 과 평소 운영(`docker compose logs/restart/down`) 은 [`infra/README.md`](../infra/README.md) 에 자세히 있다. 이 가이드는 멘탈 모델까지만.

## FAQ

**Q. Docker 를 지우면 내 노트가 날아가나?**
A. 아니다. `raw/`·`wiki/` 는 호스트 파일시스템에 산다. 컨테이너 삭제 → 도구만 사라짐. `docker compose down -v` 도 마찬가지 (volume 은 node_modules·caddy 캐시·claude 인증 캐시 같은 빌드/세션 캐시일 뿐).

**Q. 컨테이너 안에서 `raw/` 에 파일을 넣어야 하나?**
A. 아니다. 호스트 파일시스템에 넣으면 된다. 브라우저로 code-server 를 열고 통합 에디터에서 편집해도 결국 같은 호스트 파일을 보는 것이다 (bind mount 가 양방향).

**Q. 로컬에서 만든 위키를 자체호스팅으로 옮기려면?**
A. 저장소째 Mac mini 로 옮기면 끝. `git push` 후 mini 에서 `git pull` (혹은 처음이라면 `git clone`). Docker 와 무관.

**Q. Docker 를 꼭 써야 자체호스팅이 되나?**
A. 아니다. code-server·Caddy 를 brew 로 깔아 호스트에서 직접 돌려도 동작한다. Docker 는 "Mac mini 에 다른 프로젝트가 함께 살아도 충돌이 적은 길" 일 뿐. 현재 `infra/` 의 가이드는 Docker 경로만 다룬다 — 호스트 직접 설치 경로는 사용자가 직접 적용해야 한다.

**Q. 컨테이너 안 `claude` CLI 의 인증은 컨테이너 재빌드 시 날아가나?**
A. 아니다. `silva-claude-home` named volume 으로 `/home/coder/.claude` 가 보존된다 (`infra/docker-compose.yml:27`).

## 다음 단계

- 로컬 갈래면 충분하다 → [README Quick start](../README.md#quick-start)
- 자체호스팅으로 간다 → [`infra/README.md`](../infra/README.md) 의 1회 셋업
- 설계 배경·동기가 궁금하다 → [`task/blog/silva-omnium-소개.md`](../task/blog/silva-omnium-소개.md)
- 협업 규칙 (raw/ 불변, 인용 강제, 모순 callout) → [`CLAUDE.md`](../CLAUDE.md)
