local _M = {}

_M.operators = {
    -- String operators
    contains = function(value, pattern)
        return value and tostring(value):find(pattern, 1, true) ~= nil
    end,

    equals = function(value, pattern)
        return value and tostring(value) == tostring(pattern)
    end,

    startswith = function(value, pattern)
        return value and tostring(value):sub(1, #pattern) == pattern
    end,

    endswith = function(value, pattern)
        return value and tostring(value):sub(- #pattern) == pattern
    end,

    -- Regex
    matches = function(value, pattern)
        return value and ngx.re.find(tostring(value), pattern, "jo") ~= nil
    end,

    -- Collections
    In = function(value, pattern)
        if not value or type(pattern) ~= "table" then return false end
        local value_str = tostring(value)
        for _, item in ipairs(pattern) do
            if value_str == tostring(item) then return true end
        end
        return false
    end,

    not_in = function(value, pattern)
        return not _M.operators.In(value, pattern)
    end,

    -- Numeric
    gt = function(value, pattern)
        local num1, num2 = tonumber(value), tonumber(pattern)
        return num1 and num2 and num1 > num2
    end,

    lt = function(value, pattern)
        local num1, num2 = tonumber(value), tonumber(pattern)
        return num1 and num2 and num1 < num2
    end,

    -- Existence
    exists = function(value, pattern)
        return value ~= nil
    end,

    not_exists = function(value, pattern)
        return value == nil
    end
}

return _M
