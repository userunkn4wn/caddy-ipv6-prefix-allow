## What it does

This script enables IP-based access control at Layer 7 (HTTP/HTTPS) in Caddy for networks with dynamically changing IPv6 prefixes.

It monitors IPv6 address changes, generates a reusable Caddy snippet for individual /64 subnets, and automatically reloads Caddy when the generated configuration changes.

Delegated IPv6 prefix lengths of /48 and /56 are supported.

## Configuration

Configure the delegated IPv6 prefix length and output file path in the `env` file located in the same directory as the script:

```dotenv
PREFIX_LEN=48 # supported: 48, 56
FILE="/mnt/nvme/caddy/config/dynamic_ipv6.caddy"
```

- `PREFIX_LEN`: Length of the delegated IPv6 prefix.
- `FILE`: Host path to the generated Caddy snippet.

The network interface is detected automatically.

## Usage

The script runs continuously on the Docker host, preferably as a systemd service.

The output file must be stored in a directory bind-mounted into the Caddy container so that Caddy can import it.

The script expects the Docker container to be named `caddy` and its Caddyfile to be located at `/etc/caddy/Caddyfile`.

**Note:** On the first run, the generated snippet must exist before Caddy starts, since the Caddyfile imports it. On subsequent starts, the existing file can be reused. If the script stops running, the last generated configuration remains in place but will no longer be updated.

## How it works

The script generates a file at the configured location (e.g. `/mnt/nvme/caddy/config/dynamic_ipv6.caddy`) containing a reusable Caddy snippet.

For example, with a delegated /48 IPv6 prefix:

```caddyfile
(dynamic_ipv6) {
    remote_ip 2001:db8:7a3f:{args[0]}::/64
}
```

The snippet uses Caddy's `{args[0]}` placeholder to construct individual /64 subnets from the current prefix. The generated format depends on the configured prefix length.

Import the generated file into your Caddyfile and reference the desired subnets:

```caddyfile
import /config/dynamic_ipv6.caddy

@allowed {
    import dynamic_ipv6 5
    import dynamic_ipv6 12
    import dynamic_ipv6 20
}
```

For the example /48 prefix, this is equivalent to:

```caddyfile
@allowed {
    remote_ip 2001:db8:7a3f:5::/64
    remote_ip 2001:db8:7a3f:12::/64
    remote_ip 2001:db8:7a3f:20::/64
}
```

The script monitors IPv6 address changes using `ip -6 monitor`. Multiple events occurring in quick succession are handled with a two-second debounce delay.

When the generated snippet changes, the file is updated and Caddy is reloaded automatically.

### Verification

To verify that the expected IPv6 ranges are included in the adapted Caddy configuration, run:

```bash
docker exec caddy caddy adapt --config /etc/caddy/Caddyfile --adapter caddyfile 2>/dev/null | grep -o '"ranges":[^]]*]' | sort -u
```
---

### Example with a /56 prefix

For a delegated /56 IPv6 prefix such as `2001:db8:7a3f:ab00::/56`, the generated snippet looks like this:

```caddyfile
(dynamic_ipv6) {
    remote_ip 2001:db8:7a3f:ab{args[0]}::/64
}
```

The Caddyfile imports remain the same:

```caddyfile
@allowed {
    import dynamic_ipv6 05 # <- Note leading 0 leading Digits
    import dynamic_ipv6 12
    import dynamic_ipv6 20
}
```

This is equivalent to:

```caddyfile
@allowed {
    remote_ip 2001:db8:7a3f:ab05::/64
    remote_ip 2001:db8:7a3f:ab12::/64
    remote_ip 2001:db8:7a3f:ab20::/64
}
```

For /56 prefixes, the argument specifies only the last 8 bits of the fourth IPv6 block (`00` to `ff`), whereas /48 prefixes allow specifying the entire 16-bit block (`0000` to `ffff`).

**Note:** For /56 prefixes, subnet identifiers must be exactly two hexadecimal digits. Single-digit values must be padded with a leading zero (e.g. `05` instead of `5`), otherwise the resulting address will point to a different subnet.

For example, with a /56 prefix of `2001:db8:7a3f:ab00::/56`:

- `import dynamic_ipv6 05` → `2001:db8:7a3f:ab05::/64` (correct)
- `import dynamic_ipv6 5` → `2001:db8:7a3f:ab5::/64` (equivalent to `2001:db8:7a3f:0ab5::/64`, outside the intended /56 prefix)
