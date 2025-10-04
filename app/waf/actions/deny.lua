local _M = {}

function _M.execute(action, ctx, rule)
    ngx.log(ngx.WARN, "WAF DENY: ", rule.name or rule.id)

    ngx.status = action.code or 403
    ngx.header["Content-Type"] = "text/html"
    ngx.say(action.message or "Request blocked by WAF")
    ngx.exit(ngx.status)

    return "deny"
end

return _M
