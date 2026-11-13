# Runtime-only installation verification. CI builds the test binary once in the
# normal project image and mounts it read-only into each distribution.
ARG BASE_IMAGE=ubuntu:22.04
FROM ${BASE_IMAGE}
# MIME detection is a PackageKit InstallFiles input, independent of ELF deps.
# dpkg-deb/dpkg-query are already part of the base distribution's dpkg package.
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        packagekit pkexec dbus ca-certificates shared-mime-info \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /run/dbus /run/anywork-updater-test
CMD ["/bin/bash"]
