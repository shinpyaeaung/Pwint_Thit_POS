import { spawnSync } from 'node:child_process'
import { existsSync } from 'node:fs'
if (existsSync('.env')) process.loadEnvFile('.env')
const url = process.env.TEST_DATABASE_URL || process.env.DATABASE_URL
if (!url) throw new Error('Set DATABASE_URL or TEST_DATABASE_URL before running integration tests.')
const args = process.env.RUN_BROWSER_TESTS === '1' ? ['test', '-count=1', '-v', '-run', '^TestBrowserIntegration$', './internal/authn'] : ['test', '-count=1', '-v', './internal/database', './internal/migrate', './internal/authz', './internal/authn', './internal/products', './internal/suppliers']
const result = spawnSync('go', args, {
  cwd: 'backend', stdio: 'inherit', env: { ...process.env, TEST_DATABASE_URL: url },
})
if (result.error) throw result.error
process.exitCode = result.status ?? 1
