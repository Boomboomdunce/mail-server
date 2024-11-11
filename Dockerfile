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
RUN export DEBIAN_FRONTEND=noninteractive
RUN apt-get update -y
RUN apt-get install -yq
RUN apt-get install -y build-essential
RUN apt-get install -y libclang-16-dev
RUN apt-get install -y g++-aarch64-linux-gnu
RUN apt-get install -y binutils-aarch64-linux-gnu
RUN apt-get install -y g++-x86-64-linux-gnu
RUN apt-get install -y binutils-x86-64-linux-gnu
RUN apt-get install -y pkg-config
RUN apt-get install -y libssl-dev
RUN apt-get install -y openssl
RUN apt-get install -y musl-tools
# 添加交叉编译所需的 SSL 开发包
RUN apt-get install -y gcc-aarch64-linux-gnu

# 设置 OpenSSL 相关环境变量
ENV OPENSSL_DIR=/usr/include/openssl \
    PKG_CONFIG_ALLOW_CROSS=1 \
    OPENSSL_INCLUDE_DIR=/usr/include \
    OPENSSL_LIB_DIR=/usr/lib

RUN rustup target add "$(cat /target.txt)"
COPY --from=planner /recipe.json /recipe.json
RUN RUSTFLAGS="$(cat /flags.txt)" cargo chef cook --target "$(cat /target.txt)" --release --recipe-path /recipe.json
COPY . .
RUN RUSTFLAGS="$(cat /flags.txt)" cargo build --target "$(cat /target.txt)" --release -p mail-server -p stalwart-cli
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
