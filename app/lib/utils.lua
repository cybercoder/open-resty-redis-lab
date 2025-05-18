local _M = {}

function _M.get_client_identifiers()
    return {
        ip = ngx.var.remote_addr,
        port = tonumber(ngx.var.remote_port) or 0,
        forwarded_for = ngx.var.http_x_forwarded_for,
        user_agent = ngx.var.http_user_agent,
        scheme = ngx.var.scheme
    }
end

function _M.is_ip(str)
    if not str then
        return false
    end
    -- Check IPv4 (e.g., "192.168.1.1")
    if str:match("^%d+%.%d+%.%d+%.%d+$") then
        for n in str:gmatch("%d+") do
            if tonumber(n) > 255 then return false end
        end
        return true
    end

    -- Check IPv6 (basic pattern, e.g., "::1" or "2001:db8::1")
    if str:match("^[%x:]+$") and str:match(":") then
        local colons = select(2, str:gsub(":", ""))
        return colons >= 2 and colons <= 7
    end

    return false
end

function _M.getenv(key, default)
    local val = os.getenv(key) or default
    -- If the value contains a comma, return a table
    if val and val:find(",") then
        local out = {}
        for v in val:gmatch("[^,%s]+") do
            table.insert(out, v)
        end
        return out
    end
    -- Return number if it's a numeric string (optional)
    local num = tonumber(val)
    if num then return num end
    return val
end

return _M
