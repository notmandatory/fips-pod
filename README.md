# fips-pod

A Podman pod that runs a [FIPS](https://github.com/jmcorgan/fips) mesh
daemon alongside an SSH daemon, designed primarily for macOS hosts that want
to be a client on the FIPS network and reach servers on that network via SSH.

Because the pod runs its own `sshd`, it can also be used as an SSH
`ProxyJump` host — your Mac talks SSH to the pod, and the pod talks to
`*.fips` destinations over the mesh.

## What it does

The pod (`fips-pod`) is made of three single-process containers that share
one network namespace, so loopback (`127.0.0.1` / `::1`) and the `fips0`
mesh interface are visible to all of them:

```
┌─────────────────────────────── pod: fips-pod ────────────────────────────────┐
│  shared network namespace (loopback + fips0 visible to all containers)       │
│                                                                              │
│  ┌───────────────┐   ┌────────────────┐   ┌─────────────────────────────┐    │
│  │ fips          │   │ fips-dnsmasq   │   │ fips-sshd                   │    │
│  │ fips daemon   │   │ 127.0.0.1:53   │   │ sshd -D -e        (:22)     │    │
│  │ DNS [::1]:5354│──▶│ .fips → [::1]  │◀──│ outbound ssh resolves .fips │    │
│  │ TUN fips0     │   │ else → host DNS│   │ via 127.0.0.1               │    │
│  │ nft baseline  │   │                │   │                             │    │
│  │ NET_ADMIN/RAW │   │ no caps        │   │ no caps                     │    │
│  │ /dev/net/tun  │   │                │   │                             │    │
│  └───────────────┘   └────────────────┘   └─────────────────────────────┘    │
│                                                    │                         │
└────────────────────── published: 127.0.0.1:2222:22 (on the pod) ─────────────┘
```

- **`fips`** — the FIPS daemon (built from source, pinned to `v0.4.2` on
  Debian 13), run as PID 1 via `exec` for clean signal handling. Brings up
  the `fips0` TUN interface, then `entrypoint.sh` loads the
  `/etc/fips/fips.nft` baseline: default-deny on all unsolicited inbound
  mesh traffic. The only privileged container in the pod.
- **`fips-dnsmasq`** — the pod's resolver. Forwards `.fips` queries to the
  FIPS daemon's DNS responder on `[::1]:5354` and everything else to the
  host's upstream resolvers. Binds loopback only.
- **`fips-sshd`** — SSH server published to the host on `127.0.0.1:2222`
  (only the local machine can reach it), plus the SSH client used for
  outbound connections to `*.fips` servers.

All configuration lives on the host and is bind-mounted in, so edits on the
host take effect on pod restart (no image rebuild needed).

## Requirements

- macOS with [Podman](https://podman.io) (including `podman machine`)
- [just](https://just.systems) command runner

## First-run setup

Secrets are intentionally **not** committed to this repo (see `.gitignore`).
Before starting the pod you need:

1. **FIPS identity** — nothing to do: `fips.yaml` sets
   `node.identity.persistent: true`, so on first start the daemon generates
   a keypair and saves it to `etc/fips/fips.key` / `etc/fips/fips.pub`
   (on the host, via the bind mount). Your node keeps the same identity
   across restarts.
2. **SSH keys** — populate the `ssh/` directory (mounted to `/root/.ssh`
   in the `fips-sshd` container):
   - `authorized_keys` — public keys allowed to log in to the pod.
   - `id_ed25519` / `id_ed25519.pub` — optional; the key the pod uses for
     *outbound* SSH to servers on the FIPS network.
   - `known_hosts` — persists automatically through the mount.

## Usage

Everything is driven by `just` recipes:

| Recipe             | Action                                              |
|--------------------|-----------------------------------------------------|
| `just minit`       | Initialize the podman machine (first time only)     |
| `just mstart`      | Start the podman machine                            |
| `just mstop`       | Stop the podman machine                             |
| `just build`       | Build the `fips`, `fips-dnsmasq`, `fips-sshd` images|
| `just start`       | Create the `fips-pod` and start its containers      |
| `just restart`     | Restart a stopped `fips-pod`                        |
| `just stop`        | Stop the pod                                        |
| `just remove`      | Stop and remove the pod and its containers          |
| `just show`        | Show the pod and its containers                     |
| `just shell`       | Open a bash shell in the `fips` container           |
| `just shell fips-sshd` | Shell into another container                   |
| `just logs`        | Show logs for the whole pod                         |
| `just logs fips`   | Show logs for one container                         |

Typical first-time flow:

```sh
just minit      # once
just mstart
just build
just start
just logs       # watch fips connect to its peers
```

## SSH access

From the Mac host:

```sh
ssh -p 2222 root@127.0.0.1
```

A convenient `~/.ssh/config` on the Mac:

```sshconfig
# The fips-pod itself
Host fips-pod
    HostName 127.0.0.1
    Port 2222
    User root
    IdentityFile ~/.ssh/id_ed25519   # key whose public half is in ssh/authorized_keys

# Reach FIPS mesh servers through the pod
Host *.fips
    ProxyJump fips-pod
```

Then:

```sh
ssh fips-pod                      # shell inside the pod's sshd container
ssh user@test-us04.fips           # one hop, via ProxyJump
```

Name resolution for `*.fips` happens *inside* the pod (dnsmasq → the FIPS
DNS responder), so the Mac itself never needs mesh-aware DNS.

## Configuration

All files live in this repo and are bind-mounted into the containers:

| Host path          | Container (path)                          | Purpose                                   |
|--------------------|-------------------------------------------|-------------------------------------------|
| `etc/fips/`        | `fips` (`/etc/fips/`)                     | `fips.yaml`, `hosts`, peer allow/deny lists, `fips.nft`, identity keys |
| `etc/dnsmasq.conf` | `fips-dnsmasq` (`/etc/dnsmasq.conf`)      | dnsmasq main config (upstream resolv-file, loopback-only binding) |
| `etc/dnsmasq.d/`   | `fips-dnsmasq` (`/etc/dnsmasq.d/`)        | `.fips` zone forwarding                   |
| `/etc/resolv.conf` | `fips-dnsmasq` (`/etc/resolv.dnsmasq.conf`)| Host resolvers used as dnsmasq upstreams |
| `ssh/`             | `fips-sshd` (`/root/.ssh/`)               | SSH keys, `authorized_keys`, `known_hosts` |

Notes:

- **Peers** — `etc/fips/fips.yaml` ships with static peers for the public
  FIPS test mesh (`test-us01`, `test-us02`, `test-us04`) and
  `accept_connections: false` on the UDP transport (pure client posture).
  `etc/fips/peers.allow` / `peers.deny` further restrict who may peer with
  this node.
- **Hostnames** — `etc/fips/hosts` maps names like `test-us04` to npubs for
  `.fips` DNS resolution.
- **Firewall** — inbound on `fips0` is default-deny. To allow something
  (e.g. inbound SSH from a mesh peer), drop a rule file into
  `etc/fips/fips.d/*.nft` and restart; see the extensive comments in
  `etc/fips/fips.nft`.
- **Ports** — sshd is published only on `127.0.0.1:2222` on the host.
  dnsmasq binds loopback only inside the pod. FIPS itself makes outbound
  UDP connections to its static peers.

## Repository layout

```
Containerfile    # multi-stage build: fips (Rust build of FIPS v0.4.2), dnsmasq, sshd
Justfile         # podman machine / image / pod lifecycle recipes
entrypoint.sh    # fips container: exec fips as PID 1; load nftables baseline once fips0 is up
etc/fips/        # fips.yaml, hosts, fips.nft, peers.allow/deny, identity keys (gitignored)
etc/dnsmasq.conf # dnsmasq config (host resolv.conf as upstream, loopback-only)
etc/dnsmasq.d/   # .fips zone → fips DNS responder
ssh/             # /root/.ssh contents for the sshd container (gitignored)
```

## License

[MIT](LICENSE)
