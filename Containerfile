FROM debian:13

# Base packages: bash (already default, but explicit), ssh client, and
# build prerequisites for compiling FIPS from source.
RUN apt-get update && apt-get install -y --no-install-recommends \
        bash \
        openssh-client \
        ca-certificates \
        curl \
        git \
        build-essential \
        pkg-config \
        libclang-dev \
        libdbus-1-dev \
        bluez \
        nftables \
        iproute2 \
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
RUN git reset --hard v0.4.2
RUN cargo install cargo-deb \
    && cargo deb \
    && dpkg -i target/debian/fips_*.deb

# Bake in customized config (overwrites the package defaults installed
# above). Comment these out if you'd rather bind-mount your own at
# runtime instead — see notes below.
COPY etc/fips/fips.yaml /etc/fips/fips.yaml
COPY etc/fips/hosts /etc/fips/hosts
COPY etc/fips/fips.nft /etc/fips/fips.nft

# Setup dnsmasq
RUN apt-get update && apt-get install -y dnsmasq iputils-ping dnsutils

COPY etc/dnsmasq.conf /etc/dnsmasq.conf
COPY etc/dnsmasq.d/fips.conf /etc/dnsmasq.d/fips.conf

# entrypoint.sh starts fips, waits for the fips0 TUN interface, then loads
# the packaged default-deny nftables baseline (/etc/fips/fips.nft) so all
# unsolicited inbound on the mesh interface is blocked.
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
