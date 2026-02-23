FROM alpine:3.21 AS builder

# Install Zig 0.15.2 and build dependencies.
RUN apk add --no-cache curl xz && \
    curl -L https://ziglang.org/download/0.15.2/zig-x86_64-linux-0.15.2.tar.xz | \
    tar -xJ -C /opt && \
    mv /opt/zig-x86_64-linux-0.15.2 /opt/zig
ENV PATH="/opt/zig:${PATH}"

WORKDIR /src
COPY build.zig build.zig.zon ./
COPY src/ src/
COPY schemas/ schemas/

RUN zig build -Doptimize=ReleaseSafe -Dtarget=x86_64-linux

# --- Runtime stage ---
FROM alpine:3.21

RUN addgroup -S protomq && adduser -S protomq -G protomq

WORKDIR /opt/protomq

COPY --from=builder /src/zig-out/bin/protomq-server ./bin/protomq-server
COPY --from=builder /src/zig-out/bin/protomq-cli    ./bin/protomq-cli
COPY schemas/ ./schemas/

USER protomq

EXPOSE 1883

ENTRYPOINT ["./bin/protomq-server"]
