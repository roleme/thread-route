#!/bin/sh
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

mkdir "$WORK/bin"

cat > "$WORK/bin/rdisc6" <<'EOF'
#!/bin/sh
[ -f "$STUB_DIR/ra" ] && cat "$STUB_DIR/ra"
[ -f "$STUB_DIR/ra" ]
EOF

cat > "$WORK/bin/ip" <<'EOF'
#!/bin/sh
echo "ip $*" >> "$STUB_DIR/calls"
case "$*" in
    "-6 route show"*) [ -f "$STUB_DIR/route" ] && cat "$STUB_DIR/route" ;;
    "-6 route replace"*) echo "$4 via $6 dev $8 metric 1024" > "$STUB_DIR/route" ;;
esac
exit 0
EOF

cat > "$WORK/bin/socat" <<'EOF'
#!/bin/sh
head -1 >> "$STUB_DIR/requests"
printf 'HTTP/1.1 204 No Content\r\n\r\n'
EOF

chmod +x "$WORK/bin/"*

failures=0

run_case() {
    name=$1
    shift
    STUB_DIR="$WORK/$name"
    mkdir -p "$STUB_DIR"
    export STUB_DIR
    "$@"
}

ra_with_route() {
    printf 'Soliciting on eth9...\n Route                    : %s\n from %s\n' "$1" "$2" > "$STUB_DIR/ra"
}

check() {
    if [ "$2" = "$3" ]; then
        echo "ok   $1"
    else
        echo "FAIL $1: expected '$3', got '$2'"
        failures=$((failures + 1))
    fi
}

count() {
    if [ -f "$1" ]; then grep -c "$2" "$1"; else echo 0; fi
}

run_script() {
    PATH="$WORK/bin:$PATH" RUN_ONCE=1 "$ROOT/thread-route.sh" >> "$STUB_DIR/out" 2>&1
}

case_missing_route() {
    ra_with_route fd00:1::/64 fe80::1
    IFACE=eth9 RESTART_CONTAINER=target run_script
    check "missing route is installed" "$(count "$STUB_DIR/calls" 'route replace fd00:1::/64 via fe80::1 dev eth9')" 1
    check "missing route restarts container" "$(count "$STUB_DIR/requests" 'POST /containers/target/restart')" 1
}

case_current_route() {
    ra_with_route fd00:1::/64 fe80::1
    echo "fd00:1::/64 via fe80::1 dev eth9 metric 1024" > "$STUB_DIR/route"
    IFACE=eth9 RESTART_CONTAINER=target run_script
    check "current route is left alone" "$(count "$STUB_DIR/calls" 'route replace')" 0
    check "current route does not restart" "$(count "$STUB_DIR/requests" 'POST')" 0
}

case_stale_route() {
    ra_with_route fd00:1::/64 fe80::2
    echo "fd00:1::/64 via fe80::1 dev eth9 metric 1024" > "$STUB_DIR/route"
    IFACE=eth9 RESTART_CONTAINER=target run_script
    check "stale route is replaced" "$(count "$STUB_DIR/calls" 'route replace fd00:1::/64 via fe80::2 dev eth9')" 1
    check "stale route restarts container" "$(count "$STUB_DIR/requests" 'POST')" 1
}

case_no_ra() {
    IFACE=eth9 RESTART_CONTAINER=target run_script
    check "no RA changes nothing" "$(count "$STUB_DIR/calls" 'route replace')" 0
    check "no RA does not restart" "$(count "$STUB_DIR/requests" 'POST')" 0
}

case_no_route_option() {
    printf 'Soliciting on eth9...\n from fe80::1\n' > "$STUB_DIR/ra"
    IFACE=eth9 RESTART_CONTAINER=target run_script
    check "RA without route option changes nothing" "$(count "$STUB_DIR/calls" 'route replace')" 0
}

case_no_restart_target() {
    ra_with_route fd00:1::/64 fe80::1
    IFACE=eth9 run_script
    check "route installed without restart target" "$(count "$STUB_DIR/calls" 'route replace')" 1
    check "no restart target sends no request" "$(count "$STUB_DIR/requests" 'POST')" 0
}

case_missing_iface() {
    env -u IFACE PATH="$WORK/bin:$PATH" RUN_ONCE=1 "$ROOT/thread-route.sh" > /dev/null 2>&1
    status=$?
    check "missing IFACE fails" "$([ "$status" -ne 0 ] && echo failed || echo passed)" failed
}

run_case missing_route case_missing_route
run_case current_route case_current_route
run_case stale_route case_stale_route
run_case no_ra case_no_ra
run_case no_route_option case_no_route_option
run_case no_restart_target case_no_restart_target
run_case missing_iface case_missing_iface

[ "$failures" -eq 0 ]
