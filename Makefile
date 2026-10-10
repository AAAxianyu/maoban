SHELL := /bin/bash
ROOT := $(CURDIR)
FLUTTER := $(ROOT)/.tools/flutter/bin/flutter
API_PYTHON := $(ROOT)/services/api/.venv/bin/python
UV := $(ROOT)/.venv/bin/uv
NOTIFICATIONS_ALLOWED ?= false
COMPOSE := docker compose --env-file .env -f infra/compose.yaml

.PHONY: doctor setup dev-up migrate seed-demo test-backend test-mobile test-e2e test-cloud-connectivity verify build-android build-ios
doctor:
	bash scripts/doctor.sh
setup:
	python3 scripts/setup.py
	python3 -m venv .venv
	.venv/bin/pip install 'uv==0.12.23'
	$(UV) sync --project services/api --frozen
	cd apps/mobile && $(FLUTTER) pub get --enforce-lockfile
dev-up:
	$(COMPOSE) up -d --wait db
	$(COMPOSE) build api worker
	$(COMPOSE) run --rm api alembic upgrade head
	$(COMPOSE) up -d --wait api worker
migrate:
	$(COMPOSE) run --rm api alembic upgrade head
seed-demo:
	$(COMPOSE) run --rm api python -m app.seed_demo
test-backend:
	docker compose -f infra/compose.test.yaml up -d --wait
	cd services/api && ENVIRONMENT=test DATABASE_URL=postgresql+psycopg://miaoban_test:isolated-test-only@127.0.0.1:55433/miaoban_test .venv/bin/alembic upgrade head
	cd services/api && .venv/bin/ruff check app tests && .venv/bin/pytest
test-mobile:
	cd apps/mobile && $(FLUTTER) analyze && $(FLUTTER) test
test-e2e:
	@test -n "$(DEVICE)" -a -n "$(API_BASE_URL)" || (echo '必须设置 DEVICE 与隔离测试 API_BASE_URL'; exit 1)
	cd apps/mobile && $(FLUTTER) test integration_test/core_flow_test.dart -d '$(DEVICE)' --dart-define=API_BASE_URL='$(API_BASE_URL)' --dart-define=NOTIFICATIONS_ALLOWED='$(NOTIFICATIONS_ALLOWED)'
test-cloud-connectivity:
	@test -n "$(DEVICE)" || (echo '必须设置测试 DEVICE'; exit 1)
	@case '$(API_BASE_URL)' in https://*) ;; *) echo '必须设置 HTTPS API_BASE_URL'; exit 1 ;; esac
	cd apps/mobile && $(FLUTTER) test integration_test/deployment_connectivity_test.dart -d '$(DEVICE)' --dart-define=API_BASE_URL='$(API_BASE_URL)'
verify: test-backend test-mobile
build-android:
	@test -n "$(API_BASE_URL)" || (echo '必须设置 HTTPS API_BASE_URL'; exit 1)
	@test -f apps/mobile/android/key.properties || (echo '缺少用户 Android 签名配置 key.properties'; exit 1)
	cd apps/mobile && $(FLUTTER) build apk --release --dart-define=API_BASE_URL='$(API_BASE_URL)'
build-ios:
	@test -n "$(API_BASE_URL)" || (echo '必须设置 HTTPS API_BASE_URL'; exit 1)
	cd apps/mobile && $(FLUTTER) build ipa --dart-define=API_BASE_URL='$(API_BASE_URL)'
