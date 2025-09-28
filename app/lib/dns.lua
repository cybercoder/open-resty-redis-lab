local dns = require "resty.dns.resolver"
local utils = require "/app/lib/utils"

local _M = {}
local resolver_instance = nil -- Worker-level singleton

-- Initialize resolver once per worker
function _M.init_resolver()
    if resolver_instance then
        return resolver_instance
    end

    local nameservers = utils.getenv("DNS_SERVERS", "8.8.8.8,8.8.4.4")
    if type(nameservers) == "string" then
        nameservers = { nameservers }
    end

    local r, err = dns:new({
        nameservers = nameservers,
        retrans = tonumber(utils.getenv("DNS_RETRANS", "5")),
        timeout = tonumber(utils.getenv("DNS_TIMEOUT", "2000"))
    })

    if not r then
        ngx.log(ngx.ERR, "DNS resolver init failed:", err)
        return nil, err
    end

    resolver_instance = r
    ngx.log(ngx.INFO, "DNS resolver initialized successfully")
    return resolver_instance
end

function _M.query(address)
    local r, err = _M.init_resolver()
    if not r then
        return nil, err
    end

    local answers, err = r:query(address, { qtype = r.TYPE_A })
    if not answers then
        -- Try AAAA record for IPv6
        answers, err = r:query(address, { qtype = r.TYPE_AAAA })
        if not answers then
            ngx.log(ngx.ERR, "DNS query failed for ", address, ": ", err)
            return nil, err
        end
    end

    if answers.errcode then
        ngx.log(ngx.ERR, "DNS error for ", address, ": ", answers.errstr)
        return nil, answers.errstr
    end

    return answers[1], nil
end

-- Cleanup function (for graceful shutdown)
function _M.cleanup()
    if resolver_instance then
        resolver_instance = nil
        ngx.log(ngx.INFO, "DNS resolver cleaned up")
    end
end

return _M
