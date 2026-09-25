// Package costing uses rational arithmetic and integer 0.0001-MMK units.
// It never uses supplier price as a substitute for a complete landed cost.
package costing

import (
	"fmt"
	"math/big"
	"sort"
	"strings"
)

type SourceItem struct {
	ID               string `json:"id"`
	ProductName      string `json:"product_name"`
	SKU              string `json:"sku"`
	BaseUnit         string `json:"base_unit_code"`
	Expected         string `json:"expected_quantity"`
	PurchaseQuantity string `json:"purchase_quantity"`
	PurchaseTotal    string `json:"purchase_total_mmk"`
	UsedQuantity     string `json:"used_quantity"`
	UsedPurchase     string `json:"used_purchase_mmk"`
	PurchaseStatus   string `json:"purchase_status"`
}
type Source struct {
	Version   string       `json:"version"`
	Status    string       `json:"status"`
	Finalized bool         `json:"finalized"`
	Transport string       `json:"transport_mmk"`
	Expense   string       `json:"expense_mmk"`
	Items     []SourceItem `json:"items"`
}
type InputItem struct {
	ID        string `json:"id"`
	Sellable  string `json:"sellable_quantity"`
	Weight    string `json:"weight_kg"`
	Cartons   string `json:"carton_quantity"`
	Transport string `json:"manual_transport_mmk"`
	Expense   string `json:"manual_expense_mmk"`
}
type Input struct {
	Version      string      `json:"version"`
	Method       string      `json:"method"`
	Notes        string      `json:"notes"`
	Items        []InputItem `json:"items"`
	PreviewToken string      `json:"preview_token"`
}
type Item struct {
	ID          string  `json:"id"`
	ProductName string  `json:"product_name"`
	SKU         string  `json:"sku"`
	BaseUnit    string  `json:"base_unit_code"`
	Expected    string  `json:"expected_quantity"`
	Sellable    string  `json:"sellable_quantity"`
	Weight      string  `json:"weight_kg"`
	Cartons     string  `json:"carton_quantity"`
	Purchase    string  `json:"purchase_mmk"`
	Transport   string  `json:"transport_mmk"`
	Expense     string  `json:"expense_mmk"`
	Landed      string  `json:"landed_mmk"`
	Unit        *string `json:"actual_unit_cost_mmk"`
}
type Result struct {
	Method       string `json:"method"`
	Notes        string `json:"notes"`
	Purchase     string `json:"purchase_mmk"`
	Transport    string `json:"transport_mmk"`
	Expense      string `json:"expense_mmk"`
	Landed       string `json:"landed_mmk"`
	Items        []Item `json:"items"`
	PreviewToken string `json:"preview_token,omitempty"`
	Finalized    bool   `json:"finalized"`
}

func number(v string, whole, scale int) (*big.Rat, error) {
	p := strings.Split(v, ".")
	if len(p) > 2 || len(p[0]) == 0 || len(p[0]) > whole || (len(p) == 2 && (len(p[1]) == 0 || len(p[1]) > scale)) {
		return nil, fmt.Errorf("invalid decimal precision")
	}
	for _, s := range p {
		for _, r := range s {
			if r < '0' || r > '9' {
				return nil, fmt.Errorf("use non-negative decimal numbers")
			}
		}
	}
	n, ok := new(big.Rat).SetString(v)
	if !ok {
		return nil, fmt.Errorf("invalid decimal")
	}
	return n, nil
}
func rat(v string) *big.Rat { r, _ := new(big.Rat).SetString(v); return r }
func units(r *big.Rat) *big.Int {
	x := new(big.Rat).Mul(r, big.NewRat(10000, 1))
	q, rem := new(big.Int), new(big.Int)
	q.QuoRem(x.Num(), x.Denom(), rem)
	if new(big.Int).Mul(rem, big.NewInt(2)).Cmp(x.Denom()) >= 0 {
		q.Add(q, big.NewInt(1))
	}
	return q
}
func money(n *big.Int) string {
	s := n.String()
	if len(s) < 5 {
		s = strings.Repeat("0", 5-len(s)) + s
	}
	return s[:len(s)-4] + "." + s[len(s)-4:]
}

