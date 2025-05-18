local dns = require "resty.dns.resolver"
local utils = require "/app/lib/utils"
local _M = {}

-- _M.resolver = {}

function _M.new()
    -- if _M.resolver then return _M.resolver end

    local r, err = dns:new({
        nameservers = utils.getenv("DNS_SERVERS", "8.8.8.8,8.8.4.4"),
        retrans = utils.getenv("DNS_RETRANS", "5"),
        timeout = utils.getenv("DNS_TIMEOUT", "2000")
    })

    if not r then
        ngx.log(ngx.ERR, "DNS resolver init failed:", err)
        return ngx.exit(500)
    end
    -- _M.resolver = r
end

function _M.query(address)
    _M.new()
    local answers, err = _M.resolver:query(address, { qtype = _M.resolver.TYPE_A })
    if not answers then
        answers, err = _M.resolver:query(address, { qtype = _M.resolver.TYPE_AAA })
        if not answers then
            ngx.log(ngx.ERR, "DNS query failed: ", err)
            return ngx.exit(502)
        end
    end
    if answers.errcode then
        ngx.log(ngx.ERR, "DNS error: ", answers.errstr)
        return ngx.exit(50)
    end
    return answers[1]
end

return _M
