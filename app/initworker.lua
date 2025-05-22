prometheus = require("prometheus").init("prometheus_metrics", { prefix = "tlscdn_" })

metric_requests = prometheus:counter(
    "nginx_http_requests_total", "Number of HTTP requests", { "host", "status", "cdn_namespace", "cdn_gateway" })
metric_latency = prometheus:histogram(
    "nginx_http_request_duration_seconds", "HTTP request latency", { "host", "cdn_namespace", "cdn_gateway" })
metric_connections = prometheus:gauge(
    "nginx_http_connections", "Number of HTTP connections", { "state", "cdn_namespace", "cdn_gateway" })
