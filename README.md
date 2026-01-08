# shipper-backend (sample)

Small Go HTTP service exposing:

- GET /shipper?id=0001
- GET /healthz

## Run locally

```bash
go run ./cmd/shipper-backend
curl "http://localhost:8080/shipper?id=0001"
```

## Makefile build/install (matches S2I scripts)

```bash
make node=cloud build
make dest=/opt/app-root install
/opt/app-root/gobinary
```
