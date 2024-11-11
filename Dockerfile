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
    "linux/arm64") echo "aarch64-unknown-linux-musl" > /target.txt ;; \
    "linux/amd64") echo "x86_64-unknown-linux-musl" > /target.txt ;; \
    *) exit 1 ;; \
    esac

# 安装基础依赖
RUN apt-get update && \
    apt-get install -y \
    build-essential \
    musl-tools \
    wget \
    pkg-config \
    cmake

# 下载并编译 musl 交叉编译工具链
RUN wget https://musl.cc/aarch64-linux-musl-cross.tgz && \
    tar -xf aarch64-linux-musl-cross.tgz -C /opt && \
    rm aarch64-linux-musl-cross.tgz

# 下载并编译 OpenSSL
RUN wget https://www.openssl.org/source/openssl-1.1.1w.tar.gz && \
    tar -xf openssl-1.1.1w.tar.gz && \
    cd openssl-1.1.1w && \
    case "$(cat /target.txt)" in \
        "aarch64-unknown-linux-musl") \
            CC=/opt/aarch64-linux-musl-cross/bin/aarch64-linux-musl-gcc \
            ./Configure linux-aarch64 --prefix=/usr/local/musl \
            enable-pkgconfig \
            no-shared \
            no-async \
            no-engine \
            ;; \
        "x86_64-unknown-linux-musl") \
            CC=musl-gcc \
            ./Configure linux-x86_64 --prefix=/usr/local/musl \
            enable-pkgconfig \
            no-shared \
            no-async \
            no-engine \
            ;; \
    esac && \
    make -j$(nproc) && \
    make install_sw

# 设置环境变量
ENV PATH="/opt/aarch64-linux-musl-cross/bin:$PATH" \
    PKG_CONFIG_ALLOW_CROSS=1 \
    PKG_CONFIG_PATH=/usr/local/musl/lib/pkgconfig \
    PKG_CONFIG_SYSROOT_DIR=/usr/local/musl \
    OPENSSL_STATIC=1 \
    OPENSSL_DIR=/usr/local/musl \
    OPENSSL_INCLUDE_DIR=/usr/local/musl/include \
    OPENSSL_LIB_DIR=/usr/local/musl/lib \
    AARCH64_UNKNOWN_LINUX_MUSL_OPENSSL_DIR=/usr/local/musl \
    AARCH64_UNKNOWN_LINUX_MUSL_OPENSSL_INCLUDE_DIR=/usr/local/musl/include \
    AARCH64_UNKNOWN_LINUX_MUSL_OPENSSL_LIB_DIR=/usr/local/musl/lib \
    CC_aarch64_unknown_linux_musl=/opt/aarch64-linux-musl-cross/bin/aarch64-linux-musl-gcc \
    AR_aarch64_unknown_linux_musl=/opt/aarch64-linux-musl-cross/bin/aarch64-linux-musl-ar \
    CARGO_TARGET_AARCH64_UNKNOWN_LINUX_MUSL_LINKER=/opt/aarch64-linux-musl-cross/bin/aarch64-linux-musl-gcc

# 安装 Rust 目标
RUN rustup target add "$(cat /target.txt)"

# 继续构建步骤
COPY --from=planner /recipe.json /recipe.json
RUN cargo chef cook --target "$(cat /target.txt)" --release --recipe-path /recipe.json

COPY . .
RUN cargo build --target "$(cat /target.txt)" --release -p mail-server -p stalwart-cli
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