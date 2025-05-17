local resty_sha256 = require "resty.sha256"
local bit = require "bit"

local _M = {}

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

-- Hash based on IP + Port
function _M.ip_port_hash(client_ip, client_port, server_count)
    if type(client_ip) ~= "string" or client_ip == "" then
        return nil, "invalid client IP"
    end

    local normalized_ip, err = _M.normalize_ip(client_ip)
    if not normalized_ip then
        return nil, err
    end

    local hash_key = normalized_ip .. "|" .. tostring(client_port)
    return _M._hash_to_index(hash_key, server_count)
end

-- New: Hash based on IP only
function _M.ip_hash(client_ip, server_count)
    if type(client_ip) ~= "string" or client_ip == "" then
        return nil, "invalid client IP"
    end

    local normalized_ip, err = _M.normalize_ip(client_ip)
    if not normalized_ip then
        return nil, err
    end

    return _M._hash_to_index(normalized_ip, server_count)
end

-- Internal: Convert hash string to index
function _M._hash_to_index(key, server_count)
    local sha256 = resty_sha256:new()
    sha256:update(key)
    local digest = sha256:final()
    local hash = 0
    for i = 1, 8 do
        hash = bit.bor(bit.lshift(hash, 8), string.byte(digest, i))
    end
    hash = math.abs(hash) % server_count
    return hash + 1
end

return _M
