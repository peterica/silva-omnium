---
title: 스키마 정의
category: _meta
status: stable
---

# wiki frontmatter 스키마

모든 `wiki/**/*.md` 페이지의 프론트매터는 다음 필드를 따른다.

```yaml
---
title: string                 # 필수. 페이지 제목
aliases: [string]             # Obsidian alias + Starlight redirect 용
category: string              # _meta/categories.yaml 의 slug. 신규면 ingest 가 추가
tags: [string]
src: [string]                 # 이 페이지의 근거가 된 raw/ 경로 배열
updated: YYYY-MM-DD           # 마지막 ingest 일자 (UTC 기준)
status: draft | stable        # draft 는 사람이 검토 전, stable 은 검토 완료
---
```

## 인용 각주 형식

페이지 본문의 모든 사실 진술은 raw 출처와 각주로 연결한다.

- 각주 마커: `[^src-<raw-id>]`
- `<raw-id>`: raw 파일 상대 경로에서 `raw/` 접두어와 `.md` 접미어를 제거하고 `/` → `-` 로 치환
- 예시: `raw/2026/04-24-foo.md` → `[^src-2026-04-24-foo]`
- 정의는 페이지 하단에 `[^src-2026-04-24-foo]: raw/2026/04-24-foo.md` 형식으로 둔다

## 모순 표시

기존 페이지의 사실 진술과 충돌하는 새 raw 가 들어오면 병합 금지. 다음 callout 으로 명시한다.

```markdown
> [!conflict] raw/2026/04-24-newer.md (2026-04-24) 와 충돌
> 기존: 삼성 AX90 이 더 조용함 [^src-2026-04-20-old]
> 신규: LG OBJET 가 더 조용함 [^src-2026-04-24-newer]
```

## 카테고리 운영

- `_meta/categories.yaml` 의 카테고리는 ingest 가 자동 추가한다. emergent 분류라 의미 겹침·중복 슬러그가 생길 수 있다.
- 사용자는 주기적으로 yaml 을 직접 편집해 병합·리네이밍한다.
- 카테고리 슬러그를 바꾸면 해당 슬러그를 쓰는 페이지의 frontmatter `category:` 도 함께 수정해야 한다 (대량은 별도 스크립트).

## 예외 디렉토리

다음은 wiki 콘텐츠가 아니므로 Astro Starlight 가 무시한다.

- `wiki/_meta/**` — 메타 정의
- `wiki/.obsidian/**` — Obsidian vault 설정
- `wiki/_attachments/**` — 첨부 파일 (이미지·PDF 등)
