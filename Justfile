[doc("List all available recipes.")]
@list:
  just --list

[doc("Start the podman machine.")]
mstart:
  podman machine start

[doc("Stop the podman machine.")]
mstop:
  podman machine stop

[doc("Build the debian13-fips image.")]
build:
  podman build -t debian13-fips -f Containerfile .

[doc("Start the fips-node.")]
start:
  podman run -d --name fips-node \
  --cap-add=NET_ADMIN --cap-add=NET_RAW \
  --device /dev/net/tun \
  --dns=127.0.0.1 --dns-search=fips \
  -v ./etc/fips:/etc/fips:Z \
  -v ./ssh:/root/.ssh:Z \
  -v ./etc/dnsmasq.conf:/etc/dnsmasq.conf:Z \
  -v ./etc/dnsmasq.d:/etc/dnsmasq.d:Z \
  debian13-fips

[doc("Restart a stopped fips-node.")]
restart:
  podman restart fips-node

[doc("Show all containers.")]
show:
  podman container list

[doc("Stop the fips-node.")]
stop:
  podman container stop fips-node

[doc("Remove the fips-node.")]
remove: stop
  podman container rm fips-node

[doc("Shell into fips-node.")]
shell:
  podman exec -it fips-node bash

[doc("Show fips-node log.")]
log:
  podman logs fips-node -f
