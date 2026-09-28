package reports

import (
	"fmt"
	"net/url"
	"strconv"
	"time"
	_ "time/tzdata"
)

var businessZone = func() *time.Location {
	zone, err := time.LoadLocation("Asia/Yangon")
	if err != nil {
		panic(err)
	}
	return zone
}()

// ValidateFilter resolves presets on the server and rejects ambiguous/unknown inputs.
func ValidateFilter(values url.Values, now time.Time) (Filter, error) {
	fail := func(message string) (Filter, error) { return Filter{}, fmt.Errorf("%s", message) }
	for key, entries := range values {
		if key != "period" && key != "from" && key != "to" && key != "page" && key != "page_size" {
			return fail("Unknown report filter: " + key)
		}
		if len(entries) != 1 || entries[0] == "" {
			return fail("Report filters must have one non-empty value.")
		}
	}
	today := now.In(businessZone)
	today = time.Date(today.Year(), today.Month(), today.Day(), 0, 0, 0, 0, businessZone)
	period := values.Get("period")
	if period == "" {
		period = "month"
	}
	start, end := today, today
	if period != "custom" && (values.Has("from") || values.Has("to")) {
		return fail("Use Custom Date Range with from and to dates.")
	}
	switch period {
	case "today":
	case "week":
		start = today.AddDate(0, 0, -(int(today.Weekday())+6)%7)
	case "month":
		start = time.Date(today.Year(), today.Month(), 1, 0, 0, 0, 0, businessZone)
	case "year":
		start = time.Date(today.Year(), time.January, 1, 0, 0, 0, 0, businessZone)
	case "custom":
		var err error
		start, err = time.ParseInLocation("2006-01-02", values.Get("from"), businessZone)
		if err != nil {
			return fail("Enter a valid from date (YYYY-MM-DD).")
		}
		end, err = time.ParseInLocation("2006-01-02", values.Get("to"), businessZone)
		if err != nil {
			return fail("Enter a valid to date (YYYY-MM-DD).")
		}
	default:
		return fail("Choose today, week, month, year or custom.")
	}
	if start.Year() < 1 || end.Year() > 9998 || start.After(end) {
		return fail("From date must be on or before to date, within years 0001–9998.")
	}
	if end.After(today) {
		return fail("Reports cannot end after today's Myanmar business date.")
	}
	page, size := int64(1), int64(25)
	for key, destination := range map[string]*int64{"page": &page, "page_size": &size} {
		if values.Has(key) {
			n, err := strconv.ParseInt(values.Get(key), 10, 32)
			if err != nil || n < 1 {
				return fail("Page and page size must be positive integers.")
			}
			*destination = n
		}
	}
	if size > 100 || page > 1000000 {
		return fail("Page size must be at most 100 and page at most 1000000.")
	}
	return Filter{From: start.Format("2006-01-02"), To: end.Format("2006-01-02"), Period: period, Page: int32(page), PageSize: int32(size)}, nil
}
