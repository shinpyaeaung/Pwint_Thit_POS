import { test } from 'node:test'
import assert from 'node:assert/strict'
import { dispatchQuantity, dispatchQuantityError } from '../src/pages/transfers/dispatch-quantity.ts'

test('dispatch converts cartons and loose pieces exactly using each batch size', () => {
  assert.equal(dispatchQuantity('2', '12', '3'), '27.000000')
  assert.equal(dispatchQuantity('2', '24', '3'), '51.000000')
  assert.equal(dispatchQuantity('27', null), '27.000000')
  assert.equal(dispatchQuantity('0.1', '0.2'), '0.020000')
  assert.equal(dispatchQuantity('99999999999999', null), '99999999999999.000000')
})
test('dispatch rejects rounding, overflow, invalid inputs and over-dispatch', () => {
  for (const args of [['0.000001', '0.000001'], ['1', '0'], ['-1', null], ['', '12'], ['99999999999999', '12']]) assert.equal(dispatchQuantity(...args), null)
  assert.ok(dispatchQuantityError(null, '10'))
  assert.ok(dispatchQuantityError('0', '10'))
  assert.ok(dispatchQuantityError(dispatchQuantity('2', '12', '1'), '24'))
  assert.equal(dispatchQuantityError(dispatchQuantity('2', '12'), '24'), null)
})
