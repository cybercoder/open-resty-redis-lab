# tlscdn-openresty

OpenResty (Nginx + Lua) reverse-proxy/CDN gateway driven by Redis. It selects an upstream per request (with DNS resolution + caching), optionally applies WAF logic, and can enable Nginx proxy caching for eligible routes. It also exposes Prometheus metrics.

This repo is set up to run locally via Docker Compose with:
- `openresty` container (OpenResty + Lua modules)
- `redis` container (route + gateway data store)

---

## What this does (high-level)

For each request:
1. **Gateway lookup (by Host)** in Redis (or cache): determines the namespace/gateway metadata and whether the request is recognized.
2. **WAF processing** (Lua) is executed early; blocked requests stop here.
3. **Route lookup** in Redis (or cache): exact match first, then longest-prefix match.
4. **Upstream resolution**: each upstream “address” is resolved (DNS cached in `lua_shared_dict`), IPs are cached with TTL.
5. **Load-balancing choice**: the request is assigned to one upstream (currently an IP-hash-style choice based on client identifiers).
6. **Proxy + headers**: OpenResty proxies to the chosen upstream with the upstream Host header and scheme.
7. **Caching**: if enabled by route config (and not bypassed), Nginx `proxy_cache` is used. Certain paths (e.g. `.m3u8`) are force-bypassed.

---

## Quick start (Docker Compose)

From the repo root:

```/dev/null/bash#L1-6
docker compose up -d
docker compose ps

# openresty is exposed on localhost:8080 -> container port 80
# redis is exposed on localhost:6379
```

Enter Redis CLI:

```/dev/null/bash#L1-2
docker compose exec redis redis-cli
```

Add a gateway and a route (examples below), then test:

```/dev/null/bash#L1-1
curl -H "Host: mycdn.com" http://localhost:8080/
```

---

## Configuration

### Compose
See `compose.yaml` for ports, volumes, and environment variables. Notable mappings:
- `./config/nginx.conf.dev` → `/usr/local/openresty/nginx/conf/nginx.conf`
- `./app` → `/app` (Lua code)
- `./cache` → `/disk-cache` (Nginx proxy cache)
- `./maxminddb` → `/maxminddb` (GeoIP DB location, if used by WAF/rules)

### Environment variables used by Nginx/Lua

These are exposed via `env ...;` directives in Nginx config and/or used in Lua libs:

- `DNS_SERVERS` (comma-separated list; e.g. `8.8.4.4,8.8.8.8`)
- `REDIS_HOST`
- `REDIS_PASSWORD`
- `REDIS_DB`
- `WAF_ENDPOINT` (present in compose; usage depends on WAF implementation)

Notes:
- The dev Nginx config uses Docker’s internal resolver `127.0.0.11`.
- Redis auth is optional in the compose file; wire up `REDIS_PASSWORD` if you enable it.

---

## Redis data model (required)

The proxy behavior is driven by Redis keys.

### 1) Gateway key (per hostname)

**Key**
- `<host>` (example: `mycdn.com`)

**Value (JSON)**
- `fullchain`: string (PEM certificate chain; used when TLS/SNI is enabled)
- `privkey`: string (PEM private key; used when TLS/SNI is enabled)
- `port`: number (gateway port metadata)
- `protocol`: `"http"` or `"https"` (gateway protocol metadata)
- `namespace`: string (used for metrics labels)
- `gateway`: string (gateway identifier)
- other fields may exist; code uses at least `namespace` and also reads a `name` field for metrics when present

Example:

```/dev/null/redis#L1-2
SET mycdn.com '{"fullchain":"-----BEGIN CERTIFICATE-----...","privkey":"-----BEGIN PRIVATE KEY-----...","port":80,"protocol":"http","namespace":"default","gateway":"edge-a","name":"edge-a"}'
```

If the gateway key is missing or invalid JSON, requests return **404** with `gateway not found.`

### 2) Route key (per hostname + path)

Routes are stored under keys with this general shape:

- Exact match:
  - `httproute:<host>:exact:<path>`
- Prefix match:
  - `httproute:<host>:prefix:<pathPrefix>`

Routing logic:
- Try exact match for the full request `uri`
- If not found, try prefix matches from **longest** to **shortest**, down to `/`

**Value (JSON)**
- `lb_method`: string (declared, but the current request path selects upstream via an IP-hash call)
- `upstreams`: array of upstream objects
- optional `cache` object (see caching section)

Upstream object fields used by the runtime:
- `address`: hostname or IP (this is what gets DNS-resolved / cached)
- `port`: number
- `protocol`: `"http"` or `"https"`
- `hostHeader`: string (sent as `Host` to the origin)

> Important: some older examples use `server`/`host_header`. The runtime code expects `address` and `hostHeader`. Make sure your JSON matches the fields your Lua code reads.

Example (prefix route for `/`):

