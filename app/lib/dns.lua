local dns = require "resty.dns.resolver"
local utils = require "/app/lib/utils"

local _M = {}
local resolver_instance = nil -- Worker-level singleton
local resolver_created_at = 0 -- Track when resolver was created
local RESOLVER_MAX_AGE = 300  -- Recreate resolver after 5 minutes

-- Initialize or recreate resolver
local function create_resolver()
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
        ngx.log(ngx.ERR, "DNS resolver creation failed: ", err)
        return nil, err
    end

    ngx.log(ngx.INFO, "DNS resolver created successfully")
    return r, nil
end

-- Get resolver with automatic recreation on failure or age
function _M.get_resolver()
    local now = ngx.now()

    -- Check if resolver needs recreation due to age
    if resolver_instance and (now - resolver_created_at) > RESOLVER_MAX_AGE then
        ngx.log(ngx.INFO, "DNS resolver aged out, recreating...")
        resolver_instance = nil
    end

    -- Create new resolver if needed
    if not resolver_instance then
        local r, err = create_resolver()
        if not r then
            return nil, err
        end
        resolver_instance = r
        resolver_created_at = now
    end

    return resolver_instance, nil
end

-- Initialize resolver once per worker
function _M.init_resolver()
    local r, err = _M.get_resolver()
    if not r then
        ngx.log(ngx.ERR, "Failed to initialize DNS resolver: ", err)
        return nil, err
    end
    return r, nil
end

function _M.query(address)
    local max_retries = 2
    local retry_count = 0

    while retry_count <= max_retries do
        local r, err = _M.get_resolver()
        if not r then
            return nil, "Failed to get DNS resolver: " .. (err or "unknown error")
        end

        -- Try A record first
        local answers, err = r:query(address, { qtype = r.TYPE_A })
        if answers and not answers.errcode then
            return answers[1], nil
        end

        -- If A record failed, try AAAA record for IPv6
        if not answers then
            answers, err = r:query(address, { qtype = r.TYPE_AAAA })
            if answers and not answers.errcode then
                return answers[1], nil
            end
        end

        -- Check if error indicates socket closure or connection issue
        local is_connection_error = false
        if err then
            local err_lower = string.lower(err)
            is_connection_error = err_lower:match("closed") or
                err_lower:match("connection") or
                err_lower:match("timeout") or
                err_lower:match("broken pipe")
        elseif answers and answers.errcode then
            -- DNS server returned an error code
            err = answers.errstr or ("DNS error code: " .. tostring(answers.errcode))
        end

        -- If it's a connection error, recreate resolver and retry
        if is_connection_error and retry_count < max_retries then
            ngx.log(ngx.WARN, "DNS connection error for ", address, ", recreating resolver: ", err)
            resolver_instance = nil -- Force recreation on next call
            retry_count = retry_count + 1
            ngx.sleep(0.001)        -- Brief pause before retry (1ms)
        else
            -- Non-connection error or max retries reached
            local final_err = err or "DNS query failed"
            ngx.log(ngx.ERR, "DNS query failed for ", address, " after ", retry_count, " retries: ", final_err)
            return nil, final_err
        end
    end

    return nil, "DNS query failed after " .. max_retries .. " retries"
end

-- Health check function to verify resolver is working
function _M.health_check()
    local r, err = _M.get_resolver()
    if not r then
        return false, err
    end

    -- Try to resolve a reliable DNS name
    local test_domain = "google.com"
    local answers, err = r:query(test_domain, { qtype = r.TYPE_A })

    if answers and not answers.errcode then
        return true, "DNS resolver healthy"
    else
        local error_msg = err or (answers and answers.errstr) or "Unknown DNS error"
        return false, "DNS health check failed: " .. error_msg
    end
end

-- Get resolver statistics
function _M.get_stats()
    return {
        resolver_age = resolver_instance and (ngx.now() - resolver_created_at) or 0,
        resolver_exists = resolver_instance ~= nil,
        max_age = RESOLVER_MAX_AGE
    }
end

-- Cleanup function (for graceful shutdown)
function _M.cleanup()
    if resolver_instance then
        resolver_instance = nil
        resolver_created_at = 0
        ngx.log(ngx.INFO, "DNS resolver cleaned up")
    end
end

return _M
