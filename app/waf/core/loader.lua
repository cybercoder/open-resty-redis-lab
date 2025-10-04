local cjson = require "cjson.safe"

local _M = {}
local dict = ngx.shared.waf_rules_cache
local listener_started = false

-- Safe Redis connection
-- local function get_redis_connection()
--     local red = redis:new()
--     red:set_timeout(5000) -- Increased timeout
--     local ok, err = red:connect("127.0.0.1", 6379)
--     if not ok then
--         ngx.log(ngx.ERR, "Redis connect failed: ", err)
--         return nil, err
--     end
--     return red
-- end

function _M.load_gateway_rules(namespace, gateway, redis)
    local pattern = "waf:" .. namespace .. ":" .. gateway .. ":rule:*"
    ngx.log(ngx.DEBUG, "Loading rules for gateway: ", gateway, " from namespace: ", namespace)

    -- Use SCAN instead of KEYS to avoid blocking
    local cursor = "0"
    local keys = {}

    repeat
        local res, err = redis:scan(cursor, "MATCH", pattern, "COUNT", 100)
        if not res then
            ngx.log(ngx.ERR, "Redis scan failed: ", err)
            break
        end
        cursor = res[1]
        for i = 1, #res[2] do
            keys[#keys + 1] = res[2][i]
        end
    until cursor == "0"

    if #keys == 0 then
        ngx.log(ngx.WARN, "No keys found for pattern: ", pattern)
        return {}
    end

    -- Pipeline all GET requests
    redis:init_pipeline()
    for i = 1, #keys do
        redis:get(keys[i])
    end

    local results, err = redis:commit_pipeline()
    if not results then
        ngx.log(ngx.ERR, "Redis pipeline failed: ", err)
        return {}
    end

    -- Process results efficiently
    local all_rules = {}
    local valid_count = 0

    for i = 1, #results do
        local raw = results[i]
        local key = keys[i]

        if raw and raw ~= ngx.null then
            local ok, parsed = pcall(cjson.decode, raw)
            if ok then
                -- Efficiently merge rules without multiple table.insert calls
                if parsed.rules and type(parsed.rules) == "table" then
                    for j = 1, #parsed.rules do
                        valid_count = valid_count + 1
                        all_rules[valid_count] = parsed.rules[j]
                    end
                elseif type(parsed) == "table" then
                    valid_count = valid_count + 1
                    all_rules[valid_count] = parsed
                end
            else
                ngx.log(ngx.ERR, "Failed to parse JSON for key ", key, ": ", parsed)
            end
        end
    end

    -- Only store to dict if we have rules
    if valid_count > 0 then
        -- Encode only once for storage
        local combined_json = cjson.encode(all_rules)
        dict:set(namespace .. ":" .. gateway, combined_json)
        ngx.log(ngx.INFO, "Loaded ", valid_count, " rules for gateway: ", gateway)
    else
        ngx.log(ngx.WARN, "No valid rules found for gateway: ", gateway)
        return {}
    end

    return all_rules
end

-- Simple listener that only runs when needed
-- function _M.start_listener()
--     if listener_started then
--         return
--     end

--     local function check_for_updates(premature)
--         if premature then return end

--         local red, err = get_redis_connection()
--         if not red then
--             ngx.log(ngx.WARN, "Cannot connect to Redis for updates, will retry")
--             ngx.timer.at(10, check_for_updates) -- Retry after 10 seconds
--             return
--         end

--         -- Check if there are any pending messages without blocking
--         red:set_timeout(1000) -- Short timeout for quick check

--         local ok, err = red:subscribe("waf:rules:update")
--         if not ok then
--             ngx.log(ngx.ERR, "Subscribe failed: ", err)
--             red:close()
--             ngx.timer.at(10, check_for_updates)
--             return
--         end

--         -- Try to read one message with short timeout
--         local res, err = red:read_reply()
--         red:close() -- Always close connection after check

--         if err and err ~= "timeout" then
--             ngx.log(ngx.ERR, "Redis read_reply error: ", err)
--         end

--         if res and res[1] == "message" then
--             local ok, msg = pcall(cjson.decode, res[3])
--             if ok and msg and msg.gateway then
--                 ngx.log(ngx.INFO, "WAF rules update received for: ", msg.gateway)
--                 _M.load_gateway_rules(msg.gateway)
--             end
--         end

--         -- Check again in 30 seconds
--         ngx.timer.at(30, check_for_updates)
--     end

--     -- Start the periodic checker
--     local ok, err = ngx.timer.at(0, check_for_updates)
--     if not ok then
--         ngx.log(ngx.ERR, "Failed to start update checker: ", err)
--         return
--     end

--     listener_started = true
--     ngx.log(ngx.INFO, "WAF update checker started")
-- end

function _M.get_cached_rules(namespace, gateway, redis)
    local raw = dict:get(namespace .. ":" .. gateway)
    if raw then
        local ok, rules = pcall(cjson.decode, raw)
        if ok and rules then
            return rules
        end
    end

    -- Load rules if not cached
    local rules = _M.load_gateway_rules(namespace, gateway, redis) or {}

    -- Start update checker on worker 0
    -- if ngx.worker.id() == 0 then
    --     pcall(_M.start_listener)
    -- end

    return rules
end

return _M
