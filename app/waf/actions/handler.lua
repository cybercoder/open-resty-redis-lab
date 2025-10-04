local _M = {}

local actions = {
    deny = require "/app/waf/actions/deny",
    allow = require "/app/waf/actions/allow",
    -- captcha = require "/app/waf/actions/captcha",
    -- ratelimit = require "/app/waf/actions/ratelimit",
    -- set_cookie = require "/app/waf/actions/set_cookie",
    -- log = require "/app/waf/actions/"
}

function _M.execute(action_config, ctx, rule)
    local action = actions[action_config.type]
    if not action then
        ngx.log(ngx.ERR, "Unknown action: ", action_config.type)
        return "continue"
    end

    return action.execute(action_config, ctx, rule)
end

return _M
