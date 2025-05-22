local namespace = os.getenv("NAMESPACE") or "default"
local cdn_gateway = os.getenv("CDN_GATEWAY") or "default"

metric_requests:inc(1, { ngx.var.server_name, ngx.var.status, ngx.ctx.namespace or "default", ngx.ctx.cdn_gateway or "default" })
metric_latency:observe(tonumber(ngx.var.request_time), { ngx.var.server_name, ngx.ctx.namespace or "default", ngx.ctx.cdn_gateway or "default" })
