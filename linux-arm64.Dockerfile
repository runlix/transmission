# Builder tag from VERSION.json builder.tag (e.g., "bookworm-slim")
ARG BUILDER_TAG=bookworm-slim
# Base tag (variant-arch) from VERSION.json base.tag (e.g., "release-2025.12.29.1-linux-arm64-latest")
ARG BASE_TAG=release-2025.12.29.1-linux-arm64-latest
# Selected digests (build script will set based on target configuration)
# Default to empty string - build script should always provide valid digests
# If empty, FROM will fail (which is desired to enforce digest pinning)
ARG BUILDER_DIGEST=""
ARG BASE_DIGEST=""
# Package URL from VERSION.json package_url
ARG PACKAGE_URL=""
# unrar version - source available at https://www.rarlab.com/rar_add.htm
ARG UNRAR_VERSION=7.2.3

# STAGE 1 — fetch Transmission source
# Build script will pass BUILDER_TAG and BUILDER_DIGEST from VERSION.json
# Format: debian:bookworm-slim@sha256:digest (when digest provided)
FROM docker.io/library/debian:${BUILDER_TAG}@${BUILDER_DIGEST} AS fetch

# Redeclare ARG in this stage so it's available for use in RUN commands
ARG PACKAGE_URL

WORKDIR /app

# Use BuildKit cache mounts to persist apt cache between builds
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

# STAGE 2 — build Transmission and dependencies
# Build script will pass BUILDER_TAG and BUILDER_DIGEST from VERSION.json
FROM docker.io/library/debian:${BUILDER_TAG}@${BUILDER_DIGEST} AS transmission-deps

ARG UNRAR_VERSION

# Use BuildKit cache mounts to persist apt cache between builds
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

# Build unrar from source
# Source available at https://www.rarlab.com/rar_add.htm
WORKDIR /tmp
RUN curl -fsSL "https://www.rarlab.com/rar/unrarsrc-${UNRAR_VERSION}.tar.gz" -o unrar.tar.gz \
 && tar -xzf unrar.tar.gz \
 && cd unrar \
 && make -f makefile \
 && cp unrar /usr/local/bin/unrar \
 && chmod +x /usr/local/bin/unrar \
 && cd /tmp \
 && rm -rf unrar unrar.tar.gz

# Build transmission from source
# Copy source from fetch stage
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

# Copy web UI files from source tree (CMake install may not install them to expected location)
RUN mkdir -p /usr/local/share/transmission && \
    cp -r /tmp/transmission/web /usr/local/share/transmission/web

# Identify library dependencies using ldd
# #region agent log - Debug: Check all library dependencies including transitive ones
RUN ldd /usr/local/bin/transmission-daemon > /tmp/transmission_deps.txt 2>&1 || true && \
    ldd /usr/local/bin/transmission-cli >> /tmp/transmission_deps.txt 2>&1 || true && \
    ldd /usr/local/bin/transmission-remote >> /tmp/transmission_deps.txt 2>&1 || true && \
    echo "=== Transmission library dependencies ===" && \
    cat /tmp/transmission_deps.txt && \
    echo "=== Checking libcurl dependencies ===" && \
    ldd /usr/lib/aarch64-linux-gnu/libcurl.so.4 > /tmp/libcurl_deps.txt 2>&1 || true && \
    cat /tmp/libcurl_deps.txt && \
    echo "=== Checking librtmp dependencies ===" && \
    (ldd /usr/lib/aarch64-linux-gnu/librtmp.so.1 > /tmp/librtmp_deps.txt 2>&1 || true) && \
    cat /tmp/librtmp_deps.txt && \
    echo "=== Finding all nghttp2 libraries ===" && \
    find /usr/lib -name "*nghttp2*" -type f 2>/dev/null | head -10 && \
    echo "=== Finding all librtmp libraries ===" && \
    find /usr/lib -name "*rtmp*" -type f 2>/dev/null | head -10 && \
    echo "=== Finding all libssh2 libraries ===" && \
    find /usr/lib -name "*ssh2*" -type f 2>/dev/null | head -10 && \
    echo "=== Finding all libpsl libraries ===" && \
    find /usr/lib -name "*psl*" -type f 2>/dev/null | head -10 && \
    echo "=== Finding all libgssapi_krb5 libraries ===" && \
    find /usr/lib -name "*gssapi*" -type f 2>/dev/null | head -10 && \
    echo "=== Finding all krb5 libraries ===" && \
    find /usr/lib -name "*krb5*" -type f 2>/dev/null | head -10 && \
    echo "=== Finding all libldap libraries ===" && \
    find /usr/lib -name "*ldap*" -type f 2>/dev/null | head -10 && \
    echo "=== Finding all liblber libraries ===" && \
    find /usr/lib -name "*lber*" -type f 2>/dev/null | head -10 && \
    echo "=== All unique library paths from ldd ===" && \
    (ldd /usr/local/bin/transmission-daemon 2>&1 | grep "=>" | awk '{print $3}' | sort -u > /tmp/all_libs.txt || true) && \
    (ldd /usr/lib/aarch64-linux-gnu/libcurl.so.4 2>&1 | grep "=>" | awk '{print $3}' | sort -u >> /tmp/all_libs.txt || true) && \
    (ldd /usr/lib/aarch64-linux-gnu/librtmp.so.1 2>&1 | grep "=>" | awk '{print $3}' | sort -u >> /tmp/all_libs.txt || true) && \
    (ldd /usr/lib/aarch64-linux-gnu/libssh2.so.1 2>&1 | grep "=>" | awk '{print $3}' | sort -u >> /tmp/all_libs.txt || true) && \
    (ldd /usr/lib/aarch64-linux-gnu/libpsl.so.5 2>&1 | grep "=>" | awk '{print $3}' | sort -u >> /tmp/all_libs.txt || true) && \
    (ldd /usr/lib/aarch64-linux-gnu/libgssapi_krb5.so.2 2>&1 | grep "=>" | awk '{print $3}' | sort -u >> /tmp/all_libs.txt || true) && \
    (ldd /usr/lib/aarch64-linux-gnu/libldap-2.5.so.0 2>&1 | grep "=>" | awk '{print $3}' | sort -u >> /tmp/all_libs.txt || true) && \
    (ldd /usr/lib/aarch64-linux-gnu/liblber-2.5.so.0 2>&1 | grep "=>" | awk '{print $3}' | sort -u >> /tmp/all_libs.txt || true) && \
    sort -u /tmp/all_libs.txt > /tmp/unique_libs.txt && \
    echo "=== All unique libraries needed ===" && \
    cat /tmp/unique_libs.txt
