# syntax=docker/dockerfile:1.7
# The Linux host in a container with an X server and a few X apps, for testing without a Linux
# desktop (NOTES-linux.md, "Docker test"). Build context: hosts/ (the workspace):
#   docker build -f sill-host-linux/Dockerfile -t sill-linux-test .
#   docker run --rm --name sill-linux-selftest sill-linux-test                 # the self-test
#   docker run --rm --name sill-linux-host -p 127.0.0.1:47123:47123 sill-linux-test host --port 47123
# Publish ports to 127.0.0.1 only.

FROM rust:1.92-trixie AS build
WORKDIR /src
COPY . .
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/src/target-docker \
    CARGO_TARGET_DIR=/src/target-docker cargo build --release -p sill-host-linux \
 && cp /src/target-docker/release/sill-host-linux /usr/local/bin/sill-host-linux

FROM debian:trixie-slim
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      xvfb openbox xterm x11-apps x11-utils x11-xserver-utils xdotool \
      ffmpeg dbus avahi-daemon avahi-utils libnss-mdns \
      mousepad desktop-file-utils hicolor-icon-theme adwaita-icon-theme \
      fonts-dejavu-core locales procps ca-certificates \
 && sed -i 's/# en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen && locale-gen \
 && rm -rf /var/lib/apt/lists/*
ENV LANG=en_US.UTF-8 DISPLAY=:99
COPY --from=build /usr/local/bin/sill-host-linux /usr/local/bin/sill-host-linux
COPY sill-host-linux/docker/entry.sh /usr/local/bin/sill-entry
RUN chmod +x /usr/local/bin/sill-entry
ENTRYPOINT ["/usr/local/bin/sill-entry"]
CMD ["selftest"]
