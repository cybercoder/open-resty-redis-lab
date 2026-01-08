local _ROUTER = {}

function _ROUTER.findRouteInCache(host, path)
    local route = _ROUTER._findExactPath(host, path)
    if not route or route == ngx.null then
        route = _ROUTER._findPrefixPath(host, path)
    end
    return route
end

function _ROUTER.findRouteInRedis(host, path, red)
    local route = _ROUTER._findExactPath(host, path, red)
    if not route or route == ngx.null then
        route = _ROUTER._findPrefixPath(host, path, red)
    end
    return route
end

function _ROUTER._findExactPath(host, path, red)
    if not red then
        return ngx.shared.httproute_cache:get("httproute:" .. host .. ":exact:" .. path)
    end
    local route = red:get("httproute:" .. host .. ":exact:" .. path)
    if route then
        ngx.shared.httproute_cache:set("httproute:" .. host .. ":exact:" .. path, route, 300)
    end
    return route
end

function _ROUTER._findPrefixPath(host, path, red)
    local parts = {}
    for part in path:gmatch("[^/]+") do
        table.insert(parts, part)
    end
    -- Check from longest to shortest prefix (e.g., "/a/b", then "/a", then "/")
    for i = #parts, 0, -1 do
        local prefix_path = "/" .. table.concat(parts, "/", 1, i)
        local prefix_key = "httproute:" .. host .. ":prefix:" .. prefix_path
        local route = ngx.null
        if not red then
            route = ngx.shared.httproute_cache:get(prefix_key)
        else
            route = red:get(prefix_key)
        end
        if route and route ~= ngx.null then
            ngx.shared.httproute_cache:set(prefix_key, route, 300)
            return route
        end
    end
    return ngx.null
end

return _ROUTER
