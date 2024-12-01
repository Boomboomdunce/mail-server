FROM --platform=$BUILDPLATFORM docker.io/lukemathwalker/cargo-chef:latest-rust-slim-bookworm AS chef
WORKDIR /build

FROM --platform=$BUILDPLATFORM chef AS planner
COPY . .
RUN cargo chef prepare --recipe-path /recipe.json

FROM --platform=$BUILDPLATFORM chef AS builder
ARG TARGETPLATFORM

# 设置目标架构和编译器标志
RUN case "${TARGETPLATFORM}" in \
    "linux/arm64") \
        echo "aarch64-unknown-linux-gnu" > /target.txt && \
        echo "aarch64-linux-gnu" > /arch.txt ;; \
    "linux/amd64") \
        echo "x86_64-unknown-linux-gnu" > /target.txt && \
        echo "x86-64-linux-gnu" > /arch.txt ;; \
    *) exit 1 ;; \
    esac

# 设置环境变量
ENV CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER=aarch64-linux-gnu-gcc \
    CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER=x86_64-linux-gnu-gcc \
    PKG_CONFIG_ALLOW_CROSS=1 \
    OPENSSL_NO_VENDOR=1 \
    OPENSSL_STATIC=1

# 安装基本依赖
RUN export DEBIAN_FRONTEND=noninteractive && \
    apt-get update && \
    apt-get install -yq \
        build-essential \
        pkg-config \
        libssl-dev \
        libclang-16-dev \
        gcc-aarch64-linux-gnu \
        g++-aarch64-linux-gnu \
        gcc-x86-64-linux-gnu \
        g++-x86-64-linux-gnu

# 为 ARM64 准备 OpenSSL
RUN case "${TARGETPLATFORM}" in \
    "linux/arm64") \
        dpkg --add-architecture arm64 && \
        apt-get update && \
        apt-get install -y --no-install-recommends \
            libssl-dev:arm64 \
            libc6-dev-arm64-cross && \
        mkdir -p /usr/aarch64-linux-gnu/lib && \
        ln -s /usr/lib/aarch64-linux-gnu/libssl.a /usr/aarch64-linux-gnu/lib/ && \
        ln -s /usr/lib/aarch64-linux-gnu/libcrypto.a /usr/aarch64-linux-gnu/lib/ && \
        echo "export PKG_CONFIG_PATH=/usr/lib/aarch64-linux-gnu/pkgconfig" >> /env && \
        echo "export OPENSSL_DIR=/usr" >> /env && \
        echo "export OPENSSL_LIB_DIR=/usr/lib/aarch64-linux-gnu" >> /env && \
        echo "export OPENSSL_INCLUDE_DIR=/usr/include" >> /env ;; \
    "linux/amd64") \
        echo "export PKG_CONFIG_PATH=/usr/lib/x86_64-linux-gnu/pkgconfig" >> /env && \
        echo "export OPENSSL_DIR=/usr" >> /env && \
        echo "export OPENSSL_LIB_DIR=/usr/lib/x86_64-linux-gnu" >> /env && \
        echo "export OPENSSL_INCLUDE_DIR=/usr/include" >> /env ;; \
    *) exit 1 ;; \
    esac

# 添加目标架构
RUN rustup target add "$(cat /target.txt)"

# 复制和构建依赖
COPY --from=planner /recipe.json /recipe.json
RUN . /env && RUSTFLAGS="-C linker=$(cat /arch.txt)-gcc" \
    cargo chef cook --target "$(cat /target.txt)" --release --recipe-path /recipe.json

# 复制源代码并构建
COPY . .
RUN . /env && RUSTFLAGS="-C linker=$(cat /arch.txt)-gcc" \
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