// Largest remainders conserve every 0.0001 MMK; stable item order breaks ties.
func distribute(total *big.Int, weights []*big.Rat) ([]*big.Int, error) {
	sum := new(big.Rat)
	for _, w := range weights {
		sum.Add(sum, w)
	}
	out := make([]*big.Int, len(weights))
	for i := range out {
		out[i] = new(big.Int)
	}
	if total.Sign() == 0 {
		return out, nil
	}
	if sum.Sign() == 0 {
		return nil, fmt.Errorf("allocation basis must have a positive total")
	}
	rems := make([]*big.Rat, len(weights))
	order := make([]int, len(weights))
	used := new(big.Int)
	for i, w := range weights {
		x := new(big.Rat).Quo(new(big.Rat).Mul(new(big.Rat).SetInt(total), w), sum)
		out[i].Quo(x.Num(), x.Denom())
		used.Add(used, out[i])
		rems[i] = new(big.Rat).Sub(x, new(big.Rat).SetInt(out[i]))
		order[i] = i
	}
	sort.SliceStable(order, func(i, j int) bool { return rems[order[i]].Cmp(rems[order[j]]) > 0 })
	left := new(big.Int).Sub(total, used).Int64() // remainder is strictly less than the number of items
	for i := int64(0); i < left; i++ {
		out[order[i]].Add(out[order[i]], big.NewInt(1))
	}
	return out, nil
}
func Calculate(src Source, in Input) (Result, error) {
	bad := func(msg string) (Result, error) { return Result{}, fmt.Errorf("%s", msg) }
	if len(src.Items) == 0 || len(src.Items) != len(in.Items) || len(in.Items) > 100 {
		return bad("Supply every shipment item exactly once.")
	}
	if len(in.Notes) > 2000 {
		return bad("Costing notes exceed 2000 characters.")
	}
	switch in.Method {
	case "QUANTITY", "PURCHASE_VALUE", "WEIGHT", "CARTONS", "MANUAL":
	default:
		return bad("Choose a valid allocation method.")
	}
	transport, e := number(src.Transport, 16, 4)
	if e != nil {
		return bad("Transport total exceeds supported precision.")
	}
	expense, e := number(src.Expense, 16, 4)
	if e != nil {
		return bad("Expense total exceeds supported precision.")
	}
	inputs := map[string]InputItem{}
	for _, v := range in.Items {
		if _, ok := inputs[v.ID]; ok {
			return bad("Duplicate item.")
		}
		inputs[v.ID] = v
	}
	rows := append([]SourceItem(nil), src.Items...)
	sort.Slice(rows, func(i, j int) bool { return rows[i].ID < rows[j].ID })
	r := Result{Method: in.Method, Notes: in.Notes, Transport: money(units(transport)), Expense: money(units(expense))}
	weights := []*big.Rat{}
	purchases := []*big.Int{}
	ts := []*big.Int{}
	es := []*big.Int{}
	purchaseSum := new(big.Int)
	for _, row := range rows {
		v, ok := inputs[row.ID]
		if !ok {
			return bad("Item does not belong to this shipment.")
		}
		if row.PurchaseStatus != "POSTED" {
			return bad("Only posted purchases can be costed.")
		}
		sellable, err := number(v.Sellable, 14, 6)
		if err != nil || sellable.Cmp(rat(row.Expected)) > 0 {
			return bad("Sellable quantity must be between zero and expected base quantity.")
		}
		weight, cartons := new(big.Rat), new(big.Rat)
		if v.Weight != "" {
			weight, err = number(v.Weight, 14, 6)
			if err != nil || weight.Sign() == 0 {
				return bad("Weight must be positive total kilograms for the item.")
			}
		}
		if v.Cartons != "" {
			cartons, err = number(v.Cartons, 14, 6)
			if err != nil {
				return bad("Carton quantity must be non-negative.")
			}
		}
		if in.Method == "WEIGHT" && v.Weight == "" {
			return bad("Enter total weight for every item.")
		}
		if in.Method == "CARTONS" && v.Cartons == "" {
			return bad("Enter carton quantity for every item.")
		}
		remainingQty := new(big.Rat).Sub(rat(row.PurchaseQuantity), rat(row.UsedQuantity))
		remainingCost := new(big.Rat).Sub(rat(row.PurchaseTotal), rat(row.UsedPurchase))
		if remainingQty.Sign() <= 0 || remainingCost.Sign() < 0 || remainingQty.Cmp(rat(row.Expected)) < 0 {
			return bad("Purchase quantity or cost has already been allocated. Reload the costing.")
		}
		// Allocate the remaining historical line cost over remaining quantity, so split shipments reconcile exactly.
		pc := units(new(big.Rat).Quo(new(big.Rat).Mul(remainingCost, rat(row.Expected)), remainingQty))
		purchases = append(purchases, pc)
		purchaseSum.Add(purchaseSum, pc)
		w := new(big.Rat)
		switch in.Method {
		case "QUANTITY":
			w = rat(row.Expected)
		case "PURCHASE_VALUE":
			w = new(big.Rat).SetInt(pc)
		case "WEIGHT":
			w = weight
		case "CARTONS":
			w = cartons
		case "MANUAL":
			t, err := number(v.Transport, 16, 4)
			if err != nil {
				return bad("Enter exact manual transport amounts for every item.")
			}
			x, err := number(v.Expense, 16, 4)
			if err != nil {
				return bad("Enter exact manual expense amounts for every item.")
			}
			ts = append(ts, units(t))
			es = append(es, units(x))
		}
		weights = append(weights, w)
		r.Items = append(r.Items, Item{ID: row.ID, ProductName: row.ProductName, SKU: row.SKU, BaseUnit: row.BaseUnit, Expected: row.Expected, Sellable: v.Sellable, Weight: v.Weight, Cartons: v.Cartons, Purchase: money(pc)})
	}
	if in.Method == "MANUAL" {
		sumT, sumE := new(big.Int), new(big.Int)
		for i := range ts {
			sumT.Add(sumT, ts[i])
			sumE.Add(sumE, es[i])
		}
		if sumT.Cmp(units(transport)) != 0 || sumE.Cmp(units(expense)) != 0 {
			return bad("Manual allocations must match transport and expense totals separately.")
		}
	} else {
		ts, e = distribute(units(transport), weights)
		if e != nil {
			return bad(e.Error())
		}
		es, e = distribute(units(expense), weights)
		if e != nil {
			return bad(e.Error())
		}
	}
	total := new(big.Int).Set(purchaseSum)
	total.Add(total, units(transport))
	total.Add(total, units(expense))
	r.Purchase = money(purchaseSum)
	r.Landed = money(total)
	if _, e = number(r.Landed, 16, 4); e != nil {
		return bad("Landed cost exceeds supported precision.")
	}
	for i := range r.Items {
		item := &r.Items[i]
		item.Transport = money(ts[i])
		item.Expense = money(es[i])
		line := new(big.Int).Add(purchases[i], ts[i])
		line.Add(line, es[i])
		item.Landed = money(line)
		qty := rat(item.Sellable)
		if qty.Sign() > 0 {
			u := new(big.Rat).Quo(rat(item.Landed), qty).FloatString(8)
			if _, e = number(u, 16, 8); e != nil {
				return bad("Unit cost exceeds supported precision.")
			}
			item.Unit = &u
		}
	}
	return r, nil
}
