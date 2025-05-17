local cjson = require "cjson.safe"
local dns = require "resty.dns.resolver"
local lb = require "/app/lib/lb"
local utils = require "/app/lib/utils"
local redis = require "/app/lib/redis"

local r, err = dns:new({
    nameservers = { "8.8.8.8", "8.8.4.4" },
    retrans = 5,
    timeout = 2000
})

if not r then
    ngx.log(ngx.ERR, "DNS resolver init failed:", err)
    return ngx.exit(500)
end
local red = redis.connect()
local host, path = ngx.var.host, ngx.var.uri
local gateway = red:get(ngx.var.host)
if not gateway then
    redis.close()
    ngx.status = 404
    ngx.say("gateway not found.")
    return ngx.exit(ngx.HTTP_NOT_FOUND)
end

local gateway_data = cjson.decode(gateway)
if not gateway_data then
    redis.close()
    ngx.status = 404
    ngx.say("gateway not found")
    return ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
end

local route = red:get("httproute:" .. host .. ":exact:" .. path)
-- local route = red:get("httproute:" .. host .. ":" .. ngx.var.uri)
if not route or route == ngx.null then
    local parts = {}
    for part in path:gmatch("[^/]+") do
        table.insert(parts, part)
    end
    -- Check from longest to shortest prefix (e.g., "/a/b", then "/a", then "/")
    for i = #parts, 0, -1 do
        local prefix_path = "/" .. table.concat(parts, "/", 1, i)
        local prefix_key = "httproute:" .. host .. ":prefix:" .. prefix_path
        route = red:get(prefix_key)

        if route and route ~= ngx.null then
            break
        end
    end
end



if not route or route == ngx.null then
    redis.close()
    ngx.status = 404
    ngx.say("route not found")
    return ngx.exit(ngx.HTTP_NOT_FOUND)
end

local ok, error = red:set_keepalive(10000, 100)
if not ok then
    ngx.log(ngx.ERR, "Failed to set Redis keepalive: ", error)
end

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
            local answers, err = r:query(upstream.address, { qtype = r.TYPE_A })
            if not answers then
                answers, err = r:query(upstream.address, { qtype = r.TYPE_AAA })
                if not answers then
                    ngx.log(ngx.ERR, "DNS query failed: ", err)
                    return ngx.exit(502)
                end
            end
            if answers.errcode then
                ngx.log(ngx.ERR, "DNS error: ", answers.errstr)
                return ngx.exit(50)
            end
            cached_ip = answers[1].address
            ngx.shared.dns_cache:set(upstream.address, cached_ip, answers[1].ttl or 300)
        end
    end
    table.insert(upstream_servers,
        { server = cached_ip, port = upstream.port, hostHeader = upstream.hostHeader, protocol = upstream.protocol })
end

local c = utils.get_client_identifiers()

local chosen_server = lb.ip_port_hash(c.ip, c.port, #upstreams)

ngx.ctx.upstream_server = upstream_servers[chosen_server].server
ngx.ctx.upstream_port = upstream_servers[chosen_server].port
ngx.ctx.upstream_protocol = upstream_servers[chosen_server].protocol
ngx.ctx.custom_host_header = upstream_servers[chosen_server].hostHeader

ngx.var.custom_host_header = upstream_servers[chosen_server].hostHeader
ngx.var.custom_scheme = upstream_servers[chosen_server].protocol