```/dev/null/redis#L1-2
SET httproute:mycdn.com:prefix:/ '{
  "lb_method":"rr",
  "upstreams":[
    {"hostHeader":"example.com","protocol":"https","address":"example.com","port":443,"weight":1}
  ]
}'
```

Example (more specific prefix route):

```/dev/null/redis#L1-2
SET httproute:mycdn.com:prefix:/api '{
  "lb_method":"rr",
  "upstreams":[
    {"hostHeader":"api.example.com","protocol":"http","address":"10.0.0.10","port":8080,"weight":1}
  ]
}'
```

If a route is missing, requests return **404** with `route not found.`  
If a route exists but has `upstreams: []`, requests return **404** with `No upstream for route`.

---

## DNS behavior

Upstream `address` is resolved as follows:
- If `address` is already an IP, it’s used directly.
- Otherwise, it is resolved via DNS and cached in `lua_shared_dict dns_cache`.
- TTL is taken from the DNS answer when available; otherwise defaults to ~300s.

If DNS fails:
- When multiple upstreams exist, failed upstreams are skipped and others are tried.
- If all upstreams fail resolution, the request returns **502**.

---

## Load balancing behavior

Routes can declare `lb_method`, but the current access path chooses an upstream with an IP-hash approach based on client identifiers (see `/app/access.lua` and `app/lib/lb`).

This means:
- A client tends to stick to the same upstream (depending on the hashing inputs).
- Weights may or may not be honored depending on the `lb` implementation.

---

## Caching behavior

Nginx proxy cache is configured via:

- `proxy_cache_path /disk-cache ... keys_zone=STATIC:100m ...`

Per-request behavior:
- Default is **cache disabled**.
- If the request path ends with `.m3u8`, cache is **forced off**.
- If the route has no `cache` config, cache is **off**.
- If `route_data.cache.level == "bypass"`, cache is **off**.
- If `route_data.cache.level == "standard"`, cache is enabled via `proxy_cache STATIC`.

Response header:
- `X-Cache-Status` is added from `$upstream_cache_status`.

Route `cache` object (as used by Lua):
- `level`: `"bypass"` or `"standard"`
- `edgeTTL`: number (stored in `ngx.ctx.cache_edge_ttl`)
- `nonSuccessTTL`: number (stored in `ngx.ctx.cache_non_success_ttl`)
- `immutable`: boolean (stored in `ngx.ctx.cache_immutable`)

Example route with caching enabled:

```/dev/null/redis#L1-2
SET httproute:mycdn.com:prefix:/ '{
  "lb_method":"rr",
  "upstreams":[
    {"hostHeader":"example.com","protocol":"https","address":"example.com","port":443,"weight":1}
  ],
  "cache":{"level":"standard","edgeTTL":60,"nonSuccessTTL":5,"immutable":false}
}'
```

---

## TLS / SNI (optional)

There is Lua logic for dynamic certificate selection in `/app/ssl.lua` using `ngx.ssl` and shared dict caches:
- `tls_crt_cache`
- `tls_key_cache`

The dev Nginx config currently has TLS disabled (commented out). To enable TLS, you would:
- enable `listen 443 ssl;`
- set `ssl_certificate_by_lua_file /app/ssl.lua;`
- ensure certs/keys are loaded into the shared dict cache (and/or implement loading from Redis)

As committed, HTTP (`:8080` → container `:80`) is the default path.

---

## Observability

### Prometheus metrics
Metrics endpoint is exposed on port `9145`:

- `http://localhost:9145/metrics` (when running via compose)

Nginx uses `nginx-lua-prometheus`. Metrics include connection state gauges and additional counters updated by Lua (e.g., DNS query success/failure), labeled with:
- `namespace` (from gateway JSON or `"default"`)
- `cdn_gateway` (from gateway JSON `name` field when present, else `"default"`)

### Logs
- `error_log` is set to debug in dev config; logs go to stderr.

---

## Common errors

- **`gateway not found.` (404)**  
  Missing `<host>` key in Redis, or invalid JSON value.

- **`route not found.` (404)**  
  No `httproute:<host>:exact:<uri>` and no matching `httproute:<host>:prefix:<prefix>`.

- **`DNS resolution failed for all upstreams.` (502)**  
  Upstream `address` is not resolvable and no alternative upstream was usable.

- **Unexpected upstream field names**  
  Ensure your route JSON uses `address` + `hostHeader` (not `server`/`host_header`) unless you also updated the Lua code accordingly.

---

## Files to know

- `compose.yaml` — local dev stack (OpenResty + Redis)
- `config/nginx.conf.dev` — Nginx/OpenResty config used in dev container
- `app/access.lua` — gateway lookup, routing, DNS, upstream selection, cache toggles
- `app/lb.lua` — Nginx `balancer_by_lua` hook (used by `upstream backend`)
- `app/ssl.lua` — dynamic certificate selection (SNI)
- `sample-redis.txt` — example Redis keys and shapes (may include older field names)

---

## License

No license file is included in this repository as-is. Add a `LICENSE` if you intend to redistribute or open-source this project.