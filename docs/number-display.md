# Number display

Prices, amounts and quantities hide insignificant trailing decimal zeros in resting form fields: `250000.0000` displays as `250000`, `12.000000` as `12`, and `0.500000` as `0.5`. Existing table formatting already follows this convention. Meaningful fractional digits remain visible; this is not rounding to whole units.

The shared DecimalInput keeps actively typed decimal text intact until blur. Focusing a field does not rewrite its displayed value. Exact source strings and submitted amounts are preserved, with no Number/parseFloat conversion or database changes. Exchange-rate fields explicitly retain their original decimal precision. Legacy numeric fields for payments, opening balances, special prices, stock and damaged sales use the same component; names, references and dates remain ordinary text fields.

Verification covers unpadded initial amounts, large exact amounts, fractional quantities, invalid precision, loaded shipment quantities and payment inputs. Existing real-stack flows continue to check exact persisted prices, balances, exchange rates, receiving and stock quantities.
