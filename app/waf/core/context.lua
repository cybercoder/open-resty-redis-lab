local _M = {}

function _M.create()
    local headers = ngx.req.get_headers()

    -- Priority: X-Real-IP > X-Forwarded-For > remote_addr
    local client_ip = headers["X-Real-IP"]

    if not client_ip then
        local forwarded_for = headers["X-Forwarded-For"]
        if forwarded_for then
            -- X-Forwarded-For may contain a list like "client, proxy1, proxy2"
            client_ip = forwarded_for:match("([^,%s]+)")
        else
            client_ip = ngx.var.remote_addr
        end
    end

    local ctx = {
        namespace = ngx.ctx.namespace,
        cdn_gateway = ngx.ctx.cdn_gateway,
        request = {
            uri = ngx.var.request_uri,
            method = ngx.var.request_method,
            headers = headers,
            args = ngx.req.get_uri_args(),
            remote_addr = client_ip,
            host = ngx.var.host
        },
        waf = {
            score = 0,
            triggered_rules = {},
            ai_analysis = nil
        },
    }

    if ctx.request.method == "POST" then
        ngx.req.read_body()
        ctx.request.body = ngx.req.get_post_args() or {}
        ctx.request.raw_body = ngx.req.get_body_data() or ""
    end

    return ctx
end

return _M
