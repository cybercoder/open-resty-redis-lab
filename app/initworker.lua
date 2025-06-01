local utils = require("/app/lib/utils")
prometheus = require("prometheus").init("prometheus_metrics", { prefix = "tlscdn_" })

metric_requests = prometheus:counter(
    "nginx_http_requests_total", "Number of HTTP requests", { "host", "status", "cdn_namespace", "cdn_gateway" })
metric_latency = prometheus:histogram(
    "nginx_http_request_duration_seconds", "HTTP request latency", { "host", "cdn_namespace", "cdn_gateway" })
metric_connections = prometheus:gauge(
    "nginx_http_connections", "Number of HTTP connections", { "state", "cdn_namespace", "cdn_gateway" })


-- Initialize Redis Subscriber for cache invalidation
local subscriber_ok, subscriber = pcall(require, "/app/lib/redis_subscriber")
if not subscriber_ok then
    ngx.log(ngx.ERR, "failed to load redis_subscriber: ", subscriber)
else
    local cache_subscriber = subscriber.new()
    local ok, err = cache_subscriber:start()
    if not ok then
        ngx.log(ngx.ERR, "Failed to start Redis subscriber: ", err)
    else
        ngx.log(ngx.INFO, "Redis cache invalidation subscriber started successfully")
    end
end

-- Load Default Certificate to cache
local tls_crt = utils.read_file("/app/tls/tls.crt")
local tls_key = utils.read_file("/app/tls/tls.key")

ngx.shared.tls_crt_cache:set("DEFAULT", tls_crt)
ngx.shared.tls_key_cache:set("DEFAULT", tls_key)
