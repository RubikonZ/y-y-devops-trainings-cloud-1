ARG GOARCH=amd64
FROM golang:1.21 as build

WORKDIR /go/src/catgpt

COPY catgpt .

RUN go mod download
RUN CGO_ENABLED=0 GOARCH=${GOARCH} go build -o /go/bin/app

FROM gcr.io/distroless/static-debian12:latest-${GOARCH}
COPY --from=build /go/bin/app /
EXPOSE 8080 9090
CMD ["/app"]