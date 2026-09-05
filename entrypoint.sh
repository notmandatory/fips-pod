#!/bin/bash
set -e

# In the background: wait for the fips0 TUN interface to exist, then load
# the nftables baseline that references it. (Up to ~10s, then give up.)
#
# FIPS's packaged mesh-interface firewall baseline is default-deny on
# fips0: loading it as-is blocks all unsolicited inbound on the mesh
# interface. Add exception rules as drop-in files under /etc/fips/fips.d/
# if you need to allow something through (e.g. inbound SSH from a specific
# mesh peer).
(
    for i in $(seq 1 50); do
        ip link show fips0 >/dev/null 2>&1 && break
        sleep 0.2
    done

    if [ -f /etc/fips/fips.nft ]; then
        nft -f /etc/fips/fips.nft
    else
        echo "warning: /etc/fips/fips.nft not found, firewall baseline not applied" >&2
    fi
) &

# exec so fips is PID 1 and receives SIGTERM directly on pod stop.
exec fips
