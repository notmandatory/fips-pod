#!/bin/bash
set -e

# Setup dnsmasq
dnsmasq --no-daemon &
sleep 2

# Start the FIPS daemon in the background so we can wait for the fips0
# TUN interface to exist before loading nftables rules that reference it.
fips &
FIPS_PID=$!

# Wait up to ~10s for fips0 to come up.
for i in $(seq 1 50); do
    ip link show fips0 >/dev/null 2>&1 && break
    sleep 0.2
done

# Load FIPS's packaged mesh-interface firewall baseline. Per upstream docs
# this ships as default-deny on fips0 already, so loading it as-is blocks
# all unsolicited inbound on the mesh interface. Add exception rules as
# drop-in files under /etc/fips/fips.d/ if you need to allow something
# through (e.g. inbound SSH from a specific mesh peer).
if [ -f /etc/fips/fips.nft ]; then
    nft -f /etc/fips/fips.nft
else
    echo "warning: /etc/fips/fips.nft not found, firewall baseline not applied" >&2
fi

wait "$FIPS_PID"
