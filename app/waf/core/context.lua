local _M = {}

function _M.create()
    local ctx = {
        namespace = ngx.ctx.namespace,
        cdn_gateway = ngx.ctx.cdn_gateway,
        request = {
            uri = ngx.var.request_uri,
            method = ngx.var.request_method,
            headers = ngx.req.get_headers(),
            args = ngx.req.get_uri_args(),
            remote_addr = ngx.var.remote_addr,
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
