# syntax=docker/dockerfile:1.14.0

ARG TARGETPLATFORM
ARG BUILDPLATFORM
ARG PROJECT=omgwtfbbq


FROM --platform=$BUILDPLATFORM rust:1.83-bookworm AS rust
ARG TARGETPLATFORM
ARG BUILDPLATFORM

WORKDIR /build/

RUN if [ "$TARGETPLATFORM" = "linux/arm64" ]; then \
      rustup target add aarch64-unknown-linux-gnu; \
      if [ "$BUILDPLATFORM" != "linux/arm64" ]; then \
        dpkg --add-architecture arm64; \
        apt update && apt install -y gcc-aarch64-linux-gnu g++-aarch64-linux-gnu; \
      else \
        apt update; \
      fi; \
    elif [ "$TARGETPLATFORM" = "linux/amd64" ]; then \
      rustup target add x86_64-unknown-linux-gnu; \
      if [ "$BUILDPLATFORM" != "linux/amd64" ]; then \
        dpkg --add-architecture amd64; \
        apt update && apt install -y gcc-x86_64-linux-gnu g++-x86_64-linux-gnu; \
      else \
        apt update; \
      fi; \
    fi; \
    apt install -y libclang-dev clang;


FROM rust AS builder
ARG BUILDPLATFORM
ARG TARGETPLATFORM
ARG PROJECT

COPY . .
RUN mkdir -p release
RUN \
    --mount=type=cache,target=/usr/local/cargo/registry,id=${TARGETPLATFORM}-${PROJECT} \
    --mount=type=cache,target=/build/target,id=${TARGETPLATFORM}-${PROJECT} \
    if [ "$TARGETPLATFORM" = "linux/arm64" ] && [ "$BUILDPLATFORM" != "linux/arm64" ]; then \
      export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER=aarch64-linux-gnu-gcc \
        CC_aarch64_unknown_linux_gnu=aarch64-linux-gnu-gcc \
        CXX_aarch64_unknown_linux_gnu=aarch64-linux-gnu-g++ \
        PKG_CONFIG_SYSROOT_DIR=/usr/aarch64-linux-gnu; \
      TARGET_TRIPLE=aarch64-unknown-linux-gnu; \
    elif [ "$TARGETPLATFORM" = "linux/amd64" ] && [ "$BUILDPLATFORM" != "linux/amd64" ]; then \
      export CARGO_TARGET_x86_64_UNKNOWN_LINUX_GNU_LINKER=x86_64-linux-gnu-gcc \
        CC_x86_64_unknown_linux_gnu=x86_64-linux-gnu-gcc \
        CXX_x86_64_unknown_linux_gnu=x86_64-linux-gnu-g++ \
        PKG_CONFIG_SYSROOT_DIR=/usr/x86_64-linux-gnu; \
      TARGET_TRIPLE=x86_64-unknown-linux-gnu; \
    else \
      TARGET_TRIPLE=$(uname -m)-unknown-linux-gnu; \
    fi; \
    cargo build --release --target $TARGET_TRIPLE --bin ${PROJECT};\
    # Copies the binary from out of the cache directory
    if [ "$TARGETPLATFORM" = "linux/arm64" ]; then ARCH=aarch64; \
    elif [ "$TARGETPLATFORM" = "linux/amd64" ]; then ARCH=x86_64; fi; \
    cp target/$ARCH-unknown-linux-gnu/release/${PROJECT} release/;


FROM debian:bookworm-slim
ARG TARGETPLATFORM
ARG BUILDPLATFORM
ARG PROJECT
ENV PROJECT=${PROJECT}

RUN \
    apt update; \
    apt install -y wget ca-certificates libsqlite3-0 libssl3; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*;
COPY --from=builder /build/release/${PROJECT} /usr/local/bin/${PROJECT}

RUN \
  printf "#!/bin/sh\nexec /usr/local/bin/${PROJECT} \$@\n" > /usr/local/bin/entrypoint.sh; \
  chmod +x /usr/local/bin/entrypoint.sh;
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
