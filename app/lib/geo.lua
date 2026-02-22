local maxminddb = require 'resty.maxminddb'

local _M = {}

function _M.lookupAll(ip)
    if not maxminddb.initted() then
        maxminddb.init({
            asn = "/maxminddb/GeoLite2-ASN.mmdb",
            city = "/maxminddb/GeoLite2-City.mmdb",
            country = "/maxminddb/GeoLite2-Country.mmdb",
        })
    else
        ngx.log(ngx.INFO, "GeoLite2-Country.mmdb is already initialized")
    end
    local res, err = maxminddb.lookup(ip)
    if not res then
        return nil, err
    end
    return res, nil
end

return _M
