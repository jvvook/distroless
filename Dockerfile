# syntax=docker/dockerfile:1.4
ARG PYTHON_BRANCH=3.11

FROM clearlinux AS builder-base

RUN set -eux; \
    swupd update --no-boot-update; \
    swupd bundle-add mixer c-basic diffutils --no-boot-update;

FROM builder-base AS builder-repo

RUN set -eux; \
    source /usr/lib/os-release; \
    # Customize bundles
    mkdir /repo; \
    pushd /repo; \
    mixer init --no-default-bundles --mix-version "$VERSION_ID"; \
    mixer bundle add os-core; \
    mixer bundle edit os-core; \
    printf '\
glibc-lib-avx2\n\
libgcc1\n\
netbase-data\n\
tzdata-minimal\n\
' > local-bundles/os-core; \
#     mixer bundle add os-core-plus; \
#     mixer bundle edit os-core-plus; \
#     printf '\
# ncurses-data\n\
# ' > local-bundles/os-core-plus; \
    sed -i 's/os-core-update/os-core/' builder.conf; \
    mixer build all; \
    popd;

FROM builder-repo AS builder-core

RUN set -eux; \
    source /usr/lib/os-release; \
    # Install os-core
    mkdir /install_root; \
    swupd os-install --version "$VERSION_ID" \
                     --path /install_root \
                     --statedir /swupd-state \
                     --bundles os-core \
                     --no-boot-update \
                     --no-scripts \
                     --url file:///repo/update/www \
                     --certpath /repo/Swupd_Root.pem; \
    # Print contents
    find /install_root;

FROM builder-core AS builder-cc

RUN set -eux; \
    # Strip out unnecessary files
    find /install_root -name clear -exec rm -rv {} +; \
    find /install_root -name swupd -exec rm -rv {} +; \
    find /install_root -name package-licenses -exec rm -rv {} +; \
    rmdir /install_root/{autofs,boot,media,mnt,srv}; \
    # Add CA certs
    CLR_TRUST_STORE=certs clrtrust generate; \
    install -d /install_root/etc/ssl/certs; \
    install -D -m 644 certs/anchors/ca-certificates.crt /install_root/etc/ssl/certs/ca-certificates.crt; \
    # Create passwd/group files (from distroless, without staff)
    printf '\
root:x:0:0:root:/root:/sbin/nologin\n\
nobody:x:65534:65534:nobody:/nonexistent:/sbin/nologin\n\
nonroot:x:65532:65532:nonroot:/home/nonroot:/sbin/nologin\n\
' > /install_root/etc/passwd; \
    printf '\
root:x:0:\n\
nobody:x:65534:\n\
tty:x:5:\n\
nonroot:x:65532:\n\
' > /install_root/etc/group; \
    install -d -m 700 -g 65532 -o 65532 /install_root/home/nonroot; \
    # Print contents
    find /install_root; \
    cat /install_root/etc/passwd; \
    cat /install_root/etc/group; \
    cat /install_root/usr/lib/os-release;

FROM scratch AS cc-latest

COPY --link --from=builder-cc /install_root /
WORKDIR /root

FROM cc-latest AS cc-debug

COPY --link --from=busybox:musl /bin /bin/
CMD ["sh"]

FROM cc-latest AS cc-nonroot

USER nonroot
WORKDIR /home/nonroot

FROM cc-debug AS cc-debug-nonroot

USER nonroot
WORKDIR /home/nonroot

# Cache deps for multiple python versions (TBD)
FROM builder-base AS builder-python-deps

COPY --link --from=golang /usr/local/go /usr/local/go

