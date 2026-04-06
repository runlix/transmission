ARG BUILDER_REF="docker.io/library/debian:bookworm-slim@sha256:8af0e5095f9964007f5ebd11191dfe52dcb51bf3afa2c07f055fc5451b78ba0e"
ARG BASE_REF="ghcr.io/runlix/distroless-runtime-v2-canary:stable@sha256:6f96f11dbb9d8f6e76672e73bbf743dbec36d2e4f6d29250151a48379a8c66dd"
ARG PACKAGE_URL="https://github.com/transmission/transmission/releases/download/4.1.1/transmission-4.1.1.tar.xz"
ARG UNRAR_VERSION=7.2.3

FROM ${BUILDER_REF} AS fetch

ARG PACKAGE_URL

WORKDIR /app

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    tar \
    xz-utils \
 && rm -rf /var/lib/apt/lists/* \
 && mkdir -p /app/transmission \
 && curl -L -f "${PACKAGE_URL}" -o transmission.tar.xz \
 && tar -xJf transmission.tar.xz -C /app/transmission --strip-components=1 \
 && chmod -R u=rwX,go=rX /app/transmission \
 && rm transmission.tar.xz

FROM ${BUILDER_REF} AS transmission-deps

ARG UNRAR_VERSION

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    cmake \
    build-essential \
    gcc \
    g++ \
    make \
    pkg-config \
    libcurl4-openssl-dev \
    libevent-dev \
    libssl-dev \
    zlib1g-dev \
    libminiupnpc-dev \
    libcurl4 \
    libevent-2.1-7 \
    findutils \
    p7zip-full \
    autoconf \
    automake \
    libtool \
    curl \
    tar \
    python3 \
&& rm -rf /var/lib/apt/lists/*

WORKDIR /tmp
RUN curl -fsSL "https://www.rarlab.com/rar/unrarsrc-${UNRAR_VERSION}.tar.gz" -o unrar.tar.gz \
 && tar -xzf unrar.tar.gz \
 && cd unrar \
 && make -f makefile \
 && cp unrar /usr/local/bin/unrar \
 && chmod +x /usr/local/bin/unrar \
 && cd /tmp \
 && rm -rf unrar unrar.tar.gz

COPY --from=fetch /app/transmission /tmp/transmission

WORKDIR /tmp/transmission
RUN cmake -B build \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr/local \
    -DENABLE_QT=OFF \
    -DENABLE_GTK=OFF \
    -DENABLE_CLI=ON \
    -DENABLE_DAEMON=ON \
    -DENABLE_WEB=ON \
 && cmake --build build \
 && cmake --install build --prefix /usr/local

RUN mkdir -p /usr/local/share/transmission/public_html && \
    cp -r /tmp/transmission/web/* /usr/local/share/transmission/public_html/

FROM ${BASE_REF}

ARG LIB_DIR=x86_64-linux-gnu

COPY --from=transmission-deps /usr/local/bin/transmission-daemon /usr/local/bin/transmission-daemon
COPY --from=transmission-deps /usr/local/bin/transmission-cli /usr/local/bin/transmission-cli
COPY --from=transmission-deps /usr/local/bin/transmission-remote /usr/local/bin/transmission-remote

COPY --from=transmission-deps /usr/local/share/transmission/public_html /usr/share/transmission/public_html

COPY --from=transmission-deps /usr/local/bin/unrar /usr/local/bin/unrar

COPY --from=transmission-deps /usr/bin/find /usr/bin/find
COPY --from=transmission-deps /usr/bin/7za /usr/bin/7za

COPY --from=transmission-deps /usr/lib/${LIB_DIR}/libcurl.so.* /usr/lib/${LIB_DIR}/
COPY --from=transmission-deps /usr/lib/${LIB_DIR}/libnghttp2.so.* /usr/lib/${LIB_DIR}/
COPY --from=transmission-deps /usr/lib/${LIB_DIR}/librtmp.so.* /usr/lib/${LIB_DIR}/
COPY --from=transmission-deps /usr/lib/${LIB_DIR}/libssh2.so.* /usr/lib/${LIB_DIR}/
COPY --from=transmission-deps /usr/lib/${LIB_DIR}/libpsl.so.* /usr/lib/${LIB_DIR}/
COPY --from=transmission-deps /usr/lib/${LIB_DIR}/libgssapi_krb5.so.* /usr/lib/${LIB_DIR}/
COPY --from=transmission-deps /usr/lib/${LIB_DIR}/libkrb5.so.* /usr/lib/${LIB_DIR}/
COPY --from=transmission-deps /usr/lib/${LIB_DIR}/libk5crypto.so.* /usr/lib/${LIB_DIR}/
COPY --from=transmission-deps /usr/lib/${LIB_DIR}/libkrb5support.so.* /usr/lib/${LIB_DIR}/
COPY --from=transmission-deps /usr/lib/${LIB_DIR}/libldap-*.so.* /usr/lib/${LIB_DIR}/
COPY --from=transmission-deps /usr/lib/${LIB_DIR}/liblber-*.so.* /usr/lib/${LIB_DIR}/
COPY --from=transmission-deps /usr/lib/${LIB_DIR}/libbrotlidec.so.* /usr/lib/${LIB_DIR}/
COPY --from=transmission-deps /usr/lib/${LIB_DIR}/libbrotlicommon.so.* /usr/lib/${LIB_DIR}/
COPY --from=transmission-deps /usr/lib/${LIB_DIR}/libcom_err.so.* /usr/lib/${LIB_DIR}/
COPY --from=transmission-deps /usr/lib/${LIB_DIR}/libidn2.so.* /usr/lib/${LIB_DIR}/
COPY --from=transmission-deps /usr/lib/${LIB_DIR}/libunistring.so.* /usr/lib/${LIB_DIR}/
COPY --from=transmission-deps /usr/lib/${LIB_DIR}/libkeyutils.so.* /usr/lib/${LIB_DIR}/
COPY --from=transmission-deps /usr/lib/${LIB_DIR}/libsasl2.so.* /usr/lib/${LIB_DIR}/
COPY --from=transmission-deps /usr/lib/${LIB_DIR}/libzstd.so.* /usr/lib/${LIB_DIR}/
COPY --from=transmission-deps /usr/lib/${LIB_DIR}/libgnutls.so.* /usr/lib/${LIB_DIR}/
COPY --from=transmission-deps /usr/lib/${LIB_DIR}/libnettle.so.* /usr/lib/${LIB_DIR}/
COPY --from=transmission-deps /usr/lib/${LIB_DIR}/libhogweed.so.* /usr/lib/${LIB_DIR}/
COPY --from=transmission-deps /usr/lib/${LIB_DIR}/libgmp.so.* /usr/lib/${LIB_DIR}/
COPY --from=transmission-deps /usr/lib/${LIB_DIR}/libp11-kit.so.* /usr/lib/${LIB_DIR}/
COPY --from=transmission-deps /usr/lib/${LIB_DIR}/libtasn1.so.* /usr/lib/${LIB_DIR}/
COPY --from=transmission-deps /usr/lib/${LIB_DIR}/libffi.so.* /usr/lib/${LIB_DIR}/
COPY --from=transmission-deps /usr/lib/${LIB_DIR}/libevent-*.so.* /usr/lib/${LIB_DIR}/
COPY --from=transmission-deps /usr/lib/${LIB_DIR}/libevent_pthreads-*.so.* /usr/lib/${LIB_DIR}/
COPY --from=transmission-deps /usr/lib/${LIB_DIR}/libz.so.* /usr/lib/${LIB_DIR}/
COPY --from=transmission-deps /usr/lib/${LIB_DIR}/libminiupnpc.so.* /usr/lib/${LIB_DIR}/

WORKDIR /config
USER 65532:65532
ENTRYPOINT ["/usr/local/bin/transmission-daemon", "--foreground", "--config-dir", "/config"]
