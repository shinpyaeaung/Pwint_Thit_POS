package costing

import (
	"fmt"
	"math/big"
	"testing"
)

func fixture() (Source, Input) {
	src := Source{Transport: "80", Expense: "20", Items: []SourceItem{
		{ID: "a", Expected: "10", PurchaseQuantity: "10", PurchaseTotal: "100", UsedQuantity: "0", UsedPurchase: "0", PurchaseStatus: "POSTED"},
		{ID: "b", Expected: "30", PurchaseQuantity: "30", PurchaseTotal: "100", UsedQuantity: "0", UsedPurchase: "0", PurchaseStatus: "POSTED"},
	}}
	in := Input{Method: "QUANTITY", Items: []InputItem{{ID: "a", Sellable: "8", Weight: "1", Cartons: "4", Transport: "30", Expense: "2"}, {ID: "b", Sellable: "30", Weight: "2", Cartons: "1", Transport: "50", Expense: "18"}}}
	return src, in
}
func TestAllAllocationFormulas(t *testing.T) {
	for _, tc := range []struct{ method, t0, t1, e0, e1, landed, unit string }{
		{"QUANTITY", "20.0000", "60.0000", "5.0000", "15.0000", "125.0000", "15.62500000"},
		{"PURCHASE_VALUE", "40.0000", "40.0000", "10.0000", "10.0000", "150.0000", "18.75000000"},
		{"WEIGHT", "26.6667", "53.3333", "6.6667", "13.3333", "133.3334", "16.66667500"},
		{"CARTONS", "64.0000", "16.0000", "16.0000", "4.0000", "180.0000", "22.50000000"},
		{"MANUAL", "30.0000", "50.0000", "2.0000", "18.0000", "132.0000", "16.50000000"},
	} {
		t.Run(tc.method, func(t *testing.T) {
			src, in := fixture()
			in.Method = tc.method
			r, e := Calculate(src, in)
			if e != nil {
				t.Fatal(e)
			}
			a, b := r.Items[0], r.Items[1]
			if a.Transport != tc.t0 || b.Transport != tc.t1 || a.Expense != tc.e0 || b.Expense != tc.e1 || a.Landed != tc.landed || *a.Unit != tc.unit || r.Landed != "300.0000" {
				t.Fatalf("wrong allocation: %+v %+v %+v", r, a, b)
			}
		})
	}
}
func TestCoreExampleAndZeroSellable(t *testing.T) {
	src := Source{Transport: "80000", Expense: "0", Items: []SourceItem{{ID: "a", Expected: "12", PurchaseQuantity: "12", PurchaseTotal: "120000", UsedQuantity: "0", UsedPurchase: "0", PurchaseStatus: "POSTED"}}}
	in := Input{Method: "QUANTITY", Items: []InputItem{{ID: "a", Sellable: "12"}}}
	r, e := Calculate(src, in)
	if e != nil || r.Landed != "200000.0000" || *r.Items[0].Unit != "16666.66666667" {
		t.Fatal(r, e)
	}
	in.Items[0].Sellable = "0"
	r, e = Calculate(src, in)
	if e != nil || r.Items[0].Unit != nil || r.Items[0].Landed != "200000.0000" {
		t.Fatal("zero quantity must retain loss without division", r, e)
	}
}
func TestInvalidCostingInputs(t *testing.T) {
	for _, kind := range []string{"missing", "duplicate", "unknown", "method", "negative", "nan", "precision", "excess", "weight", "cartons", "zero_basis", "manual", "reversed", "exhausted", "overflow"} {
		t.Run(kind, func(t *testing.T) {
			src, in := fixture()
			switch kind {
			case "missing":
				in.Items = in.Items[:1]
			case "duplicate":
				in.Items[1].ID = "a"
			case "unknown":
				in.Items[1].ID = "x"
			case "method":
				in.Method = "PRICE"
			case "negative":
				in.Items[0].Sellable = "-1"
			case "nan":
				in.Items[0].Sellable = "NaN"
			case "precision":
				in.Items[0].Sellable = "1.0000001"
			case "excess":
				in.Items[0].Sellable = "11"
			case "weight":
				in.Method = "WEIGHT"
				in.Items[0].Weight = ""
			case "cartons":
				in.Method = "CARTONS"
				in.Items[0].Cartons = ""
			case "zero_basis":
				in.Method = "CARTONS"
				in.Items[0].Cartons = "0"
				in.Items[1].Cartons = "0"
			case "manual":
				in.Method = "MANUAL"
				in.Items[0].Transport = "31"
			case "reversed":
				src.Items[0].PurchaseStatus = "REVERSED"
			case "exhausted":
				src.Items[0].UsedQuantity = "10"
			case "overflow":
				src.Transport = "9999999999999999.9999"
			}
			if _, e := Calculate(src, in); e == nil {
				t.Fatal("accepted invalid costing")
			}
		})
	}
}
func TestRoundingConservation(t *testing.T) {
	for n := 1; n <= 100; n++ {
		weights := make([]*big.Rat, n)
		for i := range weights {
			weights[i] = big.NewRat(int64(i+1), 7)
		}
		for _, v := range []int64{0, 1, 2, 99, 10001, 999999999} {
			out, e := distribute(big.NewInt(v), weights)
			if e != nil {
				t.Fatal(e)
			}
			sum := new(big.Int)
			for _, x := range out {
				if x.Sign() < 0 {
					t.Fatal("negative allocation")
				}
				sum.Add(sum, x)
			}
			if sum.Cmp(big.NewInt(v)) != 0 {
				t.Fatal("lost rounding remainder")
			}
		}
	}
	out, _ := distribute(big.NewInt(2), []*big.Rat{big.NewRat(1, 1), big.NewRat(1, 1), big.NewRat(1, 1)})
	if fmt.Sprint(out) != "[1 1 0]" {
		t.Fatal("unstable tie break", out)
	}
}
func TestSplitPurchaseReconciliation(t *testing.T) {
	used := new(big.Rat)
	for n := 0; n < 3; n++ {
		src := Source{Transport: "0", Expense: "0", Items: []SourceItem{{ID: "a", Expected: "1", PurchaseQuantity: "3", PurchaseTotal: "0.0001", UsedQuantity: fmt.Sprint(n), UsedPurchase: used.FloatString(4), PurchaseStatus: "POSTED"}}}
		in := Input{Method: "QUANTITY", Items: []InputItem{{ID: "a", Sellable: "1"}}}
		r, e := Calculate(src, in)
		if e != nil {
			t.Fatal(e)
		}
		used.Add(used, rat(r.Purchase))
	}
	if used.Cmp(rat("0.0001")) != 0 {
		t.Fatal("split shipments lost purchase cost", used)
	}
	src, in := fixture()
	src.Transport = "0"
	src.Expense = "0"
	src.Items[0].PurchaseTotal = "0"
	src.Items[1].PurchaseTotal = "0"
	in.Method = "PURCHASE_VALUE"
	if r, e := Calculate(src, in); e != nil || r.Landed != "0.0000" {
		t.Fatal("free shipment", r, e)
	}
}
