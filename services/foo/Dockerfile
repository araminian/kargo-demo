FROM golang:1.19-alpine AS base
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN go build -o foo main.go

FROM alpine:latest
WORKDIR /app
USER 1001
COPY --from=base /app/foo .
EXPOSE 3000
CMD ["./foo"]
