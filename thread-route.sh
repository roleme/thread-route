#!/bin/sh
set -u

: "${IFACE:?IFACE is required}"
INTERVAL="${INTERVAL:-60}"
DOCKER_SOCKET="${DOCKER_SOCKET:-/var/run/docker.sock}"
RESTART_CONTAINER="${RESTART_CONTAINER:-}"
RUN_ONCE="${RUN_ONCE:-0}"

restart_container() {
    printf 'POST /containers/%s/restart HTTP/1.1\r\nHost: docker\r\nConnection: close\r\n\r\n' "$RESTART_CONTAINER" |
        socat -t 5 STDIO,ignoreeof "UNIX-CONNECT:$DOCKER_SOCKET" | head -1 | grep -q ' 204 '
}

sync_route() {
    ra=$(rdisc6 -1 -w 3000 "$IFACE" 2>/dev/null) || ra=
    prefix=$(printf '%s\n' "$ra" | awk '/^ Route / {print $3; exit}')
    next_hop=$(printf '%s\n' "$ra" | awk '/^ from / {print $2; exit}')

    if [ -z "$prefix" ] || [ -z "$next_hop" ]; then
        echo "no route option in RA on $IFACE"
        return
    fi

    if ip -6 route show "$prefix" | grep -q "via $next_hop dev $IFACE"; then
        return
    fi

    echo "route $prefix via $next_hop dev $IFACE"
    if ! ip -6 route replace "$prefix" via "$next_hop" dev "$IFACE"; then
        echo "route replace failed"
        return
    fi

    if [ -n "$RESTART_CONTAINER" ]; then
        restart_container || echo "restart of $RESTART_CONTAINER failed"
    fi
}

while true; do
    sync_route
    [ "$RUN_ONCE" = "1" ] && exit 0
    sleep "$INTERVAL"
done
