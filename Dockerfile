# syntax=docker/dockerfile:1

FROM ubuntu:24.04 AS builder

ARG DEBIAN_FRONTEND=noninteractive
ARG LLVM_VERSION=19
ARG BUILD_TYPE=RelWithDebInfo
ARG BUILD_TARGET=clickhouse
ARG BUILD_JOBS=0
ARG ENABLE_TESTS=OFF
ARG ENABLE_UTILS=OFF
ARG ENABLE_RUST=OFF
ARG EXTRA_CMAKE_ARGS=""

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    software-properties-common \
    wget \
 && rm -rf /var/lib/apt/lists/*

RUN wget -O /tmp/llvm.sh https://apt.llvm.org/llvm.sh \
 && chmod +x /tmp/llvm.sh \
 && /tmp/llvm.sh "${LLVM_VERSION}" \
 && rm -f /tmp/llvm.sh

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    ccache \
    clang-"${LLVM_VERSION}" \
    cmake \
    gawk \
    git \
    lld-"${LLVM_VERSION}" \
    nasm \
    ninja-build \
    perl \
    pkg-config \
    python3 \
    yasm \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /src

# The build context is expected to already include initialized submodules.
COPY . .
COPY docker/build-clickhouse-image.sh /usr/local/bin/build-clickhouse-image.sh

RUN chmod +x /usr/local/bin/build-clickhouse-image.sh \
 && /bin/bash /usr/local/bin/build-clickhouse-image.sh

FROM ubuntu:24.04 AS runtime

ARG DEBIAN_FRONTEND=noninteractive
ARG CLICKHOUSE_UID=101
ARG CLICKHOUSE_GID=101
ARG IMAGE_SOURCE=""
ARG IMAGE_REVISION=""
ARG IMAGE_CREATED=""

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN groupadd -r clickhouse --gid="${CLICKHOUSE_GID}" \
 && useradd -r -g clickhouse --uid="${CLICKHOUSE_UID}" --home-dir=/var/lib/clickhouse --shell=/bin/bash clickhouse \
 && apt-get update \
 && apt-get install --yes --no-install-recommends \
    busybox \
    ca-certificates \
    locales \
    tzdata \
    wget \
 && busybox --install -s \
 && rm -rf /var/lib/apt/lists/* /var/cache/debconf /tmp/*

COPY --from=builder /src/build/programs/clickhouse /tmp/clickhouse_binary/clickhouse
COPY docker/server/entrypoint.sh /entrypoint.sh

RUN chmod +x /tmp/clickhouse_binary/clickhouse /entrypoint.sh \
 && /tmp/clickhouse_binary/clickhouse install --user clickhouse --group clickhouse \
 && rm -rf /tmp/clickhouse_binary \
 && mkdir -p /var/lib/clickhouse /var/log/clickhouse-server /etc/clickhouse-server /etc/clickhouse-client /docker-entrypoint-initdb.d \
 && chmod ugo+Xrw -R /var/lib/clickhouse /var/log/clickhouse-server /etc/clickhouse-server /etc/clickhouse-client \
 && clickhouse local -q "SELECT 1" >/dev/null

COPY docker/server/docker_related_config.xml /etc/clickhouse-server/config.d/docker_related_config.xml

RUN locale-gen en_US.UTF-8

LABEL org.opencontainers.image.title="ClickHouse" \
      org.opencontainers.image.description="ClickHouse built from source" \
      org.opencontainers.image.source="${IMAGE_SOURCE}" \
      org.opencontainers.image.revision="${IMAGE_REVISION}" \
      org.opencontainers.image.created="${IMAGE_CREATED}"

ENV LANG=en_US.UTF-8
ENV TZ=UTC
ENV CLICKHOUSE_CONFIG=/etc/clickhouse-server/config.xml

WORKDIR /var/lib/clickhouse

EXPOSE 8123 9000 9009
VOLUME /var/lib/clickhouse

ENTRYPOINT ["/entrypoint.sh"]
CMD []
