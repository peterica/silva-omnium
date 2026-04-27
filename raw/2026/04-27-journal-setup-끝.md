# 2026-04-27 일지 — silva-omnium 셋업 마무리

이틀에 걸쳐 silva-omnium Phase 1, 2 를 끝냈다. 짧은 회고.

## 무엇을 했나

- Phase 1: raw → wiki ingest 파이프라인 + Astro Starlight 정적 사이트 + Obsidian vault
- Phase 2: M1 Mac mini 에 Docker 로 자체호스팅. code-server 웹 편집기 + Caddy + Tailscale Funnel 외부 접근
- 보너스: 컨테이너 안에 Claude Code CLI 사전 설치

## 잘 된 것

- ingest 파이프라인이 처음 돌렸을 때부터 동작 — provider 추상화 (Ollama / Claude) 가 깔끔
- code-server 가 생각보다 가볍다. 8GB mini 에서도 충분히 돌아감
- Tailscale Funnel 이 정말 5분 셋업. 도메인 살 필요 없음

## 발목 잡힌 것

- macOS 26 (Tahoe) 에서 colima 0.6.x 가 user-v2 네트워크 못 띄움 → 0.10.x 로 업그레이드해야 했음
- 컨테이너 coder UID(1000) ↔ macOS host UID(501) 불일치로 bind mount 쓰기 권한 막힘 → Dockerfile 에서 usermod 로 해결
- Astro 6 가 Node 22.12+ 요구 → NodeSource setup_22 로 명시
- 8GB RAM 환경에선 ollama gemma4 는 무리. qwen2.5:3b 로 정착

## 배운 것

- "최대한 호스트 의존성 줄이기" 가 sibling 프로젝트들과 격리에 큰 도움
- ollama 는 호스트 native, 나머지는 컨테이너 — 이 구조가 8GB 에서 균형 잘 잡음
- Tailscale Funnel + 비밀번호 만으로는 약함. 다음 단계는 Caddy basic_auth 추가

## 다음

- 1-2주 실사용 → 실제 ingest 패턴·실패 케이스 관찰
- 백로그: Funnel 인증 강화, ollama 11434 외부 차단, Makefile 호스트 가드
- 블로그 시리즈 #1-4 초안

## 기분

피곤하지만 만족. 작은 도구라도 직접 쌓아 올린 인프라가 동작하는 걸 보면 좋다.
