local _M = {}
local operators = require "/app/waf/rules/operators"
local geo = require 'resty.maxminddb'
-- Available parameters
_M.parameters = {
    -- Headers
    host = function(ctx) return ctx.request.headers["Host"] end,
    user_agent = function(ctx) return ctx.request.headers["User-Agent"] end,
    referer = function(ctx) return ctx.request.headers["Referer"] end,
    cookie = function(ctx) return ctx.request.headers["Cookie"] end,

    -- URL
    url = function(ctx) return ctx.request.uri end,
    path = function(ctx) return ngx.var.uri end,
    query = function(ctx) return ngx.var.query_string end,

    -- Network
    ip = function(ctx) return ctx.request.remote_addr end,
    country = function(ctx)
        if not geo.initted() then
            geo.init({ country = "/maxminddb/GeoLite2-Country.mmdb" })
        else
            ngx.log(ngx.INFO, "GeoLite2-Country.mmdb is already initialized")
        end
        local res, err = geo.lookup(ctx.request.remote_addr)
        if not res then
            ngx.log(ngx.ERR, 'failed to lookup by ip ,reason:', err)
            return "Unknown"
        end
        return res.country.iso_code or "Unknown"
    end,

    -- Request
    method = function(ctx) return ctx.request.method end,

    -- Body
    body = function(ctx) return ctx.request.raw_body end,

    -- Specific
    arg = function(ctx, name) return ctx.request.args[name] end,
    header = function(ctx, name) return ctx.request.headers[name] end
}

function _M.evaluate_condition(condition, ctx)
    local getter = _M.parameters[condition.param]
    if not getter then
        ngx.log(ngx.ERR, "Unknown parameter: ", condition.param)
        return false
    end

    if condition.operator == "in" then
        condition.operator = "In"
    end
    local operator = operators.operators[condition.operator]
    if not operator then
        ngx.log(ngx.ERR, "Unknown operator: ", condition.operator)
        return false
    end

    local value = getter(ctx, condition.param_name)
    return operator(value, condition.value)
end

-- Evaluate AND group (all conditions must match)
function _M.evaluate_and_conditions(conditions, ctx)
    for _, condition in ipairs(conditions) do
        if not _M.evaluate_condition(condition, ctx) then
            return false
        end
    end
    return true
end

-- Evaluate rule with OR between groups, AND within groups
function _M.evaluate_rule(rule, ctx)
    if not rule.conditions or #rule.conditions == 0 then
        return false
    end

    -- OR logic: ANY group can match
    for _, condition in ipairs(rule.conditions) do
        if _M.evaluate_and_conditions(condition, ctx) then
            return true
        end
    end

    return false
end

return _M
