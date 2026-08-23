FROM docker.io/kassany/alpine-ziglang:0.16.0 AS builder
WORKDIR /app

USER root
ENV ZIG_GLOBAL_CACHE_DIR=/tmp/zig-cache

ARG ZIG_TARGET=x86_64-linux-musl
ARG DOCKER_ARCH=x86_64
ARG DOCKER_VERSION=27.5.1
ARG COMPOSE_VERSION=v2.35.0

RUN apk add --no-cache wget
RUN mkdir -p /out/cli-plugins

RUN wget -q https://download.docker.com/linux/static/stable/${DOCKER_ARCH}/docker-${DOCKER_VERSION}.tgz
RUN tar -xzf docker-${DOCKER_VERSION}.tgz docker/docker
RUN mv docker/docker /out/docker
RUN rm docker-${DOCKER_VERSION}.tgz

RUN wget -qO /out/cli-plugins/docker-compose \
      https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-${DOCKER_ARCH}
RUN chmod +x /out/cli-plugins/docker-compose

COPY --chown=ziguana:ziguana . .
RUN zig build -Doptimize=ReleaseSmall -Dtarget=${ZIG_TARGET} -Dcpu=baseline 

FROM scratch AS runner
WORKDIR /app
ENV URI_SERVER=http://localhost:3000
ENV TOKEN_CD=replace_with_your_token
ENV ROUTE_APPS=/apps
ENV DOCKER_HOST=unix:///var/container/containerEngine.sock
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=builder /app/zig-out ./zig-out
COPY --from=builder /out/docker /usr/local/bin/docker
COPY --from=builder /out/cli-plugins/docker-compose /usr/local/lib/docker/cli-plugins/docker-compose
EXPOSE 8088
CMD ["./zig-out/bin/zhook"]
