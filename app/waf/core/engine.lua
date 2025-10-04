local _M = {}

function _M.process(ctx, redis)
    -- Load modules inside function
    local loader = require "/app/waf/core/loader"
    local conditions = require "/app/waf/rules/conditions"
    local actions = require "/app/waf/actions/handler"

    local namespace = ctx.namespace
    local gateway = ctx.cdn_gateway
    local rules = loader.get_cached_rules(namespace, gateway, redis)

    -- Process rules
    for _, rule in ipairs(rules) do
        if rule.enabled ~= false and conditions.evaluate_rule(rule, ctx) then
            local result = actions.execute(rule.action, ctx, rule)
            if result ~= "continue" then
                return result
            end
        end
    end

    return "continue"
end

return _M
