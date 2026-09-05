# syntax=docker/dockerfile:1
#
# Multi-stage build for the fips-pod. Build all three images with:
#
#   podman build --target fips     -t fips         -f Containerfile .
#   podman build --target dnsmasq  -t fips-dnsmasq -f Containerfile .
#   podman build --target sshd     -t fips-sshd    -f Containerfile .
#
# (or just `just build`)

# ─── Stage: fips-build ───────────────────────────────────────────────
# Compiles FIPS from source and packages it as a .deb. Only this stage
# carries the Rust toolchain and build prerequisites.
FROM debian:13 AS fips-build

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        build-essential \
        pkg-config \
        libclang-dev \
        libdbus-1-dev \
        bluez \
    && rm -rf /var/lib/apt/lists/*

# Install Rust toolchain (FIPS requires Rust 1.94.1+, edition 2024)
ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH=/usr/local/cargo/bin:$PATH
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | \
        sh -s -- -y --profile minimal --default-toolchain stable

# Clone and build FIPS
WORKDIR /usr/src
RUN git clone https://github.com/jmcorgan/fips.git
WORKDIR /usr/src/fips
RUN git reset --hard v0.5.0
RUN cargo install cargo-deb && cargo deb
# Artifact: /usr/src/fips/target/debian/fips_*.deb

# ─── Stage: fips ─────────────────────────────────────────────────────
# Runs the FIPS daemon. The only privileged container in the pod:
# owns the fips0 TUN interface and loads the nftables baseline.
FROM debian:13 AS fips

COPY --from=fips-build /usr/src/fips/target/debian/fips_*.deb /tmp/
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        /tmp/fips_*.deb \
        nftables \
        iproute2 \
        ca-certificates \
        iputils-ping \
        dnsutils \
    && rm -rf /var/lib/apt/lists/* /tmp/fips_*.deb

# Bake in default config (bind-mounted over at runtime — see Justfile).
COPY etc/fips/fips.yaml /etc/fips/fips.yaml
COPY etc/fips/hosts /etc/fips/hosts
COPY etc/fips/fips.nft /etc/fips/fips.nft

# entrypoint.sh runs fips as PID 1 (via exec, for clean SIGTERM handling)
# and, in the background, waits for the fips0 TUN interface to exist before
# loading the default-deny nftables baseline (/etc/fips/fips.nft) so all
# unsolicited inbound on the mesh interface is blocked.
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

# ─── Stage: dnsmasq ──────────────────────────────────────────────────
# The pod's resolver. Forwards .fips to the FIPS DNS responder at
# [::1]:5354, everything else to the host's upstream resolvers.
FROM debian:13 AS dnsmasq

RUN apt-get update \
    && apt-get install -y --no-install-recommends dnsmasq \
    && rm -rf /var/lib/apt/lists/*

COPY etc/dnsmasq.conf /etc/dnsmasq.conf
COPY etc/dnsmasq.d/fips.conf /etc/dnsmasq.d/fips.conf

ENTRYPOINT ["/usr/sbin/dnsmasq", "--no-daemon"]

# ─── Stage: sshd ─────────────────────────────────────────────────────
# SSH access to the pod. The server accepts logins from the host
# (published on 127.0.0.1:2222); the client is used for outbound SSH
# to servers on the FIPS network (ProxyJump).
FROM debian:13 AS sshd

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        openssh-server \
        openssh-client \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /run/sshd

ENTRYPOINT ["/usr/sbin/sshd", "-D", "-e"]
