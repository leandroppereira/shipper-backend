package main

import (
	"log"
	"net/http"
	"os"

	"finemart/shipper-backend/internal/httpapi"
)

func main() {
	// No customizations here. We support common OpenShift env vars:
	// - SERVER_PORT (if provided)
	// - PORT (common default)
	// - fallback to 8080
	port := os.Getenv("SERVER_PORT")
	if port == "" {
		port = os.Getenv("PORT")
	}
	if port == "" {
		port = "8080"
	}

	addr := ":" + port
	log.Printf("shipper-backend listening on %s", addr)

	srv := &http.Server{
		Addr:    addr,
		Handler: httpapi.Router(),
	}

	if err := srv.ListenAndServe(); err != nil {
		log.Fatal(err)
	}
}
