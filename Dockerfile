# Stalwart Dockerfile
# Credits: https://github.com/33KK 

FROM --platform=$BUILDPLATFORM docker.io/lukemathwalker/cargo-chef:latest-rust-slim-bookworm AS chef
WORKDIR /build

FROM --platform=$BUILDPLATFORM chef AS planner
COPY . .
RUN cargo chef prepare --recipe-path /recipe.json

FROM --platform=$BUILDPLATFORM chef AS builder
ARG TARGETPLATFORM

# 设置目标平台
RUN case "${TARGETPLATFORM}" in \
    "linux/arm64") echo "aarch64-unknown-linux-musl" > /target.txt && echo "-C linker=aarch64-linux-musl-gcc" > /flags.txt ;; \
    "linux/amd64") echo "x86_64-unknown-linux-musl" > /target.txt && echo "-C linker=x86_64-linux-musl-gcc" > /flags.txt ;; \
    *) exit 1 ;; \
    esac

# 安装依赖
RUN export DEBIAN_FRONTEND=noninteractive && \
    dpkg --add-architecture arm64 && \
    apt-get update && \
    apt-get install -yq \
    build-essential \
    libclang-16-dev \
    pkg-config \
    musl-tools \
    musl-dev \
    libssl-dev \
    libssl-dev:arm64 \
    gcc-aarch64-linux-gnu \
    g++-aarch64-linux-gnu \
    libc6-dev-arm64-cross

# 设置交叉编译环境变量
ENV PKG_CONFIG_ALLOW_CROSS=1 \
    PKG_CONFIG_PATH=/usr/lib/aarch64-linux-gnu/pkgconfig \
    PKG_CONFIG_SYSROOT_DIR=/usr/aarch64-linux-gnu \
    OPENSSL_DIR=/usr/lib/aarch64-linux-gnu \
    OPENSSL_INCLUDE_DIR=/usr/include \
    OPENSSL_LIB_DIR=/usr/lib/aarch64-linux-gnu \
    OPENSSL_STATIC=1 \
    CC_aarch64_unknown_linux_musl=aarch64-linux-gnu-gcc \
    CXX_aarch64_unknown_linux_musl=aarch64-linux-gnu-g++

# 创建必要的符号链接
RUN mkdir -p /usr/aarch64-linux-gnu && \
    ln -s /usr/lib/aarch64-linux-gnu/libssl.so /usr/aarch64-linux-gnu/ && \
    ln -s /usr/lib/aarch64-linux-gnu/libcrypto.so /usr/aarch64-linux-gnu/

# 安装 Rust 目标
RUN rustup target add "$(cat /target.txt)"

# 继续原来的构建步骤
COPY --from=planner /recipe.json /recipe.json
RUN RUSTFLAGS="$(cat /flags.txt)" \
    CC=aarch64-linux-gnu-gcc \
    cargo chef cook --target "$(cat /target.txt)" --release --recipe-path /recipe.json

COPY . .
RUN RUSTFLAGS="$(cat /flags.txt)" \
    CC=aarch64-linux-gnu-gcc \
    cargo build --target "$(cat /target.txt)" --release -p mail-server -p stalwart-cli
RUN mv "/build/target/$(cat /target.txt)/release" "/output"

FROM docker.io/debian:bookworm-slim
WORKDIR /opt/stalwart-mail
RUN export DEBIAN_FRONTEND=noninteractive && \
    apt-get update && \
    apt-get install -yq ca-certificates
COPY --from=builder /output/stalwart-mail /usr/local/bin
COPY --from=builder /output/stalwart-cli /usr/local/bin
COPY ./resources/docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod -R 755 /usr/local/bin
CMD ["/usr/local/bin/stalwart-mail"]
VOLUME [ "/opt/stalwart-mail" ]
EXPOSE	443 25 110 587 465 143 993 995 4190 8080
ENTRYPOINT ["/bin/sh", "/usr/local/bin/entrypoint.sh"]