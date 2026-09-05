[doc("List all available recipes.")]
@list:
  just --list

[doc("Initialize the podman machine")]
minit:
  podman machine init

[doc("Start the podman machine.")]
mstart:
  podman machine start

[doc("Stop the podman machine.")]
mstop:
  podman machine stop

[doc("Build the fips, fips-dnsmasq, and fips-sshd images.")]
build:
  podman build --target fips    -t fips         -f Containerfile .
  podman build --target dnsmasq -t fips-dnsmasq -f Containerfile .
  podman build --target sshd    -t fips-sshd    -f Containerfile .

[doc("Create the fips-pod and start its containers.")]
start:
  podman pod create --name fips-pod \
  --dns=127.0.0.1 --dns-search=fips \
  -p 127.0.0.1:2222:22
  podman run -d --pod fips-pod --name fips \
  --cap-add=NET_ADMIN --cap-add=NET_RAW \
  --device /dev/net/tun \
  -v ./etc/fips:/etc/fips:Z \
  fips
  podman run -d --pod fips-pod --name fips-dnsmasq \
  -v ./etc/dnsmasq.conf:/etc/dnsmasq.conf:Z \
  -v ./etc/dnsmasq.d:/etc/dnsmasq.d:Z \
  -v /etc/resolv.conf:/etc/resolv.dnsmasq.conf:Z \
  fips-dnsmasq
  podman run -d --pod fips-pod --name fips-sshd \
  -v ./ssh:/root/.ssh:Z \
  fips-sshd

[doc("Restart a stopped fips-pod.")]
restart:
  podman pod restart fips-pod

[doc("Show the pod and its containers.")]
show:
  podman pod ps
  podman ps -a --pod

[doc("Stop the fips-pod.")]
stop:
  podman pod stop fips-pod

[doc("Remove the fips-pod and its containers.")]
remove: stop
  podman pod rm fips-pod

[doc("Shell into a container (default: fips; e.g. just shell fips-sshd).")]
shell container="fips":
  podman exec -it {{container}} bash

[doc("Show logs (all containers, or one container: just logs fips-sshd).")]
logs container="":
  #!/usr/bin/env bash
  set -e
  if [ -z "{{container}}" ]; then
    for c in fips fips-dnsmasq fips-sshd; do
      echo "==> $c <=="
      podman logs "$c"
    done
  else
    podman logs "{{container}}"
  fi
