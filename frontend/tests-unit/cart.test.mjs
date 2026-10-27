import { test } from 'node:test'
import assert from 'node:assert/strict'
import { cartTotal, lineTotal, scaled } from '../src/pages/pos/cart.ts'

test('cart sums exact line totals wider than an editable unit price', () => {
  const line = { quantity: '100', discount: '0', unit: 'PIECE', product: { packaging: [{ unit_code: 'PIECE', retail_price_mmk: '99999999999999.9999' }] } }
  const total = lineTotal(line, 'RETAIL')
  assert.equal(total, '9999999999999999.9900')
  assert.equal(cartTotal([total, '0.0100']), '10000000000000000.0000')
  assert.throws(() => scaled('100000000000000', 4))
})

test('invalid cart lines cannot silently become a payable total', () => {
  assert.equal(cartTotal(['1.0000', null]), null)
  assert.equal(cartTotal([]), null)
  assert.equal(cartTotal(['0.1000', '0.2000']), '0.3000')
})
