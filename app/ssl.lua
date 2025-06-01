local ssl = require("ngx.ssl")
local redis = require "/app/lib/redis"
local utils = require "/app/lib/utils"

local crt = ngx.shared.tls_crt_cache:get(ngx.var.host)
local key = ngx.shared.tls_key_cache:get(ngx.var.host)

if not crt or not key then
    local red = redis.connect()
    crt = red:get("cdngateway:" .. ngx.var.host .. ":tls:crt")
    key = red:get("cdngateway:" .. ngx.var.host .. ":tls:key")
end

if not crt or not key then
    crt = utils.read_file("/app/tls/tls.crt")
    key = utils.read_file("/app/tls/tls.key")
end

ssl.clear_certs()
ssl.set_cert(ssl.parse_pem_cert(crt))
ssl.set_priv_key(ssl.parse_pem_priv_key(key))
