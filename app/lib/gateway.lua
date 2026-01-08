local _GATEWAY = {}

function _GATEWAY.findInCache(host)
    local gateway = ngx.shared.gateway_cache:get(host)
    return gateway
end

function _GATEWAY.findInRedis(host, red)
    local gateway = red:get(host)

    if gateway then
        ngx.shared.gateway_cache:set(host, gateway, 300)
    end
    return gateway
end

return _GATEWAY
