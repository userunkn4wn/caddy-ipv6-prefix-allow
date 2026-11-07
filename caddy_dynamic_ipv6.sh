#!/bin/bash
set -euo pipefail

# Load env
source "$(dirname -- "$(realpath -- "${BASH_SOURCE[0]}")")/env"

# Validate configuration
[[ "$PREFIX_LEN" == 48 || "$PREFIX_LEN" == 56 ]] || {
    echo "Invalid PREFIX_LEN: $PREFIX_LEN (supported: 48, 56)" >&2
    exit 1
}

update() {
    IPV6=$(ip -6 addr show dev "$IFACE" scope global -temporary -deprecated |
        awk '/inet6 2/ {sub("/.*","",$2); print $2; exit}')

    [[ -n "$IPV6" ]] || {
        echo "No public IPv6 address found" >&2
        return 1
    }

    PREFIX=$(
        python3 -c '
import ipaddress, sys

length = int(sys.argv[2])
net = ipaddress.IPv6Network(f"{sys.argv[1]}/{length}", strict=False)
blocks = net.network_address.exploded.split(":")

print(":".join(blocks[:3]) + (":" + blocks[3][:2] if length == 56 else ""))
' "$IPV6" "$PREFIX_LEN"
)

    if [[ "$PREFIX_LEN" == 48 ]]; then
        SUBNET=":{args[0]}" # whole 16-bit-block
    else
        SUBNET="{args[0]}" # only 8-bit-block
    fi

    NEW="(dynamic_ipv6) {
        remote_ip ${PREFIX}${SUBNET}::/64
}"

    if [[ ! -f "$FILE" ]] || [[ "$(cat "$FILE")" != "$NEW" ]]; then
        printf '%s\n' "$NEW" > "$FILE"

        echo "$(date '+%Y-%m-%d %H:%M:%S') - IPv6-Prefix updated: $PREFIX"

        docker exec caddy caddy reload \
            --config /etc/caddy/Caddyfile \
            --adapter caddyfile
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') - No changes"
    fi
}

IFACE=$(ip -6 -o addr show scope global -temporary -deprecated | awk '$4 ~ /^2[0-9a-fA-F]*:/ {print $2; exit}')
update
# handle multiple monitor triggers: wait for last trigger
timer_pid=""
while read -r _; do
    if [[ -n "$timer_pid" ]]; then
        kill "$timer_pid" 2>/dev/null || true
        wait "$timer_pid" 2>/dev/null || true
    fi

    (sleep 2; update) &
    timer_pid=$!
done < <(ip -6 monitor address dev "$IFACE")
