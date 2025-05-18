local redis = require "resty.redis"
local utils = require "/app/lib/utils"

local _M = {}

function _M.connect()
    local red = redis:new()
    red:set_timeout(utils.getenv("REDIS_TIMEOUT", "1000"))
    local ok, err = red:connect(utils.getenv("REDIS_HOST", "redis"), utils.getenv("REDIS_HOST", "6379"))
    if not ok then
        ngx.status = 500
        ngx.say("Redis connection failed: ", err)
        return ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
    end
    if not utils.getenv("REDIS_PASSWORD", "") == "" then
        local res, error = red:auth(utils.getenv("REDIS_PASSWORD", ""))
        if not res then
            ngx.log(ngx.INFO, "failed to authenticate redis: ", error)
            return
        end
    end
    return red
end

function _M.close(red)
    local ok, err = red:set_keepalive(10000, 100)
    if not ok then
        ngx.log(ngx.ERR, "Failed to set Redis keepalive: ", err)
    end
end

return _M
