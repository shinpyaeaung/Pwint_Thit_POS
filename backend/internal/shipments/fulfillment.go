package shipments

type Fulfillment struct {
	Mode    string `json:"mode"`
	Person  string `json:"person_name"`
	Vehicle string `json:"vehicle_number"`
}

func (f Fulfillment) valid() bool {
	return (f.Mode == "DELIVERY" || f.Mode == "COLLECTION") && len(f.Person) <= 200 && len(f.Vehicle) <= 100
}
