FROM golang:1.18 AS builder
WORKDIR /src
COPY . .
RUN CGO_ENABLED=0 GO111MODULE=on go build -o /out/shipper-backend .

FROM registry.access.redhat.com/ubi9/ubi-minimal
ENV SERVER_PORT=8081
EXPOSE 8081
COPY --from=builder /out/shipper-backend /usr/local/bin/shipper-backend
USER 1001
ENTRYPOINT ["/usr/local/bin/shipper-backend"]
