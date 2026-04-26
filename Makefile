.PHONY: setup setup-py setup-web ingest ingest-claude ingest-force dev build clean clean-all

VENV := .venv
PY := $(VENV)/bin/python3

setup: setup-py setup-web

$(PY): scripts/requirements.txt
	@test -d $(VENV) || python3 -m venv $(VENV)
	$(PY) -m pip install --quiet --upgrade pip
	$(PY) -m pip install --quiet -r scripts/requirements.txt
	@touch $(PY)

setup-py: $(PY)

setup-web:
	cd web && npm install
	@test -L web/src/content/docs || (mkdir -p web/src/content && cd web/src/content && ln -s ../../../wiki docs)

ingest: $(PY)
	$(PY) scripts/ingest.py

ingest-claude: $(PY)
	$(PY) scripts/ingest.py --provider claude

ingest-force: $(PY)
	$(PY) scripts/ingest.py --force

dev:
	cd web && npm run dev

build:
	cd web && npm run build

clean:
	rm -rf web/node_modules web/dist web/.astro

clean-all: clean
	rm -rf $(VENV)
