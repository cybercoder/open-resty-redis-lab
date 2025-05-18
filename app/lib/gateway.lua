local _GATEWAY = {}

function _GATEWAY.find(host, red)
    if not red then
        ngx.log(ngx.INFO, "no redis!")
    end
    local gateway = ngx.shared.gateway_cache:get(host)
    if not gateway then
        gateway = red:get(host)
    end
    if gateway then
        ngx.shared.gateway_cache:set(host, gateway, 300)
    end
    return gateway
end

return _GATEWAY
