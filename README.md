# Distroless Base Images

![workflow badge](https://github.com/jvvook/distroless/actions/workflows/build.yaml/badge.svg)

Custom distroless base images based on [Clear Linux OS](//clearlinux.org/) for my personal use

## Differences from [GoogleContainerTools/distroless](//github.com/GoogleContainerTools/distroless)

-   Based on [Clear Linux OS](//clearlinux.org/), a Linux distribution optimized for Intel processors
-   Simple dockerfile-based build
-   Only two varients (`cc`/`python`) × one architecture (`amd64`)
-   `cc` variant does not contain OpenSSL.
-   `python` varient has several compatibility breaks. it...
    -   does not contain a shell, and thus [`os.system()` won't work](//github.com/GoogleContainerTools/distroless/issues/601).
    -   is built without terminal (`ncurses`, `readline`) and embedded db (`gdbm`, `sqlite`) support.
    -   is built with LibreSSL, and thus [lacks some hash algorithms](//peps.python.org/pep-0644/#libressl-support).
    -   supports only one major version of Python, chosen at my discretion.

## Available Images

`debug` images contain utilities (e.g. a shell) imported from the official [`busybox`](//hub.docker.com/_/busybox) image.

| Image                                                                                                   |                     Tags                      |   Platform    |
| ------------------------------------------------------------------------------------------------------- | :-------------------------------------------: | :-----------: |
| [`ghcr.io/jvvook/distroless/cc`](//github.com/jvvook/distroless/pkgs/container/distroless%2Fcc)         | `latest`, `nonroot`, `debug`, `debug-nonroot` | `linux/amd64` |
| [`ghcr.io/jvvook/distroless/python`](//github.com/jvvook/distroless/pkgs/container/distroless%2Fpython) | `latest`, `nonroot`, `debug`, `debug-nonroot` | `linux/amd64` |
