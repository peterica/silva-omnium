.PHONY: setup setup-py setup-web ingest ingest-claude ingest-force dev build clean clean-all

VENV := .venv
# venv 가 있으면 venv 의 python3, 없으면 system python3 (= Docker 컨테이너).
PY := $(if $(wildcard $(VENV)/bin/python3),$(VENV)/bin/python3,python3)

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
