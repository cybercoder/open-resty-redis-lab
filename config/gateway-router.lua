local redis = require "resty.redis"
local cjson = require "cjson.safe"

local red = redis:new()
red:set_timeout(1000)

local ok, err = red:connect("redis", 6379)
if not ok then
    ngx.status = 500
    ngx.say("Redis connection failed: ", err)
    return ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
end

local host, path = ngx.var.host, ngx.var.uri
local gateway_data = red:get("gateway:" .. host)
if not gateway_data or gateway_data == ngx.null then
    ngx.status = 404
    ngx.say("Gateway not found for ", host)
    return ngx.exit(ngx.HTTP_NOT_FOUND)
end

local gateway = cjson.decode(gateway_data)
if not gateway then
    ngx.status = 500
    ngx.say("Failed to parse gateway data")
    return ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
end

local routes_data = red:get("gateway:" .. host .. ":httproutes")
if not routes_data or routes_data == ngx.null then
    ngx.status = 404
    ngx.say("HTTP routes not found for ", host)
    return ngx.exit(ngx.HTTP_NOT_FOUND)
end

local routes = cjson.decode(routes_data)
if not routes then
    ngx.status = 500
    ngx.say("Failed to parse routes")
    return ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
end

for _, route in ipairs(routes) do
    if route.route == path then
        ngx.var.upstream_url = route.protocol .. "://" .. route.upstream .. ":" .. route.port .. path
        if route.hostHeader then
            ngx.var.customhost = route.hostHeader
        end
        if route.protocol then
            ngx.var.customscheme = route.protocol
        end
        red:set_keepalive(10000, 100)
        return ngx.exec("@proxy_to_upstream")
    end
end

ngx.status = 404
ngx.say("No matching upstream for route: ", path)
return ngx.exit(ngx.HTTP_NOT_FOUND)
