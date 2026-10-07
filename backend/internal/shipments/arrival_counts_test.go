package shipments

import (
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/costing"
	"testing"
)

func TestArrivalCounts(t *testing.T) {
	source := costing.Source{Status: "IN_TRANSIT", Items: []costing.SourceItem{{ID: "item", Expected: "100"}}}
	in := costing.Input{Items: []costing.InputItem{{ID: "item", Sellable: "1"}}}
	if e := arrivalCounts(source, &in); e != nil || in.Items[0].Sellable != "100" {
		t.Fatal("planning must use expected quantities", in, e)
	}
	in.Items[0].Received = "95"
	in.Items[0].Damaged = "5"
	if e := arrivalCounts(source, &in); e == nil {
		t.Fatal("accepted counts before arrival")
	}
	source.Status = "ARRIVED"
	in.Items[0].Sellable = ""
	if e := arrivalCounts(source, &in); e != nil || in.Items[0].Sellable != "90.000000" {
		t.Fatal(in, e)
	}
	for _, v := range []costing.InputItem{{ID: "item"}, {ID: "item", Received: "101", Damaged: "0"}, {ID: "item", Received: "10", Damaged: "11"}, {ID: "item", Received: "95", Damaged: "5", Sellable: "95"}, {ID: "item", Received: "NaN", Damaged: "0"}} {
		in.Items[0] = v
		if e := arrivalCounts(source, &in); e == nil {
			t.Fatal("invalid arrival counts", v)
		}
	}
	in.Items[0] = costing.InputItem{ID: "item", Received: "0", Damaged: "0"}
	if e := arrivalCounts(source, &in); e != nil || in.Items[0].Sellable != "0.000000" {
		t.Fatal("all goods missing", e)
	}
	in.Items[0] = costing.InputItem{ID: "item", Received: "1.000001", Damaged: "0.000001"}
	if e := arrivalCounts(source, &in); e != nil || in.Items[0].Sellable != "1.000000" {
		t.Fatal("decimal subtraction", e)
	}
}
