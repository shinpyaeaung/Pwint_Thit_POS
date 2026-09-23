COMPOSE := $(shell if docker compose version >/dev/null 2>&1; then echo "docker compose"; else echo "docker-compose"; fi)
SQLC_VERSION := v1.31.1

.PHONY: setup dev db-up db-stop backend frontend generate check test-integration test-e2e up down migrate create-admin
setup:
	@test -f .env || cp .env.example .env
	pnpm --dir frontend install --frozen-lockfile
	cd backend && go mod download

db-up:
	$(COMPOSE) up -d --wait postgres

db-stop:
	$(COMPOSE) stop postgres

migrate:
	cd backend && go run ./cmd/migrate

dev: db-up migrate
	node scripts/dev.mjs

backend: migrate
	cd backend && go run ./cmd/api

frontend:
	pnpm --dir frontend run dev

generate:
	cd backend && go run github.com/sqlc-dev/sqlc/cmd/sqlc@$(SQLC_VERSION) generate -f ../sqlc.yaml

check:
	cd backend && go test -race ./... && go vet ./...
	pnpm --dir frontend run lint
	pnpm --dir frontend run build

test-integration:
	node scripts/integration.mjs

test-e2e:
	RUN_BROWSER_TESTS=1 node scripts/integration.mjs

up:
	$(COMPOSE) up -d --build --wait

down:
	$(COMPOSE) down

create-admin: migrate
	cd backend && go run ./cmd/create-admin
