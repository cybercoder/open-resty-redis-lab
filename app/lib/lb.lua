local resty_sha256 = require "resty.sha256"
local bit = require "bit"

local _M = {}

--[[
    Normalizes IP addresses for consistent hashing
    Handles both IPv4 and IPv6, including:
    - Lowercase conversion
    - IPv6 compression removal
    - IPv4-mapped IPv6 addresses
    - Removal of non-alphanumeric chars
]]
function _M.normalize_ip(ip)
    if not ip or ip == "" then
        return nil, "empty IP address"
    end
    local normalized = ip:lower()
    if normalized:find("::ffff:") then
        normalized = normalized:gsub("::ffff:", "")
    elseif normalized:find("::") then
        normalized = normalized:gsub("::", ":0:")
    end
    normalized = normalized:gsub(":", ""):gsub("[^%w]", "")
    return normalized
end

--[[
    IP+Port hash function
    @param client_ip : string - Client IP address
    @param client_port : number - Client port
    @param server_count : number - Number of available servers
    @return number (1-based server index) or nil, error
]]
function _M.ip_port_hash(client_ip, client_port, server_count)
    if type(client_ip) ~= "string" or client_ip == "" then
        return nil, "invalid client IP"
    end

    local normalized_ip, err = _M.normalize_ip(client_ip)

    local hash_key = normalized_ip .. "|" .. tostring(client_port)

    local sha256 = resty_sha256:new()

    sha256:update(hash_key)
    local digest = sha256:final()
    local hash = 0
    for i = 1, 8 do
        hash = bit.bor(bit.lshift(hash, 8), string.byte(digest, i))
    end
    hash = math.abs(hash) % server_count
    return hash + 1
end

return _M
