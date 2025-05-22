metric_requests:inc(1, { ngx.var.server_name, ngx.var.status })
metric_latency:observe(tonumber(ngx.var.request_time), { ngx.var.server_name })
