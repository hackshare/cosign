# Cosign relay — builds the `relay-server` binary from the cosign_core crate.
FROM rust:1-slim AS build
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential pkg-config libssl-dev clang \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
# build.rs runs uniffi scaffolding over src/cosign_core.udl, so src/ is needed.
COPY Cargo.toml Cargo.lock build.rs uniffi.toml ./
COPY src ./src
# static/ holds the marketing landing + privacy pages compiled into the binary
# via include_str! behind the `landing` feature.
COPY static ./static
RUN cargo build --release --bin relay-server --features landing

FROM debian:stable-slim
# ca-certificates for upstream TLS; libssl3 is native-tls's runtime dependency.
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates libssl3 \
    && rm -rf /var/lib/apt/lists/*
COPY --from=build /app/target/release/relay-server /usr/local/bin/relay-server
# Fly routes to internal_port 8080; the relay reads its bind address from env.
ENV COSIGN_RELAY_BIND_ADDR=0.0.0.0:8080
EXPOSE 8080
CMD ["relay-server"]
