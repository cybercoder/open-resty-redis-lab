local ssl = require("ngx.ssl")

local server_name, err = ssl.server_name()
if not server_name then
    ngx.log(ngx.ERR, "failed to get SNI server name: ", err)
    -- return ngx.exit(ngx.ERROR)
end

local crt = ngx.shared.tls_crt_cache:get(server_name) or ngx.shared.tls_crt_cache:get("DEFAULT")
local key = ngx.shared.tls_key_cache:get(server_name) or ngx.shared.tls_key_cache:get("DEFAULT")

ssl.clear_certs()
ssl.set_cert(ssl.parse_pem_cert(crt))
ssl.set_priv_key(ssl.parse_pem_priv_key(key))
