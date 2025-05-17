local redis = require "resty.redis"

local _M = {}

function _M.connect()
    local red = redis:new()
    red:set_timeout(1000)
    local ok, err = red:connect("redis", 6379)
    if not ok then
        ngx.status = 500
        ngx.say("Redis connection failed: ", err)
        return ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
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
