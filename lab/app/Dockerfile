FROM golang:1.26.8-alpine@sha256:8ac98ca534ac3f51e1f420a1dd2c15e74c75cfa0f23f3ad27eb5d7236c349a0c AS build
WORKDIR /src
ENV GOTOOLCHAIN=local GOMAXPROCS=2 CGO_ENABLED=0
COPY go.mod main.go main_test.go ./
RUN test -z "$(gofmt -l .)" && go vet ./... && go test -count=1 -v ./...
ARG APP_VERSION=dev
ARG VCS_REF=unknown
RUN go build -trimpath -buildvcs=false -ldflags="-s -w -X main.version=${APP_VERSION} -X main.revision=${VCS_REF}" -o /out/lab-http .

FROM scratch
COPY --from=build /out/lab-http /lab-http
USER 65532:65532
EXPOSE 8080
STOPSIGNAL SIGTERM
ENTRYPOINT ["/lab-http"]
