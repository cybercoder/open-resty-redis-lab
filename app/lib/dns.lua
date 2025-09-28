local dns = require "resty.dns.resolver"
local utils = require "/app/lib/utils"

local _M = {}
local resolver_instance = nil -- Worker-level singleton

-- Create a new resolver instance
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

-- Check if resolver is healthy by attempting a lightweight operation
local function is_resolver_healthy(r)
    if not r then
        return false
    end

    -- Try to get the socket from the resolver
    -- This is a low-level check to see if the underlying socket is still valid
    local sock = r.sock
    if not sock then
        return false
    end

    -- Check if socket is connected and not closed
    local ok, err = sock:getreusedtimes()
    if not ok and err == "closed" then
        return false
    end

    return true
end

-- Test resolver with a quick query to detect socket issues
local function test_resolver(r)
    if not r then
        return false, "no resolver"
    end

    -- Use a fast, reliable test query
    -- We use a short timeout for this test to fail fast
    local original_timeout = r.timeout
    r.timeout = 1000 -- 1 second timeout for health check

    local answers, err = r:query("dns.google", { qtype = r.TYPE_A })

    -- Restore original timeout
    r.timeout = original_timeout

    -- Check for connection-related errors
    if not answers then
        if err then
            local err_lower = string.lower(err)
            if err_lower:match("closed") or
                err_lower:match("connection") or
                err_lower:match("broken pipe") or
                err_lower:match("network is unreachable") then
                return false, err
            end
        end
        -- Other errors might be temporary (like DNS server busy)
        return true, "resolver ok despite query error"
    end

    -- Even if we get a DNS error response, the socket is working
    return true, "resolver healthy"
end

-- Get resolver with automatic recreation on socket failure
function _M.get_resolver()
    -- If no resolver exists, create one
    if not resolver_instance then
        local r, err = create_resolver()
        if not r then
            return nil, err
        end
        resolver_instance = r
        return resolver_instance, nil
    end

    -- Check if existing resolver is healthy using socket state
    if not is_resolver_healthy(resolver_instance) then
        ngx.log(ngx.INFO, "DNS resolver socket appears closed, recreating...")
        resolver_instance = nil
        local r, err = create_resolver()
        if not r then
            return nil, err
        end
        resolver_instance = r
        return resolver_instance, nil
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
                err_lower:match("broken pipe") or
                err_lower:match("network is unreachable")
        elseif answers and answers.errcode then
            -- DNS server returned an error code - this is not a connection error
            err = answers.errstr or ("DNS error code: " .. tostring(answers.errcode))
        end

        -- If it's a connection error, force resolver recreation and retry
        if is_connection_error and retry_count < max_retries then
            ngx.log(ngx.WARN, "DNS connection error for ", address, ", forcing resolver recreation: ", err)
            resolver_instance = nil -- Force recreation on next call
            retry_count = retry_count + 1

            -- Brief pause before retry to avoid tight loop
            if retry_count <= max_retries then
                ngx.sleep(0.01) -- 10ms pause
            end
        else
            -- Non-connection error or max retries reached
            local final_err = err or "DNS query failed"
            if retry_count > 0 then
                ngx.log(ngx.ERR, "DNS query failed for ", address, " after ", retry_count, " retries: ", final_err)
            else
                ngx.log(ngx.ERR, "DNS query failed for ", address, ": ", final_err)
            end
            return nil, final_err
        end
    end

    return nil, "DNS query failed after " .. max_retries .. " retries"
end

-- Health check function with actual socket testing
function _M.health_check()
    local r, err = _M.get_resolver()
    if not r then
        return false, err
    end

    -- Check socket health first
    if not is_resolver_healthy(r) then
        return false, "DNS resolver socket is not healthy"
    end

    -- Test with actual query
    local healthy, msg = test_resolver(r)
    return healthy, msg
end

-- Get resolver statistics
function _M.get_stats()
    local stats = {
        resolver_exists = resolver_instance ~= nil,
        socket_healthy = false,
        test_result = "not tested"
    }

    if resolver_instance then
        stats.socket_healthy = is_resolver_healthy(resolver_instance)
        local healthy, msg = test_resolver(resolver_instance)
        stats.test_result = msg or "test completed"
        stats.test_healthy = healthy
    end

    return stats
end

-- Cleanup function (for graceful shutdown)
function _M.cleanup()
    if resolver_instance then
        -- Try to properly close the socket if possible
        if resolver_instance.sock then
            pcall(function()
                resolver_instance.sock:close()
            end)
        end
        resolver_instance = nil
        ngx.log(ngx.INFO, "DNS resolver cleaned up")
    end
end

return _M
