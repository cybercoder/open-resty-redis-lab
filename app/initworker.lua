prometheus = require("prometheus").init("prometheus_metrics", { prefix = "tlscdn" })

metric_requests = prometheus:counter(
    "nginx_http_requests_total", "Number of HTTP requests", { "host", "status" })
metric_latency = prometheus:histogram(
    "nginx_http_request_duration_seconds", "HTTP request latency", { "host" })
metric_connections = prometheus:gauge(
    "nginx_http_connections", "Number of HTTP connections", { "state" })
