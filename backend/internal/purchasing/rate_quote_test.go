package purchasing

import "testing"

func TestNormalizeQuote(t *testing.T) {
	for _, tc := range []struct{ foreign, mmk, want string }{
		{"100", "4450", "44.5000000000"},
		{"100", "4500", "45.0000000000"},
		{"3", "1", "0.3333333333"},
		{"6", "1", "0.1666666667"},
		{"0.1", "4.45", "44.5000000000"},
	} {
		got, err := NormalizeQuote(tc.foreign, tc.mmk)
		if err != nil || got != tc.want {
			t.Errorf("%s = %s: got %s, %v; want %s", tc.foreign, tc.mmk, got, err, tc.want)
		}
	}
	for _, tc := range [][2]string{{"0", "4450"}, {"100", "0"}, {"-100", "4450"}, {"", "4450"}, {"NaN", "1"}, {"1e2", "4450"}, {"99999999999999", "0.0000000001"}, {"0.0000000001", "99999999999999"}} {
		if _, err := NormalizeQuote(tc[0], tc[1]); err == nil {
			t.Errorf("accepted invalid quote %v", tc)
		}
	}
}
