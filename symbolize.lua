local function toMap(list)
    local map = {}
    for _, v in ipairs(list) do
        map[v] = true
    end
    return map
end

local keywords = toMap {
    "and", "break", "do", "else", "elseif",
    "end", "false", "for", "function", "if",
    "in", "local", "nil", "not", "or",
    "repeat", "return", "then", "true", "until", "while",
    "self",
}

local tokens = toMap {
    "+", "-", "*", "/", "%", "^", "#",
    "==", "~=", "<=", ">=", "<", ">", "=",
    "(", ")", "{", "}", "[", "]",
    ";", ":", ",", ".", "..", "...",
    "\'", "\"",
    "[[", "]]",
}

local formats = toMap {
    " ", "\n", "--", "--[["
}

local function newSymbol(src, type)
    ---@class Symbol
    local symbol = {
        src = src,
        type = type
    }
    return symbol
end

---comment
---@param text string
---@param i integer
---@return string?, integer?
local function parseToken(text, i)
    ---comment
    ---@param o integer?
    ---@return string
    local function peek(o)
        o = o or 0
        local c = text:sub(i + o, i + o)
        return c
    end

    if peek() == "-" then
        if peek(1) == "-" then
            return nil, nil
        else
            return "-"
        end
    end

    if peek() == "=" then
        if peek(1) == "=" then
            return "==", 1
        else
            return "="
        end
    end

    if peek() == "~" then
        if peek() == "=" then
            return "~=", 1
        else
            return "~"
        end
    end

    if peek() == "<" then
        if peek() == "=" then
            return "<=", 1
        else
            return "<"
        end
    end

    if peek() == ">" then
        if peek() == "=" then
            return ">=", 1
        else
            return ">"
        end
    end

    if peek() == "." then
        if peek(1) == "." then
            if peek(2) == "." then
                return "...", 2
            else
                return "..", 1
            end
        else
            return "."
        end
    end

    -- Should this be format, token or something else?
    if peek() == "[" then
        if peek(1) == "[" then
            return "[[", 1
        end
    end

    if peek() == "]" then
        if peek(1) == "]" then
            return "]]", 1
        end
    end

    local t = tokens[peek(0)]
    if t == true then
        return peek(0)
    end
end

---@param text string
---@param i integer
---@return string?, integer?
local function parseFormats(text, i)
    ---comment
    ---@param o integer?
    ---@return string
    local function peek(o)
        o = o or 0
        local c = text:sub(i + o, i + o)
        return c
    end

    if peek() == "\n" then
        return "\n", 0
    end

    if peek() == " " then
        return " ", 0
    end

    if peek() == "-" then
        if peek(1) == "-" then
            if peek(2) == "[" then
                if peek(3) == "[" then
                    return "--[[", 3
                end
            end
            return "--", 1
        else
            return
        end
    end

    local f = formats[peek(0)]
    if f == true then
        return peek(0)
    end
end

---comment
---@param text string
---@param i integer
---@return string?, integer?, string?
local function parseIdentifier(text, i)
    local format, of = parseFormats(text, i)
    if format ~= nil then
        return format, of, "format"
    end

    local token, ot = parseToken(text, i)
    if token ~= nil then
        return token, ot, "token"
    end
end

---comment
---@param text string
local function symbolize(text)
    local symbols = {}
    local word = ""
    local i = 0
    while i <= #text do
        i = i + 1
        local c = text:sub(i, i)
        local ident, o, type = parseIdentifier(text, i)
        if ident ~= nil or i == #text + 1 then
            if word ~= "" then
                if keywords[word] == true then
                    table.insert(symbols, newSymbol(word, "keyword"))
                else
                    table.insert(symbols, newSymbol(word, "var"))
                end
                word = ""
            end

            if ident then
                table.insert(symbols, newSymbol(ident, type))
            end

            if o then
                i = i + o
            end
        else
            word = word .. c
        end
    end

    return symbols
end

return {symbolize, newSymbol}