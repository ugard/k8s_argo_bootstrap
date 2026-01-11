FROM golang:1.21-alpine AS builder
WORKDIR /src
RUN echo 'module alert-webhook' > go.mod && \
    echo 'go 1.21' >> go.mod
COPY main.go ./
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o webhook .

FROM alpine:3.19
RUN apk --no-cache add ca-certificates
COPY --from=builder /src/webhook /usr/local/bin/
ENTRYPOINT ["webhook"]
