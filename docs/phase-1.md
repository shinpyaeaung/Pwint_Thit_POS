# Phase 1 — Project foundation

## Scope decision

The explicit user workflow narrows this phase to infrastructure. Specification section 68 groups authentication, roles, permissions, products, and suppliers into a broader Phase 1; those features are deferred, not removed. Do not begin them until the foundation is verified and the user selects the next slice.

The original specification is copied verbatim into this directory. No business rules were changed.

## Foundation choices

- A Go/Gin API with pgx connection pooling, startup connection verification, environment validation, JSON logging, request IDs, safe JSON errors, HTTP timeouts, and graceful shutdown.
- Readiness (`GET /api/v1/health`) executes a sqlc-generated PostgreSQL query. Database failure returns HTTP 503. Liveness (`GET /api/v1/health/live`) reports process availability independently of PostgreSQL.
- React uses TanStack Query for health data and Zustand only for the expandable UI details. A shadcn/ui button, Tailwind theme, Inter font, and reduced-motion-aware Framer Motion establish the UI foundation.
- Brand colors follow the specification: primary red #ba0d0d, neutral #f8f8f8, and restrained amber accents. No mock financial dashboard, permissions, or business operations are exposed.
- Same-origin requests use a Vite development proxy and Nginx container proxy. There is no permissive cross-origin configuration.
- PostgreSQL 17 uses a persistent Docker volume. No Redis, business tables, or premature inventory/financial schema.
- The empty `app` schema is a bootstrap only. A migration runner must be added with the first actual database slice.

## Business rules retained for later slices

MMK base currency; original foreign amounts and historical exchange rates; historical batch costs; unlimited transport stages; selectable cost allocation; landed cost divided by sellable quantity; carton/unit conversions; below-cost protection; exactly SUPER_ADMIN and STAFF_ADMIN roles; per-user backend authorization; transactional stock/financial/audit operations; gross versus net profit; and reversals rather than deleting completed transactions.

## Official setup references

- [Tailwind Vite integration](https://tailwindcss.com/docs/installation/using-vite)
- [shadcn/ui setup](https://ui.shadcn.com/docs/installation/manual)
- [sqlc PostgreSQL tutorial](https://docs.sqlc.dev/en/stable/tutorials/getting-started-postgresql.html)

See `verification.md` for checks actually run and remaining limitations.
