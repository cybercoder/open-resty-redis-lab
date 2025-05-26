local redis = require "resty.redis"
local utils = require "/app/lib/utils"

local _M = {}

function _M.connect()
    local red = redis:new()
    red:set_timeout(utils.getenv("REDIS_TIMEOUT", "1000"))
    
    local ok, err = red:connect(utils.getenv("REDIS_HOST", "redis"), 
                      utils.getenv("REDIS_PORT", "6379"))
    if not ok then
        ngx.log(ngx.ERR, "Redis connection failed: ", err)
        return nil, err
    end

    local redis_password = utils.getenv("REDIS_PASSWORD", "")
    if redis_password and redis_password ~= "" then
        local res, err = red:auth(redis_password)
        if not res then
            ngx.log(ngx.ERR, "failed to authenticate redis: ", err)
            red:close()
            return nil, err
        end
    end
    
    return red
end

function _M.close(red)
    -- Check if connection is in subscribed state
    local subscribed = red:get_reused_times() == -1  -- -1 indicates subscribed state
    
    if subscribed then
        -- Can't use keepalive for subscribed connections
        local ok, err = red:close()
        if not ok then
            ngx.log(ngx.ERR, "failed to close subscribed redis connection: ", err)
        end
    else
        -- Normal keepalive for non-subscribed connections
        local ok, err = red:set_keepalive(10000, 100)
        if not ok then
            ngx.log(ngx.ERR, "failed to set Redis keepalive: ", err)
        end
    end
end

return _M