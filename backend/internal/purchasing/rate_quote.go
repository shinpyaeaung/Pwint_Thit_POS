package purchasing

import (
	"errors"
	"math/big"
)

// NormalizeQuote converts a quoted pair using exact decimal arithmetic. Stored
// rates retain the existing NUMERIC scale of ten decimal places, rounded half up.
func NormalizeQuote(foreign, mmk string) (string, error) {
	if !decimal(foreign, 14, 10, true) || !decimal(mmk, 14, 10, true) {
		return "", errors.New("Enter positive currency and MMK amounts, with up to 14 whole digits and 10 decimal places.")
	}
	a, _ := new(big.Rat).SetString(foreign)
	b, _ := new(big.Rat).SetString(mmk)
	rate := new(big.Rat).Quo(b, a).FloatString(10)
	if !decimal(rate, 14, 10, true) {
		return "", errors.New("The resulting rate is outside the supported range.")
	}
	return rate, nil
}
