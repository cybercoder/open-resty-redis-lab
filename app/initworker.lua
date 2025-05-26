prometheus = require("prometheus").init("prometheus_metrics", { prefix = "tlscdn_" })

metric_requests = prometheus:counter(
    "nginx_http_requests_total", "Number of HTTP requests", { "host", "status", "cdn_namespace", "cdn_gateway" })
metric_latency = prometheus:histogram(
    "nginx_http_request_duration_seconds", "HTTP request latency", { "host", "cdn_namespace", "cdn_gateway" })
metric_connections = prometheus:gauge(
    "nginx_http_connections", "Number of HTTP connections", { "state", "cdn_namespace", "cdn_gateway" })

local redis_lib = require "/app/lib/redis"
local cjson = require "cjson.safe"

local function cache_invalidator(premature)
    if premature then return end
    local red = redis_lib.connect()
    if not red then
        ngx.log(ngx.ERR, "Failed to connect to Redis for cache invalidation")
        ngx.timer.at(1, cache_invalidator)
        return
    end
    local ok, err = red:subscribe("cache_invalidate")
    if not ok then
        ngx.log(ngx.ERR, "Failed to subscribe: ", err)
        redis_lib.close(red)
        ngx.timer.at(1, cache_invalidator)
        return
    end
    while true do
        local res, err = red:read_reply()
        if not res then
            ngx.log(ngx.ERR, "Failed to read pubsub reply: ", err)
            break
        end
        if res[1] == "message" then
            local msg = cjson.decode(res[3])
            if msg and msg.type and msg.key then
                if msg.type == "gateway" then
                    ngx.shared.gateway_cache:delete(msg.key)
                    ngx.log(ngx.INFO, "Invalidated gateway_cache: " .. msg.key)
                elseif msg.type == "httproute" then
                    ngx.shared.httproute_cache:delete(msg.key)
                    ngx.log(ngx.INFO, "Invalidated httproute_cache: " .. msg.key)
                end
            end
        end
    end
    redis_lib.close(red)
    ngx.timer.at(1, cache_invalidator)
end

if ngx.worker.id() == 0 then
    ngx.timer.at(0, cache_invalidator)
end
