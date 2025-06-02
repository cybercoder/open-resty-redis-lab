local cjson = require "cjson.safe"
local redis_conn = require "/app/lib/redis"
local ngx = ngx

local _M = {}

function _M.new()
    local self = {
        gateway_cache = ngx.shared.gateway_cache,
        httproute_cache = ngx.shared.httproute_cache,
        tls_crt_cache = ngx.shared.tls_crt_cache,
        tls_key_cache = ngx.shared.tls_key_cache,
        running = false
    }
    return setmetatable(self, { __index = _M })
end

function _M.start(self)
    if self.running then return true end

    local ok, err = ngx.timer.at(0, function()
        self:_run_loop()
    end)

    if not ok then
        ngx.log(ngx.ERR, "failed to create subscriber timer: ", err)
        return nil, err
    end

    self.running = true
    return true
end

function _M._run_loop(self)
    local red = redis_conn.connect()
    if not red then
        ngx.log(ngx.ERR, "failed to connect to redis in subscriber")
        ngx.timer.at(5, function() self:_run_loop() end)
        return
    end

    -- Set longer timeout for subscriber
    red:set_timeout(60000) -- 60 seconds for subscriber

    local channels = { "invalidate_gateway_cache", "invalidate_httproute_cache", "new_cert" }
    local res, err = red:subscribe(unpack(channels))
    if not res then
        ngx.log(ngx.ERR, "failed to subscribe: ", err)
        red:close() -- Use close() instead of keepalive for failed subscription
        ngx.timer.at(5, function() self:_run_loop() end)
        return
    end

    ngx.log(ngx.INFO, "Redis subscriber listening on channels: ", table.concat(channels, ", "))

    -- Track last message time for health check
    local last_message_time = ngx.now()

    while true do
        local res, err = red:read_reply()
        if not res then
            -- Check if we've gone too long without messages
            if ngx.now() - last_message_time > 30 then -- 30 seconds without messages
                ngx.log(ngx.WARN, "No messages received in 30 seconds, reconnecting...")
                break
            end

            if err ~= "timeout" then
                ngx.log(ngx.ERR, "failed to read reply: ", err)
                break
            end

            -- For timeout, just continue the loop
            ngx.log(ngx.DEBUG, "read_reply timeout, continuing...")
            goto continue
        end

        last_message_time = ngx.now()

        if type(res) == "table" and res[1] == "message" then
            local channel, key = res[2], res[3]
            if channel == "invalidate_gateway_cache" then
                self.gateway_cache:delete(key)
                ngx.log(ngx.INFO, "invalidated gateway_cache key: ", key)
            elseif channel == "invalidate_httproute_cache" then
                self.httproute_cache:delete(key)
                ngx.log(ngx.INFO, "invalidated httproute_cache key: ", key)
            elseif channel == "invalidate_cert_cache" then
                self.tls_crt_cache:delete(key)
                ngx.log(ngx.INFO, "invalidated tls crt cache:", key)
                self.tls_key_cache:delete(key)
                ngx.log(ngx.INFO, "invalidated tls key cache: ", key)
            elseif channel == "new_cert" then
                local tlsData = cjson.decode(key)
                if not tlsData then
                    ngx.log(ngx.INFO, "Invalid tls crt.", key)
                else
                    self.tls_crt_cache:set(tlsData.hostname, tlsData.crt)
                    self.tls_key_cache:set(tlsData.hostname, tlsData.key)
                end
            end
        end

        ::continue::
    end

    -- Cleanup and reconnect
    pcall(function()
        red:unsubscribe(unpack(channels))
        red:close() -- Must use close() for subscribed connections
    end)
    ngx.timer.at(1, function() self:_run_loop() end)
end

return _M
