# thread-route

Keeps a host's IPv6 route to a Thread mesh in sync with the border router's router advertisements.

Some kernels ignore the Route Information option in router advertisements, so the host never learns the route to the Thread mesh by itself. This container sends a router solicitation on a chosen interface, reads the Thread prefix from the Route option and the border router's link-local address from the sender of the reply, and runs `ip -6 route replace` only when the installed route differs. Nothing about the prefix or the border router is configured; both are discovered on every pass.

When the route changes it can also restart one container through the Docker API. That is for services that cache the old address, such as a Matter server.

## Usage

```yaml
services:
  thread-route:
    image: ghcr.io/roleme/thread-route:1.0.0
    restart: unless-stopped
    network_mode: host
    cap_add:
      - NET_ADMIN
    environment:
      IFACE: eth0
      RESTART_CONTAINER: matter-server
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
```

The container needs host networking and `NET_ADMIN` to change the host's routes. Mount the Docker socket only when `RESTART_CONTAINER` is set; it gives the container control of the Docker daemon.

## Configuration

| Variable | Default | Meaning |
|---|---|---|
| `IFACE` | required | Interface to solicit on and install the route through |
| `INTERVAL` | `60` | Seconds between passes |
| `RESTART_CONTAINER` | empty | Container to restart after a route change; empty means never restart |
| `DOCKER_SOCKET` | `/var/run/docker.sock` | Docker API socket used for the restart |
| `RUN_ONCE` | `0` | `1` runs a single pass and exits |

If no router advertisement carries a Route option, the existing route is left alone.

## Development

```sh
sh tests/test.sh
```

The tests run the script against stub `rdisc6`, `ip` and `socat`, so they need no network access or privileges.

Images are published for each `vX.Y.Z` tag.
