package httpapi

import "net/http"

func Router() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/shipper", ShipperHandler)
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	return mux
}
