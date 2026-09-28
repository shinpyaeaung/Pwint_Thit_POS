package reports

import (
	"net/url"
	"testing"
	"time"
)

func TestValidateFilter(t *testing.T) {
	// Sunday UTC has already become Monday in Myanmar.
	now := time.Date(2026, 3, 1, 18, 0, 0, 0, time.UTC)
	for _, tc := range []struct{ period, from, to string }{
		{"today", "2026-03-02", "2026-03-02"}, {"week", "2026-03-02", "2026-03-02"},
		{"month", "2026-03-01", "2026-03-02"}, {"year", "2026-01-01", "2026-03-02"},
	} {
		f, err := ValidateFilter(url.Values{"period": {tc.period}}, now)
		if err != nil || f.From != tc.from || f.To != tc.to {
			t.Fatalf("%s: %+v %v", tc.period, f, err)
		}
	}
	for _, raw := range []string{"period=bad", "period=custom", "period=custom&from=2026-02-30&to=2026-03-01", "period=custom&from=2026-03-02&to=2026-03-01", "period=custom&from=2026-03-01&to=2026-03-03", "page=-1", "page=1.5", "page_size=101", "page_size=0", "page=2147483648", "page=1&page=2", "period=month&from=2026-01-01", "unexpected=x"} {
		values, _ := url.ParseQuery(raw)
		if _, err := ValidateFilter(values, now); err == nil {
			t.Errorf("accepted %s", raw)
		}
	}
	f, err := ValidateFilter(url.Values{"period": {"custom"}, "from": {"2024-02-29"}, "to": {"2024-02-29"}, "page": {"3"}, "page_size": {"10"}}, now)
	if err != nil || f.From != "2024-02-29" || f.Page != 3 {
		t.Fatal(f, err)
	}
}
