# CLAUDE.md — silva-omnium

> Claude Code 세션 진입점.

## 프로젝트

 `raw/` 에 떨어진 원본 MD를 Claude가 읽어 `wiki/` 에 영속 위키 페이지로 종합한다.
Karpathy LLM Wiki 패턴 + `silva rerum`(사물의 숲) 전통.

## 디렉토리 규칙

| 디렉토리 | 소유 | 쓰기 권한 |
|---|---|---|
| `raw/` | 사용자 | Obsidian + 웹 편집기 (code-server). **Claude는 읽기만** |
| `wiki/` | Claude | ingest 후 생성/수정. 사용자도 편집 가능 |
| `wiki/_meta/` | 사용자+Claude | 카테고리·사이드바 정의 |
| `scripts/` | 개발자 | ingest 파이프라인 코드 |
| `web/` | 개발자 | Astro Starlight 웹 뷰 |
| `infra/` | 개발자 | 자체호스팅(M1 mini) 설정·스크립트 |

## 필수 규칙

1. **`raw/` 수정·삭제 금지** — 원본 불변. 정리·재분류는 `wiki/` 프론트매터로만. **사용자**는 Obsidian / 웹 편집기에서 raw/ 를 자유롭게 편집·생성·삭제할 수 있다 (이 규칙은 Claude/AI 에이전트에게만 적용).
2. **Read 후 Edit** — 파일 수정 전 반드시 Read.
3. **커밋 금지** — 명시적 요청 없이 `git commit` / `git push` 하지 않는다.
4. **feature 브랜치** — main 직접 작업 금지. `feat/<slug>` 또는 `ingest/<date>` 형식.
5. **인용은 raw 기반** — wiki 페이지의 사실 진술은 `[^src-<raw-id>]` 각주로 원본과 연결한다.
6. **모순 표시** — 기존 wiki 페이지와 충돌하는 사실을 발견하면 병합하지 말고 `> [!conflict]` callout으로 명시한다.

## 현황

- Phase 1 완료: ingest 파이프라인 (Ollama/Claude provider), Astro Starlight 웹 뷰, Obsidian vault, Makefile
- Phase 2 작업 중: M1 Mac mini 자체호스팅 (`infra/`)
