// Package reports provides read-only, permission-scoped business reports.
package reports

import "encoding/json"

type Column struct {
	Key   string `json:"key"`
	Label string `json:"label"`
	Kind  string `json:"kind"`
}
type Definition struct {
	ID          string   `json:"id"`
	Title       string   `json:"title"`
	Description string   `json:"description"`
	Columns     []Column `json:"columns"`
	Metrics     []Column `json:"metrics"`
}
type Filter struct {
	From     string `json:"from"`
	To       string `json:"to"`
	Period   string `json:"period"`
	Page     int32  `json:"page"`
	PageSize int32  `json:"page_size"`
}
type Result struct {
	Total   int64                        `json:"total"`
	Summary map[string]json.RawMessage   `json:"summary"`
	Rows    []map[string]json.RawMessage `json:"rows"`
}
type Response struct {
	Definition Definition `json:"definition"`
	Filter     Filter     `json:"filter"`
	Result
}
