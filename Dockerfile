# Stalwart Dockerfile
# Credits: https://github.com/33KK 

FROM --platform=$BUILDPLATFORM docker.io/lukemathwalker/cargo-chef:latest-rust-slim-bookworm AS chef
WORKDIR /build

FROM --platform=$BUILDPLATFORM chef AS planner
COPY . .
RUN cargo chef prepare --recipe-path /recipe.json

FROM --platform=$BUILDPLATFORM chef AS builder
ARG TARGETPLATFORM
RUN case "${TARGETPLATFORM}" in \
    "linux/arm64") echo "aarch64-unknown-linux-gnu" > /target.txt && echo "-C linker=aarch64-linux-gnu-gcc" > /flags.txt ;; \
    "linux/amd64") echo "x86_64-unknown-linux-gnu" > /target.txt && echo "-C linker=x86_64-linux-gnu-gcc" > /flags.txt ;; \
    *) exit 1 ;; \
    esac

# 安装基本依赖
RUN export DEBIAN_FRONTEND=noninteractive && \
    apt-get update && \
    apt-get install -yq build-essential libclang-16-dev pkg-config openssl libssl-dev

# 根据目标平台安装特定的编译工具
RUN case "${TARGETPLATFORM}" in \
    "linux/arm64") \
        apt-get install -yq g++-aarch64-linux-gnu binutils-aarch64-linux-gnu && \
        mkdir -p /usr/aarch64-linux-gnu && \
        ln -s /usr/include/aarch64-linux-gnu/openssl /usr/include/openssl ;; \
    "linux/amd64") \
        apt-get install -yq g++-x86-64-linux-gnu binutils-x86-64-linux-gnu ;; \
    *) exit 1 ;; \
    esac

RUN rustup target add "$(cat /target.txt)"
COPY --from=planner /recipe.json /recipe.json

# 设置持久的环境变量
ENV PKG_CONFIG_ALLOW_CROSS=1
ENV OPENSSL_NO_VENDOR=1
RUN case "${TARGETPLATFORM}" in \
    "linux/arm64") \
        echo "export PKG_CONFIG_PATH=/usr/lib/aarch64-linux-gnu/pkgconfig" >> /etc/environment && \
        echo "export OPENSSL_DIR=/usr" >> /etc/environment && \
        echo "export OPENSSL_LIB_DIR=/usr/lib/aarch64-linux-gnu" >> /etc/environment && \
        echo "export OPENSSL_INCLUDE_DIR=/usr/include/openssl" >> /etc/environment ;; \
    "linux/amd64") \
        echo "export PKG_CONFIG_PATH=/usr/lib/x86_64-linux-gnu/pkgconfig" >> /etc/environment && \
        echo "export OPENSSL_DIR=/usr" >> /etc/environment && \
        echo "export OPENSSL_LIB_DIR=/usr/lib/x86_64-linux-gnu" >> /etc/environment && \
        echo "export OPENSSL_INCLUDE_DIR=/usr/include/openssl" >> /etc/environment ;; \
    *) exit 1 ;; \
    esac

# 使用 shell 包装命令以确保环境变量生效
RUN echo '#!/bin/sh' > /build.sh && \
    echo 'set -e' >> /build.sh && \
    echo 'source /etc/environment' >> /build.sh && \
    echo 'RUSTFLAGS="$(cat /flags.txt)" cargo chef cook --target "$(cat /target.txt)" --release --recipe-path /recipe.json' >> /build.sh && \
    chmod +x /build.sh

RUN /build.sh

COPY . .
RUN echo '#!/bin/sh' > /build-final.sh && \
    echo 'set -e' >> /build-final.sh && \
    echo 'source /etc/environment' >> /build-final.sh && \
    echo 'RUSTFLAGS="$(cat /flags.txt)" cargo build --target "$(cat /target.txt)" --release -p mail-server -p stalwart-cli' >> /build-final.sh && \
    chmod +x /build-final.sh

RUN /build-final.sh
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