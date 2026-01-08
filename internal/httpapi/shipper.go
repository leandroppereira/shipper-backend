package httpapi

import (
	"encoding/json"
	"net/http"

	"finemart/shipper-backend/pkg/model"
)

var shippers = map[string]model.Shipper{
	"0001": {
		ShipperID:   "0001",
		CompanyName: "ParcelLite - leandro",
		Phone:       "+1-407-555-0111",
	},
}

func ShipperHandler(w http.ResponseWriter, r *http.Request) {
	id := r.URL.Query().Get("id")
	if id == "" {
		http.Error(w, "missing query parameter: id", http.StatusBadRequest)
		return
	}

	shipper, ok := shippers[id]
	if !ok {
		http.Error(w, "shipper not found", http.StatusNotFound)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	enc := json.NewEncoder(w)
	enc.SetIndent("", "  ")
	_ = enc.Encode(shipper)
}
