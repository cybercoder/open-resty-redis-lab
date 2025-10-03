local namespace = os.getenv("NAMESPACE") or "default"
local cdn_gateway = os.getenv("CDN_GATEWAY") or "default"
local cache_status = ngx.var.upstream_cache_status or "MISS"

metric_requests:inc(1,
    { ngx.var.server_name, ngx.var.request_method, ngx.var.uri, cache_status, ngx.var.status, ngx.ctx.namespace or
    "default", ngx.ctx.cdn_gateway or "default" })
metric_latency:observe(tonumber(ngx.var.request_time),
    { ngx.var.server_name, ngx.ctx.namespace or "default", ngx.ctx.cdn_gateway or "default" })
-- Track cache status (HIT, MISS, BYPASS, etc.)

metric_url_requests:inc(1,
    { ngx.var.server_name, ngx.var.request_method, ngx.var.uri, cache_status, ngx.ctx.namespace or "default", ngx.ctx
    .cdn_gateway or
    "default" })

metric_cache_status:inc(1,
    { ngx.var.server_name, cache_status, ngx.ctx.namespace or "default", ngx.ctx.cdn_gateway or "default" })
