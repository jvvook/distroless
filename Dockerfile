# syntax=docker/dockerfile:1.4
ARG PYTHON_BRANCH=3.11

FROM clearlinux AS builder-base

RUN set -eux; \
    swupd update --no-boot-update; \
    swupd bundle-add mixer c-basic diffutils patch --no-boot-update;

FROM builder-base AS builder-cc

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
#tzdata-minimal\n\
tzdata\n\
' > local-bundles/os-core; \
    mixer bundle add os-core-plus; \
    mixer bundle edit os-core-plus; \
    printf '\
libstdc++\n\
' > local-bundles/os-core-plus; \
    sed -i 's/os-core-update/os-core/' builder.conf; \
    cat builder.conf; \
    mixer build all; \
    popd; \
    # Install base OS
    mkdir /cc_root; \
    swupd os-install --version "$VERSION_ID" \
                     --path /cc_root \
                     --statedir /swupd-state \
                     --bundles os-core \
                     --no-boot-update \
                     --no-scripts \
                     --url file:///repo/update/www \
                     --certpath /repo/Swupd_Root.pem; \
    mkdir /py_root_plus; \
    swupd os-install --version "$VERSION_ID" \
                     --path /py_root_plus \
                     --statedir /swupd-state \
                     --bundles os-core,os-core-plus \
                     --no-boot-update \
                     --no-scripts \
                     --url file:///repo/update/www \
                     --certpath /repo/Swupd_Root.pem; \
    # Retain only differences
    find /py_root_plus -name os-core-plus -delete; \
    pushd /cc_root; \
    find . -depth -exec rm -d '/py_root_plus/{}' \;; \
    popd; \
    # Strip out unnecessary files
    set +x; before="$(set +x; find /cc_root)"; set -x; \
    find /cc_root -depth \
        \( \
            -name clear \
         -o -name swupd \
         -o -name package-licenses \
        \) -exec rm -rv '{}' +; \
    rmdir -v /cc_root/{autofs,boot,media,mnt,srv}; \
    # Add CA certs
    CLR_TRUST_STORE=/certs clrtrust generate; \
    install -Dvm644 /certs/anchors/ca-certificates.crt /cc_root/etc/ssl/certs/ca-certificates.crt; \
    # Create passwd/group files (no staff)
    printf '\
root:x:0:0:root:/root:/sbin/nologin\n\
nobody:x:65534:65534:nobody:/nonexistent:/sbin/nologin\n\
nonroot:x:54321:54321:nonroot:/home/nonroot:/sbin/nologin\n\
' > /cc_root/etc/passwd; \
    printf '\
root:x:0:\n\
nobody:x:65534:\n\
tty:x:5:\n\
nonroot:x:54321:\n\
' > /cc_root/etc/group; \
    install -dvm700 -g54321 -o54321 /cc_root/home/nonroot; \
    set +x; after="$(find /cc_root)"; set -x; \
    # Print contents
    diff <(set +x; echo "$before") <(set +x; echo "$after") || true; \
    find /cc_root; \
    find /py_root_plus;

FROM scratch AS cc-latest

COPY --link --from=builder-cc /cc_root/ /
ENV LANG=C.UTF-8

FROM cc-latest AS cc-debug

COPY --link --from=busybox:musl /bin/ /bin/
CMD ["sh"]

FROM cc-latest AS cc-nonroot

USER nonroot
WORKDIR /home/nonroot

FROM cc-debug AS cc-debug-nonroot

USER nonroot
WORKDIR /home/nonroot

FROM builder-base AS builder-py-deps

RUN set -ex; \
    source /usr/share/defaults/etc/profile; \
    set -u; \
    mkdir /deps; \
    pushd /deps; \
    export CFLAGS="$CFLAGS -flto=auto"; \
    makeopts="-j$(cat /proc/cpuinfo | grep processor | wc -l)"; \
    # Install zlib (cloudflare fork)
    git clone --depth 1 https://github.com/cloudflare/zlib; \
    pushd zlib; \
    ./configure --static \
                --libdir=/usr/local/lib64; \
    make "$makeopts" check install; \
    echo "$(basename "$(pwd)")_rev=$(git rev-parse --short HEAD)" >> /revisions; \
    popd; \
    # Install bzip2
    git clone --depth 1 https://sourceware.org/git/bzip2; \
    pushd bzip2; \
    make "$makeopts" check CFLAGS="$CFLAGS" LDFLAGS="${LDFLAGS:-}"; \
    install -vm644 bzlib.h /usr/local/include; \
    install -vm644 libbz2.a /usr/local/lib64; \
    printf "\
prefix=/usr/local\n\
exec_prefix=\${prefix}\n\
libdir=\${exec_prefix}/lib64\n\
includedir=\${prefix}/include\n\n\
Name: bzip2\n\
Description: A file compression library\n\
Version: $(grep '^DISTNAME=' Makefile | cut -d- -f2)\n\
Libs: -L\${libdir} -lbz2\n\
Cflags: -I\${includedir}\n\
" > /usr/local/lib64/pkgconfig/bzip2.pc; \
    echo "$(basename "$(pwd)")_rev=$(git rev-parse --short HEAD)" >> /revisions; \
    popd; \
    # Install xz
    git clone --depth 1 https://github.com/tukaani-project/xz; \
    pushd xz; \
    ./autogen.sh --no-po4a; \
    ./configure --disable-shared \
                --libdir=/usr/local/lib64 \
                --disable-xz \
                --disable-xzdec \
                --disable-lzmadec \
                --disable-lzmainfo \
                --disable-lzma-links \
                --disable-scripts \
                --disable-doc; \
    make "$makeopts" check install; \
    echo "$(basename "$(pwd)")_rev=$(git rev-parse --short HEAD)" >> /revisions; \
    popd; \
    # Install libffi
    git clone --depth 1 https://github.com/libffi/libffi; \
    pushd libffi; \
    ./autogen.sh; \
    ./configure --disable-shared \
                --libdir=/usr/local/lib64 \
                --disable-multi-os-directory \
                --disable-docs; \
    make "$makeopts" check install; \
    echo "$(basename "$(pwd)")_rev=$(git rev-parse --short HEAD)" >> /revisions; \
    popd; \
    # Install libuuid
    git clone --depth 1 https://git.kernel.org/pub/scm/utils/util-linux/util-linux libuuid; \
    pushd libuuid; \
    ./autogen.sh; \
    ./configure --disable-shared \
                --libdir=/usr/local/lib64 \
                --disable-all-programs \
                --enable-libuuid; \
    make "$makeopts" check install; \
    echo "$(basename "$(pwd)")_rev=$(git rev-parse --short HEAD)" >> /revisions; \
    popd; \
    # Install libressl
    git clone --depth 1 https://github.com/libressl/portable libressl \
    pushd libressl; \
    ./autogen.sh; \
    ./configure --disable-shared \
                --libdir=/usr/local/lib64 \
                --with-openssldir=/etc/ssl; \
    make "$makeopts" check install; \
    echo "$(basename "$(pwd)")_rev=$(git rev-parse --short HEAD)" >> /revisions; \
    popd; \
    popd; \
    # Print contents
    rm -rv /usr/local/share; \
    find /usr/local;

