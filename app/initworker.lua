local utils = require "/app/lib/utils"
local redis = require "/app/lib/redis"
prometheus = require("prometheus").init("prometheus_metrics", { prefix = "tlscdn_" })

metric_requests = prometheus:counter(
    "nginx_http_requests_total", "Number of HTTP requests", { "host", "status", "cdn_namespace", "cdn_gateway" })
metric_latency = prometheus:histogram(
    "nginx_http_request_duration_seconds", "HTTP request latency", { "host", "cdn_namespace", "cdn_gateway" })
metric_connections = prometheus:gauge(
    "nginx_http_connections", "Number of HTTP connections", { "state", "cdn_namespace", "cdn_gateway" })
metric_url_requests = prometheus:counter(
    "nginx_http_url_requests_total", "Number of HTTP requests by URL",
    { "host", "method", "uri", "cache_status", "cdn_namespace", "cdn_gateway" })
metric_cache_status = prometheus:counter(
    "nginx_http_cache_status_total", "Number of HTTP requests by cache status",
    { "host", "status", "cdn_namespace", "cdn_gateway" })


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

-- Load Stored certificates from redis to cache

local function load_certificates_from_redis()
    local red = redis.connect()
    local cursor = "0"
    repeat
        local res, err = red:scan(cursor, "MATCH", "*:tls", "COUNT", 100)
        if not res then
            ngx.log(ngx.ERR, "Failed to scan Redis: ", err)
            return
        end

        cursor = res[1]
        local keys = res[2]

        for _, key in ipairs(keys) do
            local cert_data, err = red:hgetall(key)
            if not cert_data or #cert_data == 0 then
                ngx.log(ngx.WARN, "Empty or bad cert for key: ", key)
            else
                local obj = {}
                for i = 1, #cert_data, 2 do
                    obj[cert_data[i]] = cert_data[i + 1]
                end

                local hostname = obj.hostname
                if hostname and obj.crt and obj.key then
                    ngx.shared.tls_crt_cache:set(hostname, obj.crt)
                    ngx.shared.tls_key_cache:set(hostname, obj.key)
                    ngx.log(ngx.NOTICE, "Loaded TLS cert for host: ", hostname)
                else
                    ngx.log(ngx.ERR, "Missing fields in cert entry: ", key)
                end
            end
        end
    until cursor == "0"
end

if ngx.worker.id() == 0 then
    local ok, err = ngx.timer.at(0, function(premature)
        if not premature then
            load_certificates_from_redis()
        end
    end)
    if not ok then
        ngx.log(ngx.ERR, "Failed to create init timer: ", err)
    end
end
