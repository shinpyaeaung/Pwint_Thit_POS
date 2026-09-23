# Phase 1 verification

Verified locally on 2026-09-23 (macOS ARM64).

## Completed checks

- The source specification copy matches the original byte for byte.
- `make generate`: sqlc v1.31.1 generated pgx/v5 query code successfully.
- `make check`: Go tests with race detection, `go vet`, frontend lint, strict TypeScript checking, and Vite production build pass.
- `make test-integration`: the generated query executes against real PostgreSQL successfully.
- `make dev`: starts the PostgreSQL container, Go API on port 8080, and Vite on port 5173.
- `make test-e2e`: all three Chrome tests pass against the development stack: live frontend/API/database connection, simulated outage/recovery, and mobile layout.
- Desktop (1440px) and mobile (375px) screenshots visually inspected.
- Real PostgreSQL stop/restart: readiness returns 503 while liveness remains 200; readiness returns 200 after recovery without restarting the API.
- The PostgreSQL bootstrap created the empty `app` schema.
- `.env`, dependencies, compiled binaries, and browser test artifacts are ignored by Git.

- `docker-compose up -d --build --wait`: Linux container builds completed; PostgreSQL, Go, and Nginx/frontend all report healthy.
- `E2E_BASE_URL=http://127.0.0.1:8088 make test-e2e`: all three browser tests also pass against the built container stack.

## Phase 1 boundaries (historical)

These were the boundaries at the end of Phase 1. See [Phase 2 verification](phase-2-verification.md) for the subsequently added migrations and authorization. This verifies the foundation, not a production business system. No authentication, permission enforcement, business modules, migration runner, public deployment, or production backup schedule is implemented in this phase. These remain required in their subsequent slices. No Git commit or push has been performed.
