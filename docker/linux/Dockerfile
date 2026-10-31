# Ubuntu Official Image, 22.04 linux/amd64 manifest.
FROM ubuntu:22.04@sha256:8a2321a92b438238f93b4346fff61bc4259c99fdd4d9b52ee86f153fee0c344f AS native

SHELL ["/bin/bash", "-euo", "pipefail", "-c"]
RUN test "$(dpkg --print-architecture)" = amd64 \
    && apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        bash ca-certificates curl git python3 xz-utils unzip zstd \
        clang cmake ninja-build pkg-config build-essential libgtk-3-dev \
        binutils dpkg-dev desktop-file-utils xvfb xauth dbus-x11 \
        libgl1-mesa-dri libglx-mesa0 libegl1 libasound2 \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /opt/anywork-toolchain
COPY docker/linux/versions.env /opt/anywork-image/versions.env
COPY docker/linux/scripts/install-common.sh /opt/anywork-image/scripts/install-common.sh

# No dependency on rust-toolchain.toml: a Rust upgrade retains Flutter's layer.
FROM native AS flutter-env
COPY docker/linux/scripts/install-flutter.sh /opt/anywork-image/scripts/install-flutter.sh
RUN bash /opt/anywork-image/scripts/install-flutter.sh

FROM native AS rust-env
ENV CARGO_HOME=/opt/cargo \
    RUSTUP_HOME=/opt/rustup \
    PATH=/opt/cargo/bin:/opt/flutter/bin:/opt/zig:$PATH
COPY rust-toolchain.toml /opt/anywork-toolchain/rust-toolchain.toml
COPY docker/linux/scripts/install-rust.sh /opt/anywork-image/scripts/install-rust.sh
RUN bash /opt/anywork-image/scripts/install-rust.sh
ENV RUSTUP_AUTO_INSTALL=0

FROM rust-env AS linux-build
COPY --from=flutter-env /opt/flutter /opt/flutter
COPY docker/linux/scripts/install-tools.sh /opt/anywork-image/scripts/install-tools.sh
RUN bash /opt/anywork-image/scripts/install-tools.sh \
    && git config --system --add safe.directory /opt/flutter \
    && chmod 1777 /opt/cargo \
    && chmod -R a+rwX /opt/flutter/bin/cache
COPY --chmod=644 docker/linux/versions.env /opt/anywork-image/versions.env
COPY --chmod=755 docker/linux/scripts/entrypoint.sh docker/linux/scripts/smoke.sh /opt/anywork-image/scripts/
ENV HOME=/tmp/anywork-home \
    FLUTTER_SUPPRESS_ANALYTICS=true \
    DART_SUPPRESS_ANALYTICS=true
ENTRYPOINT ["/opt/anywork-image/scripts/entrypoint.sh"]
CMD ["bash"]
