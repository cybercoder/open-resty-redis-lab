local ssl = require("ngx.ssl")

local crt = ngx.shared.tls_crt_cache:get(ngx.var.host) or ngx.shared.tls_crt_cache:get("DEFAULT")
local key = ngx.shared.tls_key_cache:get(ngx.var.host) or ngx.shared.tls_key_cache:get("DEFAULT")

ssl.clear_certs()
ssl.set_cert(ssl.parse_pem_cert(crt))
ssl.set_priv_key(ssl.parse_pem_priv_key(key))
