# silva-omnium

> "나만의 숲" — 모든 것이 쌓이는 개인 지식 숲.

LLM으로 문서를 다루는 대부분의 방식은 질문할 때마다 지식을 처음부터 재발견합니다. 같은 문서에 10번 질문하면 → 10번 재발견.

**silva-omnium은 이걸 뒤집습니다.** 소스는 한 번만 넣으면 됩니다. Claude가 읽고, 영속 위키에 통합하고, 기존 페이지와의 모순을 표시하고, 인용을 연결하고, 커밋합니다. 10번째 질문 즈음이면 위키가 이미 종합을 마친 상태입니다.

## 계보

- [Andrej Karpathy의 LLM Wiki 패턴](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f)

## 구조

```
silva-omnium/
├─ raw/              원본 소스. 불변. Obsidian에서 여기로만 저장.
├─ wiki/             Claude가 관리하는 페이지. Obsidian vault 루트.
│  └─ _meta/         카테고리·사이드바 정의
└─ scripts/          ingest 파이프라인 (예정)
```

## 흐름

```
raw/ ──(make ingest)──▶ wiki/ ──▶ [Astro Starlight 웹] + [Obsidian 그래프]
```

- **사람**: 소스 큐레이션, 질문, 분석 방향 결정
- **Claude**: 요약, 교차참조, 인용, 모순 탐지, 파일 정리
- **위키**: 쌓입니다

## 자체호스팅 (선택)

M1 Mac mini 등 상시 머신에서 silva-omnium 을 호스팅하면 어디서든 웹 브라우저로 편집·열람할 수 있다.

- 웹 편집기: code-server (VS Code in browser) — 트리·에디터·미리보기·파일 ops
- 정적 사이트: Astro Starlight `dist/` 를 Caddy 가 서빙
- 자동 ingest: `raw/` 변경 시 fswatch 가 `make ingest && make build` 자동 실행
- 외부 접근: Tailscale Funnel — 공개 URL, 클라이언트 설치 불필요

셋업: `infra/README.md` 참조.

## 상태

- Phase 1 (ingest + Astro 빌드 + Obsidian vault + Makefile): 완료
- Phase 2 (M1 mini 자체호스팅): 진행 중
