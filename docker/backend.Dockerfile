FROM golang:1.27-alpine AS build
WORKDIR /src
COPY backend/go.mod backend/go.sum ./
RUN go mod download
COPY backend/ ./
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/api ./cmd/api && CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/migrate ./cmd/migrate && CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/create-admin ./cmd/create-admin

FROM alpine:3.23
RUN apk add --no-cache ca-certificates && addgroup -S app && adduser -S -G app app
WORKDIR /app
COPY --from=build /out/api ./api
COPY --from=build /out/migrate ./migrate
COPY --from=build /out/create-admin ./create-admin
COPY database/migrations ./migrations
USER app
EXPOSE 8080
CMD ["./api"]
