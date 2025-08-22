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
    local val = os.getenv(key)

    -- Handle nil case
    if val == nil then
        return default
    end

    -- Handle empty string case (optional - depends on your needs)
    if val == "" then
        return default
    end

    -- If the value contains a comma, return a table
    if val:find(",") then
        local out = {}
        for v in val:gmatch("([^,]+)") do
            -- Trim whitespace if desired
            local trimmed = v:match("^%s*(.-)%s*$")
            table.insert(out, trimmed)
        end
        return out
    end

    -- Optional: Add a flag to control number conversion
    -- For now, let's keep it as string unless explicitly numeric
    local num = tonumber(val)
    if num and tostring(num) == val then -- Ensure it's a pure numeric string
        return num
    end

    return val
end

function _M.read_file(path)
    local file = io.open(path, "rb")
    if not file then return nil end
    local content = file:read("*a")
    file:close()
    return content
end

function _M.writeToFile(filename, content)
    local file = io.open(filename, "w") -- "w" mode overwrites the file or creates a new one
    if not file then
        error("Could not open file " .. filename .. " for writing.")
    end
    file:write(content)
    file:close()
end

return _M
