FROM kassany/alpine-ziglang:0.16.0 AS builder
WORKDIR /app
ENV ZIG_GLOBAL_CACHE_DIR=/tmp/zig-cache
COPY --chown=ziguana:ziguana . .
RUN zig build -Doptimize=ReleaseSmall 


FROM scratch AS runner
WORKDIR /app
ENV URI_SERVER="http://locahost:3000"
ENV TOKEN_CD=""
COPY --from=builder /app/zig-out ./zig-out
EXPOSE 8088
CMD ["./zig-out/bin/zhook"]
