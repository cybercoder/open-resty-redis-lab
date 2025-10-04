local _M = {}

function _M.execute(action, ctx, rule)
    ngx.log(ngx.INFO, "WAF ALLOW: ", rule.name or rule.id)
    return "continue"
end

return _M
