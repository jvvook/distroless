# syntax=docker/dockerfile:1.4
ARG PYTHON_BRANCH=3.11

FROM clearlinux AS builder-base

RUN set -eux; \
    swupd update --no-boot-update; \
    swupd bundle-add mixer \
                     # python dependencies (no ncurses/readline/gdbm/sqlite3)
                     devpkg-zlib \
                     devpkg-bzip2 \
                     devpkg-xz \
                     devpkg-libffi \
                     devpkg-expat \
                     devpkg-util-linux \
                     devpkg-openssl \
                     --no-boot-update;

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
# tzdata-minimal\n\
tzdata\n\
' > local-bundles/os-core; \
    sed -i 's/os-core-update/os-core/' builder.conf; \
    mixer build all; \
    popd; \
    # Install os-core
    mkdir /cc_root; \
    swupd os-install --version "$VERSION_ID" \
                     --path /cc_root \
                     --statedir /swupd-state \
                     --bundles os-core \
                     --no-boot-update \
                     --no-scripts \
                     --url file:///repo/update/www \
                     --certpath /repo/Swupd_Root.pem; \
    # Print contents
    find /cc_root; \
    # Strip out unnecessary files
    find /cc_root -depth \
        \( \
            -name clear \
         -o -name swupd \
         -o -name package-licenses \
        \) -exec rm -rv '{}' +; \
    rm -rv /cc_root/{autofs,boot,media,mnt,srv}; \
    # Add CA certs
    CLR_TRUST_STORE=/certs clrtrust generate; \
    install -Dvm644 /certs/anchors/ca-certificates.crt /cc_root/etc/ssl/certs/ca-certificates.crt; \
    # Create passwd/group files (from distroless, without staff)
    printf '\
root:x:0:0:root:/root:/sbin/nologin\n\
nobody:x:65534:65534:nobody:/nonexistent:/sbin/nologin\n\
nonroot:x:65532:65532:nonroot:/home/nonroot:/sbin/nologin\n\
' > /cc_root/etc/passwd; \
    printf '\
root:x:0:\n\
nobody:x:65534:\n\
tty:x:5:\n\
nonroot:x:65532:\n\
' > /cc_root/etc/group; \
    install -dvm700 -g65532 -o65532 /cc_root/home/nonroot; \
    # Print contents
    find /cc_root; \
    cat /cc_root/etc/passwd; \
    cat /cc_root/etc/group; \
    cat /cc_root/usr/lib/os-release;

FROM scratch AS cc-latest

COPY --link --from=builder-cc /cc_root /

FROM cc-latest AS cc-debug

COPY --link --from=busybox:musl /bin /bin/
CMD ["sh"]

FROM cc-latest AS cc-nonroot

USER nonroot
WORKDIR /home/nonroot

FROM cc-debug AS cc-debug-nonroot

USER nonroot
WORKDIR /home/nonroot

FROM builder-base AS builder-py

ARG PYTHON_BRANCH

RUN set -ex; \
    source /usr/share/defaults/etc/profile; \
    set -u; \
    export LDFLAGS="${LDFLAGS:-} -Wl,--strip-all"; \
    # Install python
    mkdir /py_root; \
    git clone --depth 1 --branch "$PYTHON_BRANCH" https://github.com/python/cpython; \
    pushd cpython; \
    # Might not be needed in 3.12
    sed -i 's/^#@MODULE__CTYPES_TRUE@\(.*\)/\1 -lffi/' Modules/Setup.stdlib.in; \
    ln -svrf Modules/Setup.stdlib Modules/Setup.local; \
    ./configure --enable-option-checking=fatal \
                # --enable-optimizations \
                # --with-lto \
                --enable-shared \
                --with-system-expat \
                --without-ensurepip \
                --disable-test-modules \
                MODULE_BUILDTYPE=static \
                # xxlimited cannot be built as static libraries
                py_cv_module_xxlimited=n/a \
                py_cv_module_xxlimited_35=n/a; \
    make "-j$(nproc)"; \
    make install DESTDIR=/py_root; \
    popd; \
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
    # Similar to Debian libpython3-stdlib (pydoc?)
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
         # PyTorch needs libstdc++
         -o -name 'libstdc++.so.*' \
        \) -exec install -Dvm755 '{}' '/py_root/{}' \;; \
    # Print contents
    find /py_root;

FROM cc-latest AS py-latest

COPY --link --from=builder-py /py_root /
CMD ["python"]

FROM py-latest AS py-debug

COPY --link --from=busybox:musl /bin /bin/
CMD ["sh"]

FROM py-latest AS py-nonroot

USER nonroot
WORKDIR /home/nonroot

FROM py-debug AS py-debug-nonroot

USER nonroot
WORKDIR /home/nonroot
