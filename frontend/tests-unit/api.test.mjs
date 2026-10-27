import { test } from 'node:test'
import assert from 'node:assert/strict'
import { ApiError, requestJSON } from '../src/services/api.ts'

test('a truncated successful checkout response remains an uncertain result', async t => {
  t.mock.method(globalThis, 'fetch', async () => new Response('{"id":', { status: 201 }))
  await assert.rejects(requestJSON('/pos/checkout', { method: 'POST', body: '{}' }), error =>
    error instanceof ApiError && error.status >= 500)
})

test('a response body connection failure remains an uncertain result', async t => {
  t.mock.method(globalThis, 'fetch', async () => ({ ok: true, status: 201, json: async () => { throw new TypeError('terminated') } }))
  await assert.rejects(requestJSON('/pos/checkout', { method: 'POST', body: '{}' }), error =>
    error instanceof ApiError && error.status >= 500)
})

test('preserves validation status and does not retry a mutation automatically', async t => {
  const fetch = t.mock.method(globalThis, 'fetch', async () => new Response('{"error":{"message":"Insufficient stock"}}', { status: 409 }))
  await assert.rejects(requestJSON('/pos/checkout', { method: 'POST', body: '{}' }), error =>
    error instanceof ApiError && error.status === 409 && error.message === 'Insufficient stock')
  assert.equal(fetch.mock.callCount(), 1)
})

test('merges Headers objects with required JSON and origin-check headers', async t => {
  t.mock.method(globalThis, 'fetch', async (_url, options) => {
    const headers = new Headers(options.headers)
    assert.equal(headers.get('X-Test'), 'preserved')
    assert.equal(headers.get('X-Pwint-Thit-Request'), '1')
    assert.equal(headers.get('Content-Type'), 'application/json')
    return new Response(null, { status: 204 })
  })
  assert.equal(await requestJSON('/test', { method: 'POST', body: '{}', headers: new Headers({ 'X-Test': 'preserved' }) }), undefined)
})
