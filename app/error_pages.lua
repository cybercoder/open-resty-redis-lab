local template_file = "/app/error_page_templates/5xx/fa.html"
local f = io.open(template_file, "r")

if not f then
    -- Fallback template
    ngx.say([[<h1>Server Error1</h1><p>Please try again later.</p>]])
    return
end

local template = f:read("*a")
f:close()

local vars = {
    status = ngx.var.status or "500",
    message = ngx.var.status == "504" and "Timeout" or "Server Error",
    requestid = ngx.var.request_id or "",
    request_uri = ngx.var.request_uri or "",
    timestamp = ngx.localtime(),
}

local html = template:gsub("{{(%w+)}}", function(key)
    return vars[key] or ""
end)

ngx.say(html)
