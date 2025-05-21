local resty_sha256 = require "resty.sha256"
local bit = require "bit"

local _LB = {}

function _LB.normalize_ip(ip)
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
function _LB.ip_port_hash(client_ip, client_port, server_count)
    if type(client_ip) ~= "string" or client_ip == "" then
        return nil, "invalid client IP"
    end

    local normalized_ip, err = _LB.normalize_ip(client_ip)
    if not normalized_ip then
        return nil, err
    end

    local hash_key = normalized_ip .. "|" .. tostring(client_port)
    return _LB._hash_to_index(hash_key, server_count)
end

-- New: Hash based on IP only
function _LB.ip_hash(client_ip, servers)
    if type(client_ip) ~= "string" or client_ip == "" then
        return nil, "invalid client IP"
    end

    local normalized_ip, err = _LB.normalize_ip(client_ip)
    if not normalized_ip then
        return nil, err
    end

    -- Calculate total weight
    local total_weight = 0
    for _, server in ipairs(servers) do
        total_weight = total_weight + (tonumber(server.weight) or 1) -- Default weight=1 if missing
    end

    return _LB._hash_to_index(normalized_ip, servers)
end

-- Internal: Convert hash string to index including weight calculation.
function _LB._hash_to_index(key, servers)
    local sha256 = resty_sha256:new()
    sha256:update(key)
    local digest = sha256:final()
    local hash = 0
    for i = 1, 8 do
        hash = bit.bor(bit.lshift(hash, 8), string.byte(digest, i))
    end
    hash = math.abs(hash) % #servers

    local cumulative_weight = 0
    for i, server in ipairs(servers) do
        local weight = tonumber(server.weight) or 1
        if hash < cumulative_weight + weight then
            return i
        end
        cumulative_weight = cumulative_weight + weight
    end
    return 1
end

return _LB
