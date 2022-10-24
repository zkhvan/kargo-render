FROM --platform=$BUILDPLATFORM ghcr.io/akuityio/k8sta-tools:v0.3.0 as builder

ARG TARGETOS
ARG TARGETARCH

ARG HELM_VERSION=v3.9.4
RUN curl -L -o /tmp/helm.tar.gz \
      https://get.helm.sh/helm-${HELM_VERSION}-linux-${TARGETARCH}.tar.gz \
    && tar xvfz /tmp/helm.tar.gz -C /usr/local/bin --strip-components 1

ARG KUSTOMIZE_VERSION=v4.5.5
RUN curl -L -o /tmp/kustomize.tar.gz \
      https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2F${KUSTOMIZE_VERSION}/kustomize_${KUSTOMIZE_VERSION}_linux_${TARGETARCH}.tar.gz \
    && tar xvfz /tmp/kustomize.tar.gz -C /usr/local/bin

ARG YTT_VERSION=v0.41.1
RUN curl -L -o /usr/local/bin/ytt \
      https://github.com/vmware-tanzu/carvel-ytt/releases/download/${YTT_VERSION}/ytt-linux-${TARGETARCH} \
      && chmod 755 /usr/local/bin/ytt

ARG VERSION_PACKAGE=github.com/akuityio/bookkeeper/pkg/internal/common/version
ARG VERSION
ARG CGO_ENABLED=0

WORKDIR /bookkeeper
COPY go.mod .
COPY go.sum .
RUN go mod download
COPY cmd cmd
COPY internal internal
COPY *.go .

RUN ls

RUN GOOS=${TARGETOS} GOARCH=${TARGETARCH} go build \
      -ldflags "-w -X ${VERSION_PACKAGE}.version=${VERSION} -X ${VERSION_PACKAGE}.buildDate=$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
      -o bin/bookkeeper-action \
      ./cmd/action \
    && bin/bookkeeper-action version \
    && GOOS=${TARGETOS} GOARCH=${TARGETARCH} go build \
      -tags thick \
      -ldflags "-w -X ${VERSION_PACKAGE}.version=${VERSION} -X ${VERSION_PACKAGE}.buildDate=$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
      -o bin/bookkeeper \
      ./cmd/cli \
    && bin/bookkeeper version \ 
    && GOOS=${TARGETOS} GOARCH=${TARGETARCH} go build \
      -ldflags "-w -X ${VERSION_PACKAGE}.version=${VERSION} -X ${VERSION_PACKAGE}.buildDate=$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
      -o bin/bookkeeper-server \
      ./cmd/server \
    && bin/bookkeeper-server version


FROM alpine:3.15.4 as final

RUN apk update \
    && apk add git openssh-client \
    && addgroup -S -g 65532 nonroot \
    && adduser -S -D -H -u 65532 -g nonroot -G nonroot nonroot

COPY --from=builder /usr/local/bin/helm /usr/local/bin/
COPY --from=builder /usr/local/bin/kustomize /usr/local/bin/
COPY --from=builder /usr/local/bin/ytt /usr/local/bin/
COPY --from=builder /bookkeeper/bin/ /usr/local/bin/

USER nonroot

CMD ["/usr/local/bin/bookkeeper-server"]