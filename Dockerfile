FROM clearlinux AS builder

RUN set -eux; \
    # Update & install mixer
    swupd update --no-boot-update; \
    swupd bundle-add mixer --no-boot-update;

RUN set -eux; \
    # Get version info
    source /usr/lib/os-release; \
    # Customize os-core
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
    sed -i 's/os-core-update/os-core/' builder.conf; \
    mixer build bundles; \
    mixer build update; \
    popd; \
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
    find /install_root; \
    # Strip out unnecessary files
    find /install_root -name clear -exec rm -rv {} +; \
    find /install_root -name swupd -exec rm -rv {} +; \
    find /install_root -name package-licenses -exec rm -rv {} +; \
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

FROM scratch

COPY --from=builder /install_root /

USER nonroot
WORKDIR /home/nonroot
