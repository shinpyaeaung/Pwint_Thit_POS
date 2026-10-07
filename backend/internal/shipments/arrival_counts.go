package shipments

import (
	"fmt"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/costing"
	"math/big"
)

func arrivalCounts(source costing.Source, in *costing.Input) error {
	expected := map[string]string{}
	for _, item := range source.Items {
		expected[item.ID] = item.Expected
	}
	for i := range in.Items {
		item := &in.Items[i]
		value, ok := expected[item.ID]
		if !ok {
			return fmt.Errorf("Choose an existing shipment item.")
		}
		if source.Status != "ARRIVED" {
			if item.Received != "" || item.Damaged != "" {
				return fmt.Errorf("Enter received and damaged quantities only after the shipment arrives.")
			}
			item.Sellable = value // Planning estimate only, never saved as a confirmed count.
			continue
		}
		if !decimal(item.Received, 14, 6, false) || !decimal(item.Damaged, 14, 6, false) {
			return fmt.Errorf("Enter actual received and damaged quantities after arrival.")
		}
		received, _ := new(big.Rat).SetString(item.Received)
		damaged, _ := new(big.Rat).SetString(item.Damaged)
		limit, _ := new(big.Rat).SetString(value)
		if received.Cmp(limit) > 0 || damaged.Cmp(received) > 0 {
			return fmt.Errorf("Received cannot exceed expected quantity; damaged cannot exceed received.")
		}
		sellable := new(big.Rat).Sub(received, damaged)
		if item.Sellable != "" {
			provided, ok := new(big.Rat).SetString(item.Sellable)
			if !ok || provided.Cmp(sellable) != 0 {
				return fmt.Errorf("Sellable quantity is calculated as received minus damaged.")
			}
		}
		item.Sellable = sellable.FloatString(6)
	}
	return nil
}
