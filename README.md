# Distroless base images

Custom distroless base images based on [Clear Linux OS](//clearlinux.org/) for my personal use

## Differences from [GoogleContainerTools/distroless](//github.com/GoogleContainerTools/distroless)

-   Based on [Clear Linux OS](//clearlinux.org/), a rolling-release distribution optimized for Intel processors
-   Simple dockerfile-based build
-   Only two varients (cc/py) & one architecture (amd64)
-   cc variant does not contain OpenSSL.
-   py varient does not contain a shell, and thus [`os.system()` won't work](//github.com/GoogleContainerTools/distroless/issues/601).
-   py varient is built without terminal (`ncurses`/`readline`) and embedded db (`gdbm`/`sqlite`) support.
-   py varient: only one major version of Python is maintained and updated at my discretion.