FROM builder-py-deps AS builder-py

ARG PYTHON_BRANCH

RUN set -ex; \
    source /usr/share/defaults/etc/profile; \
    set -u; \
    export LDFLAGS="${LDFLAGS:-} -Wl,--strip-all"; \
    makeopts="-j$(cat /proc/cpuinfo | grep processor | wc -l)"; \
    # Install python
    mkdir /py_root; \
    git clone --depth 1 --branch "$PYTHON_BRANCH" https://github.com/python/cpython python; \
    pushd python; \
    # Might not be needed in 3.12
    sed -i 's/^#@MODULE__CTYPES_TRUE@\(.*\)/\1 -lffi/' Modules/Setup.stdlib.in; \
    # Build test modules as shared libraries
    sed -i '/^# Test modules/a \*shared\*' Modules/Setup.stdlib.in; \
    cat Modules/Setup.stdlib.in; \
    ln -svrf Modules/Setup.stdlib Modules/Setup.local; \
    ./configure --enable-option-checking=fatal \
                # --enable-optimizations \
                # --with-lto \
                --enable-shared \
                --with-system-expat \
                --without-ensurepip \
                MODULE_BUILDTYPE=static; \
    make "$makeopts"; \
    make install DESTDIR=/py_root; \
    echo "$(basename "$(pwd)")_rev=$(git rev-parse --short HEAD)" >> /revisions; \
    popd; \
    # Print contents
    find /py_root; \
    # Strip out unnecessary files
    find /py_root/usr/local -depth \
        \( \
            \( -type d -a \( -name test -o -name tests -o -name idle_test \) \) \
         -o \( -type f -a \( -name '*.pyc' -o -name '*.pyo' -o -name 'libpython*.a' \) \) \
        \) -exec rm -rv '{}' +; \
    find /py_root/usr/local -depth -type d -name __pycache__ -delete; \
    pyid="python$PYTHON_BRANCH"; \
    pushd /py_root/usr/local; \
    find . -maxdepth 1 ! -name bin ! -name lib ! -name . -exec rm -rv '{}' +; \
    pushd bin; \
    find . -maxdepth 1 ! -name "$pyid" ! -name . -exec rm -rv '{}' +; \
    ln -sv "$pyid" python3; \
    ln -sv python3 python; \
    popd; \
    pushd lib; \
    find . -maxdepth 1 -type f -name "lib$pyid.so.*" -exec install -Dvm755 '{}' '../lib64/{}' \;; \
    find . -maxdepth 1 ! -name "$pyid" ! -name . -exec rm -rv '{}' +; \
    pushd "$pyid"; \
    [ -z "$(ls lib-dynload | grep -v test | grep -v xxlimited)" ]; \
    rm -rv lib-dynload; \
    # Strip like debian libpython3-stdlib (pydoc?)
    rm -rv config-* site-packages ensurepip lib2to3 idlelib tkinter pydoc* turtledemo; \
    popd; \
    popd; \
    popd; \
    # Copy shared libraries
    find /usr/lib64 -depth -type f \
        \( \
            -name 'libz.so.*' \
         -o -name 'libbz2.so.*' \
         -o -name 'liblzma.so.*' \
         -o -name 'libffi.so.*' \
         -o -name 'libexpat.so.*' \
         -o -name 'libuuid.so.*' \
         -o -name 'libcrypto.so.*' \
         -o -name 'libssl.so.*' \
         # Some packages (e.g. pytorch) need libstdc++
         -o -name 'libstdc++.so.*' \
        \) -exec install -Dvm755 '{}' '/py_root/{}' \;; \
    # Print contents
    find /py_root; \
    ldd -r /py_root/usr/local/bin/python;

FROM cc-latest AS py-latest

COPY --link --from=builder-py /py_root/ /
CMD ["python"]

FROM py-latest AS py-debug

COPY --link --from=busybox:musl /bin/ /bin/
CMD ["sh"]

FROM py-latest AS py-nonroot

USER nonroot
WORKDIR /home/nonroot

FROM py-debug AS py-debug-nonroot

USER nonroot
WORKDIR /home/nonroot
