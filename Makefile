.PHONY: setup setup-py setup-web ingest ingest-claude ingest-claude-cli ingest-ollama ingest-force dev build clean clean-all

VENV := .venv
# venv 의 python3 가 실제로 실행 가능하면 그것, 아니면 system python3 (= Docker
# 컨테이너 — 호스트 .venv 가 마운트돼도 컨테이너 내부에선 깨진 심볼릭 링크).
PY := $(shell test -x $(VENV)/bin/python3 && echo $(VENV)/bin/python3 || echo python3)

setup: setup-py setup-web

setup-py:
	@test -d $(VENV) || python3 -m venv $(VENV)
	$(VENV)/bin/python3 -m pip install --quiet --upgrade pip
	$(VENV)/bin/python3 -m pip install --quiet -r scripts/requirements.txt

setup-web:
	cd web && npm install
	@test -L web/src/content/docs || (mkdir -p web/src/content && cd web/src/content && ln -s ../../../wiki docs)

# 기본 ingest = claude-cli (구독 OAuth, 추가 청구 없음, 품질 ↑).
# watcher 도 이 타겟을 호출하므로 자동 ingest 도 같이 전환됨.
ingest:
	$(PY) scripts/ingest.py --provider claude-cli

# Anthropic API key 직접 사용 (per-token 청구)
ingest-claude:
	$(PY) scripts/ingest.py --provider claude

# 명시적 claude-cli (default 와 동일 — 명확성용)
ingest-claude-cli:
	$(PY) scripts/ingest.py --provider claude-cli

# 로컬 ollama (오프라인·빠른 실험용)
ingest-ollama:
	$(PY) scripts/ingest.py --provider ollama

ingest-force:
	$(PY) scripts/ingest.py --force --provider claude-cli

dev:
	cd web && npm run dev

build:
	cd web && npm run build

clean:
	rm -rf web/node_modules web/dist web/.astro

clean-all: clean
	rm -rf $(VENV)
