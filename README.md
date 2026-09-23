# Pwint Thit Distribution

Phases 1–6 provide the foundation, PostgreSQL schema, authentication, configurable Staff Admin permissions, reusable frontend design system, and the complete product and supplier modules. Further business modules follow as vertical slices. See [authentication](docs/authentication.md) for setup and access rules. See [database design](docs/database-design.md) for the schema and its enforcement boundaries.
The complete [system specification](docs/Pwint_Thit_Distribution_Overall_System_Specification.md) is the source of truth; the user's current phase scope takes precedence over its suggested phase grouping.

## Requirements

- Node.js 24+, pnpm 12.3.4, Go 1.27.1+, and Make
- Docker with Compose (Docker Desktop or Colima on macOS)
- Google Chrome for the browser tests

On this Mac, Docker CLI and Compose were installed with Homebrew, and Colima provides the Docker engine. Start it with `colima start` if stopped. The Makefile supports both `docker compose` and Homebrew's standalone `docker-compose`.

## Local development

Use pnpm for all frontend commands. The version is pinned in `frontend/package.json`; `frontend/pnpm-lock.yaml` is the dependency lockfile. With Corepack installed, enable pnpm using `corepack enable pnpm`. The frontend pnpm configuration includes user-approved release-age exceptions for the existing tested `framer-motion@13.4.1` and `motion-dom@13.4.1` versions only; other dependencies retain the default policy.

From the repository root:

```sh
make setup
make dev
```

`make setup` creates `.env` from `.env.example` if needed and installs dependencies. `make dev` starts PostgreSQL, applies pending database migrations, compiles the Go API, and starts the API and Vite together. Ctrl+C stops both application processes; PostgreSQL retains its data. Restart `make dev` after Go source changes; Vite reloads frontend changes automatically.

- Frontend: http://127.0.0.1:5173
- API readiness: http://127.0.0.1:8080/api/v1/health
- API liveness: http://127.0.0.1:8080/api/v1/health/live
- PostgreSQL: `127.0.0.1:5432` (credentials in local `.env`)

Alternatively, run `make db-up`, `make backend`, and `make frontend` in separate terminals.

The browser uses same-origin `/api/v1` requests. Vite proxies them to Go during development; Nginx proxies them in Docker. Database credentials never enter the browser bundle. `API_PROXY_TARGET` is server-side Vite configuration, not a `VITE_` variable. Keep secrets out of all `VITE_` variables.

## Run the container stack

```sh
make setup
make up
```

Open http://127.0.0.1:8088. This builds the frontend, serves it through Nginx, and runs migrations before starting Go, with health checks for all long-running services. `make down` stops the stack without deleting the database volume. `make db-stop` stops only PostgreSQL.

These are local deployment foundations. Before a Linux VPS launch, configure a domain and HTTPS, separate production credentials, restricted database access, backups/restore, and operational monitoring. Nothing has been deployed publicly. Database and web ports bind to loopback by default. The sample password is development-only. Use URL-safe database passwords in Compose's interpolated URL, or provide a correctly percent-encoded connection URL when customizing it. Changing database credentials requires updating the existing database role as well as configuration; initialization environment variables only affect a new volume.

## Verification

```sh
make check             # Go tests with race detection, go vet, frontend lint and build
make test-integration  # Real pgx/sqlc query against running PostgreSQL
make test-e2e          # Isolated real API/database + Chrome authentication tests
```

The browser suite creates a disposable database, starts isolated Go/Vite servers, seeds test-only users, and removes them afterward. It verifies login, logout, session restoration, denied access, permission grants/revocations, health recovery, and mobile width. Both integration suites require running PostgreSQL and a configured database URL with CREATEDB access. Plain `go test` skips database/browser integration unless explicitly configured.

## Structure

```text
frontend/   React, Vite, TypeScript, Tailwind, shadcn/ui, Framer Motion,
            TanStack Query for server data, Zustand for small UI state
backend/    Go, Gin, environment validation, pgx pool, structured logs,
            graceful shutdown, JSON errors, request IDs, health routes
database/  Versioned migrations, sqlc queries, and test fixtures
docs/      Complete specification, scope, verification notes
docker/    Multi-stage builds and Nginx reverse proxy
scripts/   Local process runner and database integration test runner
```

## Database and code generation

SQL lives in `database/queries` and `database/migrations`. Apply pending migrations with `make migrate` after starting PostgreSQL. The Docker stack runs its migration service before starting the API. Regenerate checked-in Go code with:

```sh
make generate
```

This uses sqlc v1.31.1 and pgx/v5. Migrations are ordered, checksummed, and applied transactionally under a database advisory lock. Rerunning is safe; editing an applied file is rejected. Add a new numbered migration for every subsequent change. There is no destructive automatic down/reset command; correct deployed schemas with a new migration and retain tested backups for recovery.

The original Phase 1 empty `app` schema upgrades in place. Do not delete the database volume. The integration suite creates disposable databases on the configured server and requires `CREATEDB`; it does not reset the application database. Use a dedicated development/test PostgreSQL server for tests.

## First login

Start PostgreSQL, then run `make create-admin` in your terminal. Enter a password of at least 12 characters when prompted. The initial username is `admin`; no default password is supplied. The command refuses to create another bootstrap account once a Super Admin exists.

Open `/login` at the development or Docker frontend URL. Super Admin can create staff and assign permissions through **Users & access**. See [authentication setup and API](docs/authentication.md).

## Product catalog

Use **Products** for product creation, packaging conversions, search, filters, editing and archiving. **Catalog setup** manages categories, brands and unit definitions. See the [product module guide](docs/products.md) for permissions, API contracts, and integrity rules.

## Suppliers

Use **Suppliers** to maintain contacts, country, payment terms and notes, and view permission-controlled purchase history. See the [supplier guide](docs/suppliers.md) for archive behavior, permissions and API contracts.

## Frontend design system

See the [component guide](docs/design-system.md) for reusable layouts, tables, dialogs, forms, and exact-value inputs. Super Admin can open **UI library** in the sidebar for interactive previews. The application uses the approved light-only red/yellow identity.

## Development rules

Follow [AGENTS.md](AGENTS.md) and [phase scope](docs/phase-1.md). Complete each business module vertically: database → backend API → backend tests → frontend UI → integration → complete feature tests. Preserve all important business rules. No Redis is included.
