# silva-omnium 운영 첫날 회고 — 실제 ingest 한 결과 드러난 결함들

Phase 2 자체호스팅까지 끝나고 raw/ 에 실제 노트를 떨어뜨려 본 첫날. 동작 자체는 했지만 여러 결함이 드러났다. 솔직하게 기록.

## 결함 1: watcher race condition (git pull 동시 변경)

다른 머신에서 raw/ 4개 파일을 한 번에 push 했더니 mini 의 fswatch 가 동시 다발적 change 이벤트를 받음. ingest-watcher.sh 의 debounce 가 기존 sleep PID 를 kill 하는 방식인데, 이미 ingest 가 시작된 경우에도 kill 이 들어가서 ingest 도중 중단·재시작 반복.

**증상:** watcher 로그에 같은 파일이 여러 번 "pipeline start" 로 찍힘. ingest 가 부분 완료 상태로 종료되어 일부 파일 누락.

**임시 회피:** watcher 잠시 unload 후 `make ingest` 수동 실행.

**근본 fix 후보:**
- debounce 가 sleep 만 kill, 진행 중 ingest 는 wait
- 또는 ingest 에 mutex (lockfile) 도입
- 또는 fswatch 의 `--latency` 더 크게 (현재 5초 → 30초)

## 결함 2: qwen2.5:3b 가 큰 raw 파일에서 timeout

`raw/2026/04-27-Introducing-GPT-5.5.md` 같은 긴 클리핑 (수 KB) 을 ollama qwen2.5:3b 로 처리하면 5분(300초) 안에 응답 못 함. urllib timeout 으로 ingest 실패.

**원인:** 8GB RAM 환경에서 모델은 작은 걸 써야 (qwen2.5:3b = 1.9GB) 메모리 압박 없는데, 작은 모델은 긴 입력 + JSON 강제 출력에 시간이 더 걸림. 트레이드오프.

**해결:** Claude Code CLI (`claude -p`) 를 새 provider 로 추가 (`scripts/llm_providers/claude_cli.py`). 같은 파일 ~59초 처리 + 결과 품질 더 정확. 구독 OAuth 사용해 API 청구 없음. 오늘 default ingest provider 를 ollama → claude-cli 로 전환.

## 결함 3: 페이지 타이틀 중복 렌더 (frontmatter + body H1)

ingest 가 wiki/*.md 를 만들 때 frontmatter `title:` 을 넣고, 동시에 body 첫 줄에 `# 같은 제목` 도 출력. Astro Starlight 는 frontmatter title 을 페이지 H1 으로 자동 렌더하므로 화면에 H1 두 개 표시.

**fix:**
- prompt 에 "body 시작 시 H1 금지" 규칙 추가
- ingest.py 에 `strip_leading_h1()` post-processor (작은 모델이 prompt 무시할 때 방어)
- 기존 6개 wiki 파일은 sed-like 일회성 정리

## 결함 4: Starlight 기본 헤딩 사이즈 과대

H1 ~2.5rem, H2 ~2rem 등 기본값이 와이드 스크린에서 한 줄을 거의 다 차지. 위키처럼 정보 밀도 높은 페이지엔 부담.

**fix:** `web/src/styles/custom.css` 추가 → `:root` 의 `--sl-text-h1` ~ `--sl-text-h5` 변수 override (mobile/desktop 분기). astro.config.mjs 의 starlight `customCss` 옵션으로 등록.

## 결함 5: qwen2.5:3b 의 슬러그·카테고리 일관성

ingest 결과 일부 파일이 잘못된 슬러그로 배정됨:
- Memex 콘텐츠 → `wiki/concepts/idea-synthesis.md` 슬러그 (틀림)
- Tailscale Funnel 콘텐츠 → `wiki/concepts/memex.md` 슬러그 (틀림)

또한 categories.yaml 이 실제 사용된 카테고리 (invention-theories, ingest-agent, economic-research) 를 다 등록 안 함.

**원인:** 3B 모델의 instruction following 한계. 작은 모델이 schema 의 모든 제약을 일관되게 못 지킴.

**해결:** claude-cli 전환으로 자연 개선 예상. 기존 잘못 배정된 페이지는 수동 rename + frontmatter 수정 또는 `make ingest-force` 로 전부 재처리 (단 모든 raw 가 다시 처리되어 시간 비용).

## 결함 6: bind mount + 컨테이너 사용자 UID 불일치

별개 이슈이지만 셋업 단계에서 만난 것: 호스트 macOS 사용자 (UID 501) ↔ 컨테이너 coder (UID 1000) 불일치로 컨테이너에서 web/.astro, web/dist, ~/.claude 등에 쓰기 불가.

**fix:**
- Dockerfile 에서 `usermod -u 501 coder` 로 UID 일치
- 첫 실행 직후 `chown -R coder:coder /workspace/web/node_modules /home/coder/.claude` 같은 init step (install-mac-mini.sh)

## 결함 7: 첫 build 가 비치명적

install-mac-mini.sh 의 `make build` 가 `|| warn` 으로 처리되어 실패해도 설치 "성공" 으로 보임. 그 상태에서 Caddy 는 빈 dist 를 서빙해 사용자가 외부에서 404 만 받음. Codex 리뷰가 짚어 fatal 게이트로 변경.

## 회고

7개 결함 중 5개는 "실제로 raw 떨어뜨려보기 전엔 안 보였을" 종류. self-host + 실사용 단계 들어와야 비로소 드러남. Codex 리뷰 (사전) + 실사용 (사후) 두 축이 모두 필요함을 확인.

지금 default 가 claude-cli 로 바뀌었으니 앞으로의 ingest 는 결함 2·3·5 가 같이 줄어들 것으로 예상. watcher race (1) 와 카테고리 일관성 (5) 은 별도 후속 작업 후보.
