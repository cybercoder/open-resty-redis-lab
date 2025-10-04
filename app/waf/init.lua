local _M = {}

function _M.process(redis)
    local engine = require "/app/waf/core/engine"
    local context = require "/app/waf/core/context"

    local ctx = context.create()
    local result = engine.process(ctx, redis)

    return result == "continue"
end

return _M
