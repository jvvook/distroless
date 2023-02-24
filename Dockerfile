FROM clearlinux AS builder-base

RUN set -eux; \
    # Update & install bundles
    swupd update --no-boot-update; \
    swupd bundle-add mixer c-basic --no-boot-update;

FROM builder-base AS builder-repo

RUN set -eux; \
    # Get version info
    source /usr/lib/os-release; \
    # Customize bundles
    mkdir /repo; \
    pushd /repo; \
    mixer init --no-default-bundles --mix-version $VERSION_ID; \
    mixer bundle add os-core; \
    mixer bundle edit os-core; \
    printf '\
glibc-lib-avx2\n\
libgcc1\n\
netbase-data\n\
tzdata-minimal\n\
' > local-bundles/os-core; \
    mixer bundle add os-core-plus; \
    mixer bundle edit os-core-plus; \
    printf '\
ncurses-data\n\
' > local-bundles/os-core-plus; \
    sed -i 's/os-core-update/os-core/' builder.conf; \
    mixer build all; \
    popd;

FROM builder-repo AS builder-core

RUN set -eux; \
    # Get version info
    source /usr/lib/os-release; \
    # Install os-core
    mkdir /install_root; \
    swupd os-install --version $VERSION_ID \
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

COPY --from=builder-cc /install_root /
WORKDIR /root

FROM cc-latest AS cc-debug

COPY --from=busybox:musl /bin /bin/
ENTRYPOINT ["/bin/sh"]

FROM cc-latest AS cc-nonroot

USER nonroot
WORKDIR /home/nonroot

FROM cc-debug AS cc-debug-nonroot

USER nonroot
WORKDIR /home/nonroot

FROM builder-base AS builder-python

RUN set -eux;

FROM builder-repo AS builder-core-plus

RUN set -eux; \
    # Get version info
    source /usr/lib/os-release; \
    # Install os-core & os-core-plus
    mkdir /install_root; \
    swupd os-install --version $VERSION_ID \
                     --path /install_root \
                     --statedir /swupd-state \
                     --bundles os-core,os-core-plus \
                     --no-boot-update \
                     --no-scripts \
                     --url file:///repo/update/www \
                     --certpath /repo/Swupd_Root.pem; \
    # Print contents
    find /install_root;
