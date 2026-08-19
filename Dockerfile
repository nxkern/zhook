FROM docker.io/kassany/alpine-ziglang:0.16.0 AS builder
WORKDIR /app
ENV ZIG_GLOBAL_CACHE_DIR=/tmp/zig-cache
COPY --chown=ziguana:ziguana . .
RUN zig build -Doptimize=ReleaseSmall -Dtarget=x86_64-linux-musl -Dcpu=baseline 

FROM alpine:3.20 AS certs


FROM scratch AS runner
WORKDIR /app
ENV URI_SERVER=http://locahost:3000
ENV TOKEN_CD=
ENV DOCKER_HOST=unix:///var/container/containerEngine.sock
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=builder /app/zig-out ./zig-out
EXPOSE 8088
CMD ["./zig-out/bin/zhook"]
