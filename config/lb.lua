local balancer = require "ngx.balancer"
ngx.log(ngx.INFO, "balancer module loaded:", ngx.ctx.upstream_server)
local ok, err = balancer.set_current_peer(ngx.ctx.upstream_server, ngx.ctx.upstream_port, ngx.ctx.custom_host_header)
if not ok then
    ngx.status = 500
    -- ngx.say("failed to set peer by the lb:", err)
    return ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR, err)
end

ok, err = balancer.set_upstream_tls(ngx.ctx.upstream_protocol == "https")
if not ok then
    ngx.status = 500
    return ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR, err)
end
