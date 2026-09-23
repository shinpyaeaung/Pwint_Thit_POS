import { spawn } from 'node:child_process'
import { mkdirSync } from 'node:fs'
mkdirSync('backend/bin', { recursive: true })
const build = spawn('go', ['build', '-o', 'bin/api', './cmd/api'], { cwd: 'backend', stdio: 'inherit' })
build.on('exit', code => {
  if (code !== 0) { process.exitCode = code ?? 1; return }
  const children = [
    spawn('./bin/api', [], { cwd: 'backend', stdio: 'inherit' }),
    spawn(process.execPath, ['node_modules/vite/bin/vite.js'], { cwd: 'frontend', stdio: 'inherit' }),
  ]
  let stopping = false
  function stop(code = 0) {
    if (stopping) return
    stopping = true
    process.exitCode = code
    children.forEach(child => child.kill('SIGTERM'))
  }
  process.on('SIGINT', () => stop())
  process.on('SIGTERM', () => stop())
  children.forEach(child => {
    child.on('error', error => { console.error(error); stop(1) })
    child.on('exit', code => { if (!stopping) stop(code || 1) })
  })
})
build.on('error', error => { console.error(error); process.exitCode = 1 })
