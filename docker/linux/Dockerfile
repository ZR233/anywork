# Ubuntu Official Image, 22.04 linux/amd64 manifest.
FROM ubuntu:22.04@sha256:8a2321a92b438238f93b4346fff61bc4259c99fdd4d9b52ee86f153fee0c344f AS native

SHELL ["/bin/bash", "-euo", "pipefail", "-c"]
RUN test "$(dpkg --print-architecture)" = amd64 \
    && apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        bash ca-certificates curl openssh-client libnss-wrapper python3 xz-utils unzip zstd \
        clang cmake ninja-build pkg-config build-essential libgtk-3-dev \
        binutils dpkg-dev desktop-file-utils xvfb xauth dbus-x11 \
        libgl1-mesa-dri libglx-mesa0 libegl1 libasound2 \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /opt/anywork-toolchain
COPY docker/linux/versions.env /opt/anywork-image/versions.env
COPY docker/linux/scripts/install-common.sh /opt/anywork-image/scripts/install-common.sh

FROM native AS git-env
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        libcurl4-openssl-dev libexpat1-dev libssl-dev zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*
COPY docker/linux/scripts/install-git.sh /opt/anywork-image/scripts/install-git.sh
RUN bash /opt/anywork-image/scripts/install-git.sh
COPY docker/linux/Dockerfile /opt/git-source/Dockerfile

FROM native AS build-base
COPY --from=git-env /opt/git /opt/git
RUN mkdir -p /opt/git/etc \
    && ln -s "$(dpkg-query -L libnss-wrapper | grep '/libnss_wrapper\.so$')" \
    /opt/anywork-image/libnss_wrapper.so
ENV PATH=/opt/git/bin:$PATH

# No dependency on rust-toolchain.toml: a Rust upgrade retains Flutter's layer.
FROM build-base AS flutter-env
COPY docker/linux/scripts/install-flutter.sh /opt/anywork-image/scripts/install-flutter.sh
RUN bash /opt/anywork-image/scripts/install-flutter.sh

# The SDK archive's tool configuration can refer to the producer's private
# pub cache. Re-resolve only flutter_tools using pub's native cache contract.
FROM flutter-env AS flutter-tools-env
COPY docker/linux/scripts/prepare-flutter-tools.sh /opt/anywork-image/scripts/prepare-flutter-tools.sh
RUN bash /opt/anywork-image/scripts/prepare-flutter-tools.sh

FROM build-base AS rust-env
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
COPY --from=flutter-tools-env /opt/flutter/packages/flutter_tools/.dart_tool /opt/flutter/packages/flutter_tools/.dart_tool
COPY --from=flutter-tools-env /opt/flutter-pub-cache /opt/flutter-pub-cache
COPY --chmod=644 docker/linux/versions.env /opt/anywork-image/versions.env
COPY --chmod=755 docker/linux/scripts/entrypoint.sh docker/linux/scripts/smoke.sh /opt/anywork-image/scripts/
COPY --from=git-env /opt/git-source /opt/anywork-image/git-source
ENV HOME=/tmp/anywork-home \
    FLUTTER_SUPPRESS_ANALYTICS=true \
    DART_SUPPRESS_ANALYTICS=true
ENTRYPOINT ["/opt/anywork-image/scripts/entrypoint.sh"]
CMD ["bash"]