RUN set -ex; \
    source /usr/share/defaults/etc/profile; \
    set -u; \
    mkdir /deps; \
    pushd /deps; \
    export CFLAGS="$CFLAGS -flto=auto"; \
    makeopts="-j$(cat /proc/cpuinfo | grep processor | wc -l)"; \
    # Install bzip2
    git clone --depth 1 https://sourceware.org/git/bzip2; \
    pushd bzip2; \
    make "$makeopts" install CFLAGS="$CFLAGS" LDFLAGS="${LDFLAGS:-}" PREFIX=/usr/local; \
    echo "$(basename "$(pwd)")=$(git rev-parse --short HEAD)" >> /revisions; \
    popd; \
    # Install zlib
    git clone --depth 1 https://github.com/cloudflare/zlib; \
    pushd zlib; \
    ./configure --static --prefix=/usr/local --libdir=/usr/local/lib64; \
    make "$makeopts" install; \
    echo "$(basename "$(pwd)")=$(git rev-parse --short HEAD)" >> /revisions; \
    popd; \
    # Install xz
    git clone --depth 1 https://github.com/tukaani-project/xz; \
    pushd xz; \
    ./autogen.sh --no-po4a; \
    ./configure --disable-shared --prefix=/usr/local \
                                 --libdir=/usr/local/lib64 \
                                 --disable-xz \
                                 --disable-xzdec \
                                 --disable-lzmadec \
                                 --disable-lzmainfo \
                                 --disable-lzma-links \
                                 --disable-scripts \
                                 --disable-doc; \
    make "$makeopts" install; \
    echo "$(basename "$(pwd)")=$(git rev-parse --short HEAD)" >> /revisions; \
    popd; \
    # Install libffi
    git clone --depth 1 https://github.com/libffi/libffi; \
    pushd libffi; \
    ./autogen.sh; \
    ./configure --disable-shared --prefix=/usr/local \
                                 --libdir=/usr/local/lib64 \
                                 --disable-multi-os-directory \
                                 --disable-docs; \
    make "$makeopts" install; \
    echo "$(basename "$(pwd)")=$(git rev-parse --short HEAD)" >> /revisions; \
    popd; \
    # Install boringssl
    git clone --depth 1 https://boringssl.googlesource.com/boringssl; \
    pushd boringssl; \
    mkdir build; \
    pushd build; \
    cmake .. -DCMAKE_INSTALL_PREFIX=/usr/local \
             -DCMAKE_BUILD_TYPE=Release \
             -DGO_EXECUTABLE=/usr/local/go/bin/go; \
    make "$makeopts" install; \
    popd; \
    echo "$(basename "$(pwd)")=$(git rev-parse --short HEAD)" >> /revisions; \
    popd; \
    # Install libuuid
    git clone --depth 1 https://git.kernel.org/pub/scm/utils/util-linux/util-linux libuuid; \
    pushd libuuid; \
    ./autogen.sh; \
    ./configure --disable-shared --prefix=/usr/local \
                                 --libdir=/usr/local/lib64 \
                                 --disable-all-programs \
                                 --enable-libuuid; \
    make "$makeopts" install; \
    echo "$(basename "$(pwd)")=$(git rev-parse --short HEAD)" >> /revisions; \
    popd; \
    # Print contents
    popd; \
    rm -r /usr/local/go /deps; \
    find /usr/local; \
    cat /revisions;

FROM builder-python-deps AS builder-python

ARG PYTHON_BRANCH

RUN set -ex; \
    source /usr/share/defaults/etc/profile; \
    set -u; \
    export CFLAGS="$CFLAGS -flto=auto"; \
    makeopts="-j$(cat /proc/cpuinfo | grep processor | wc -l)"; \
    # Install python
    mkdir /python_root; \
    git clone --depth 1 --branch "$PYTHON_BRANCH" https://github.com/python/cpython python; \
    pushd python; \
    ./configure --prefix=/usr/local \
                --with-pkg-config=yes \
                --enable-optimizations \
                --with-lto \
                --without-static-libpython \
                --without-readline \
                --with-ensurepip=no \
                --disable-test-modules; \
    make "$makeopts" install DESTDIR=/python_root; \
    echo "$(basename "$(pwd)")=$(git rev-parse --short HEAD)" >> /revisions; \
    popd; \
    # Strip python, static?
    strip /usr/local/bin/python3; \
    # Print contents
    popd; \
    find /python_root; \
    cat /revisions;
