.PHONY: setup setup-py setup-web ingest ingest-claude ingest-force dev build clean clean-all

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

ingest:
	$(PY) scripts/ingest.py

ingest-claude:
	$(PY) scripts/ingest.py --provider claude

ingest-force:
	$(PY) scripts/ingest.py --force

dev:
	cd web && npm run dev

build:
	cd web && npm run build

clean:
	rm -rf web/node_modules web/dist web/.astro

clean-all: clean
	rm -rf $(VENV)
