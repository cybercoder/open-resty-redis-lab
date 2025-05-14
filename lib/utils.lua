local _M = {}

function _M.is_ip(str)
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

return _M
