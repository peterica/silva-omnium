# Ollama 모델 선택 — 8GB RAM 환경에서

silva-omnium ingest 가 ollama 를 호출. 어떤 모델을 쓸지가 처음 막히는 지점.

## 시도해 본 모델들

| 모델 | 디스크 | RAM 사용 | 첫 추론 시간 (8GB mini) | JSON 따름 정도 |
|---|---|---|---|---|
| `gemma4:e4b-it-q4_K_M` | 9.6 GB | ~9 GB peak | 매우 느림 (swap 발생) | 좋음 |
| `exaone3.5:7.8b` | 4.8 GB | ~5 GB | 60-300초+ (timeout 위험) | 좋음 |
| `mistral:latest` | 4.4 GB | ~5 GB | 60초 내외 | 보통 |
| **`qwen2.5:3b`** | **1.9 GB** | **~2.5 GB** | **20-30초** | **좋음** |
| `kanana-1.5-2.1b` | 1.5 GB | ~2 GB | ~15초 | 보통 |

## 발견

- **8GB RAM** 환경에선 4GB+ 모델은 swap 빈번 → 체감 매우 느림
- ollama 는 모델을 mmap 로 로드 — 첫 호출이 가장 느리고 이후 캐시
- 다른 무거운 프로세스 (Docker VM, 브라우저, IDE) 가 같이 떠 있으면 swap 더 심함

## 결론 (8GB 기준)

- **qwen2.5:3b 를 기본으로 쓰자** — 속도·품질 밸런스 좋고 JSON 강제도 잘 따름
- 주말 등 다른 프로세스 적을 때만 7B+ 모델 시도
- ingest 직전에만 ollama serve, 평시 stop 하면 RAM 압박 줄음

## 16GB+ 환경이라면

- exaone3.5:7.8b 또는 kanana 8b 가 카테고리 분류·요약 품질 더 좋음
- gemma4 도 swap 없이 가동 가능

## frontmatter 예시 (qwen2.5:3b 결과)

```yaml
---
title: ...
category: infra
tags: [tailscale, vpn, hosting]
description: ...
---
```

다국어 (한/영) 혼재 입력에도 카테고리·태그를 영문 slug 로 잘 뽑아냄.
