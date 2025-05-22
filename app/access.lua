local cjson = require "cjson.safe"
local dns = require "/app/lib/dns"
local lb = require "/app/lib/lb"
local utils = require "/app/lib/utils"
local redis = require "/app/lib/redis"
local router = require "/app/lib/router"
local gw = require "/app/lib/gateway"

local red = redis.connect()
local host, path = ngx.var.host, ngx.var.uri
if not red then
    ngx.log(ngx.INFO, "No REDIS")
end
local gateway = gw.find(host, red)

if not gateway then
    redis.close(red)
    ngx.status = 404
    ngx.say("gateway not found.")
    return ngx.exit(ngx.HTTP_NOT_FOUND)
end

local gateway_data = cjson.decode(gateway)
if not gateway_data then
    redis.close(red)
    ngx.status = 404
    ngx.say("gateway not found")
    return ngx.exit(ngx.HTTP_NOT_FOUND)
end

-- Store namespace and cdn_gateway for metrics
ngx.ctx.namespace = gateway_data.namespace or "default"
ngx.ctx.cdn_gateway = gateway_data.name or "default"

local route = router.findRoute(host, path, red)

if not route or route == ngx.null then
    redis.close(red)
    ngx.status = 404
    ngx.say("route not found")
    return ngx.exit(ngx.HTTP_NOT_FOUND)
end

redis.close(red)

local route_data = cjson.decode(route)
if not route_data then
    ngx.status = 500
    ngx.say("Failed to parse route.")
    return ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
end

local upstream_servers = {}
local upstreams = route_data.upstreams

if #upstreams == 0 then
    ngx.status = 404
    ngx.say("No upstream for route: ", path)
    return ngx.exit(ngx.HTTP_NOT_FOUND)
end
for _, upstream in ipairs(upstreams) do
    local cached_ip = ngx.shared.dns_cache:get(upstream.address)
    if not cached_ip then
        if utils.is_ip(upstream.address) then
            cached_ip = upstream.address
        else
            local answer = dns.query(upstream.address)
            cached_ip = answer.address
            ngx.shared.dns_cache:set(upstream.address, cached_ip, answer.ttl or 300)
        end
    end
    table.insert(upstream_servers,
        { server = cached_ip, port = upstream.port, hostHeader = upstream.hostHeader, protocol = upstream.protocol })
end

local c = utils.get_client_identifiers()

local chosen_server = lb.ip_hash(c.ip, upstreams)


ngx.ctx.upstream_server = upstream_servers[chosen_server].server
ngx.ctx.upstream_port = upstream_servers[chosen_server].port
ngx.ctx.upstream_protocol = upstream_servers[chosen_server].protocol
ngx.ctx.custom_host_header = upstream_servers[chosen_server].hostHeader

ngx.var.custom_host_header = upstream_servers[chosen_server].hostHeader
ngx.var.custom_scheme = upstream_servers[chosen_server].protocol

-- cache settings
if not route_data.cache then
    ngx.var.cache_enabled = "off"
    return
end
if route_data.cache.level == "bypass" then
    ngx.var.cache_enabled = "off"
    return
end

if route_data.cache.level == "standard" then
    ngx.var.cache_enabled = "STATIC"
end
ngx.log(ngx.INFO, cjson.encode(route_data.cache))

ngx.ctx.cache_edge_ttl = route_data.cache.edgeTTL or 0
ngx.ctx.cache_non_success_ttl = route_data.cache.nonSuccessTTL or 0
ngx.ctx.cache_immutable = route_data.cache.immutable or false
