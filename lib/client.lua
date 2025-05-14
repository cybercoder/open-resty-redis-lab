local _M = {}

function _M.get_identifiers()
    return {
        ip = ngx.var.remote_addr,
        port = tonumber(ngx.var.remote_port) or 0,
        forwarded_for = ngx.var.http_x_forwarded_for,
        user_agent = ngx.var.http_user_agent,
        scheme = ngx.var.scheme
    }
end

return _M
