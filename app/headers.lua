if ngx.var.cache_enabled == "off" then
    ngx.header["Cache-Control"] = "no-store"
    return
end
local ttls = {
    ["200"] = tostring(ngx.ctx.cache_edge_ttl) .. "s",
    ["301"] = tostring(ngx.ctx.cache_edge_ttl) .. "s",
    ["302"] = tostring(ngx.ctx.cache_edge_ttl) .. "s",
    ["304"] = tostring(ngx.ctx.cache_edge_ttl) .. "s",
    ["400"] = tostring(ngx.ctx.cache_non_success_ttl) .. "s",
    ["404"] = tostring(ngx.ctx.cache_non_success_ttl) .. "s",
}

if ttls[ngx.status] then
    ngx.header["X-Accel-Expires"] = ttls[ngx.status]
end

ngx.header["Cache-Control"] = ngx.ctx.cache_immutable and "public, immutable" or "public"