# #endregion agent log

# STAGE 3 — distroless final image
# Build script will pass BASE_TAG (from VERSION.json base.tag) and BASE_DIGEST
# Format: ghcr.io/runlix/distroless-runtime:release-2025.12.29.1-linux-arm64-latest@sha256:digest (when digest provided)
FROM ghcr.io/runlix/distroless-runtime:${BASE_TAG}@${BASE_DIGEST}

# Hardcoded for arm64 - no conditionals needed!
ARG LIB_DIR=aarch64-linux-gnu
ARG LD_SO=ld-linux-aarch64.so.1

# Copy transmission binaries
COPY --from=transmission-deps /usr/local/bin/transmission-daemon /usr/local/bin/transmission-daemon
COPY --from=transmission-deps /usr/local/bin/transmission-cli /usr/local/bin/transmission-cli
COPY --from=transmission-deps /usr/local/bin/transmission-remote /usr/local/bin/transmission-remote

# Copy transmission web UI files
COPY --from=transmission-deps /usr/local/share/transmission/web /usr/local/share/transmission/web

# Copy unrar binary
COPY --from=transmission-deps /usr/local/bin/unrar /usr/local/bin/unrar

# Copy utilities
COPY --from=transmission-deps /usr/bin/find /usr/bin/find
COPY --from=transmission-deps /usr/bin/7za /usr/bin/7za

# Copy required shared libraries - combined into fewer layers by grouping related libraries
# libcurl libraries
COPY --from=transmission-deps /usr/lib/${LIB_DIR}/libcurl.so.* /usr/lib/${LIB_DIR}/
# libnghttp2 (transitive dependency of libcurl for HTTP/2 support)
COPY --from=transmission-deps /usr/lib/${LIB_DIR}/libnghttp2.so.* /usr/lib/${LIB_DIR}/
# librtmp (transitive dependency of libcurl for RTMP support)
COPY --from=transmission-deps /usr/lib/${LIB_DIR}/librtmp.so.* /usr/lib/${LIB_DIR}/
# libssh2 (transitive dependency of libcurl for SSH/SFTP support)
COPY --from=transmission-deps /usr/lib/${LIB_DIR}/libssh2.so.* /usr/lib/${LIB_DIR}/
# libpsl (transitive dependency of libcurl for Public Suffix List support)
COPY --from=transmission-deps /usr/lib/${LIB_DIR}/libpsl.so.* /usr/lib/${LIB_DIR}/
# libgssapi_krb5 (transitive dependency of libcurl for Kerberos/GSSAPI support)
COPY --from=transmission-deps /usr/lib/${LIB_DIR}/libgssapi_krb5.so.* /usr/lib/${LIB_DIR}/
# libldap (transitive dependency of libcurl for LDAP support)
COPY --from=transmission-deps /usr/lib/${LIB_DIR}/libldap-*.so.* /usr/lib/${LIB_DIR}/
# liblber (transitive dependency of libldap for LDAP Basic Encoding Rules)
COPY --from=transmission-deps /usr/lib/${LIB_DIR}/liblber-*.so.* /usr/lib/${LIB_DIR}/
# libevent libraries
COPY --from=transmission-deps /usr/lib/${LIB_DIR}/libevent-*.so.* /usr/lib/${LIB_DIR}/
COPY --from=transmission-deps /usr/lib/${LIB_DIR}/libevent_pthreads-*.so.* /usr/lib/${LIB_DIR}/
# zlib libraries
COPY --from=transmission-deps /usr/lib/${LIB_DIR}/libz.so.* /usr/lib/${LIB_DIR}/
# libminiupnpc libraries
COPY --from=transmission-deps /usr/lib/${LIB_DIR}/libminiupnpc.so.* /usr/lib/${LIB_DIR}/

WORKDIR /config
USER 65532:65532
ENTRYPOINT ["/usr/local/bin/transmission-daemon", "--foreground", "--config-dir", "/config"]

