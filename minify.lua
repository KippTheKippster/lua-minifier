assert(type(arg[1]) == "string" and arg[1] ~= "")

local allowLog = arg[3] or false
local function log(...)
    if allowLog then
        print(...)
    end
end

local function split(str, sep)
    if sep == nil then
        sep = "%s"
    end
    local t = {}
    for s in string.gmatch(str, "([^" .. sep .. "]+)") do
        table.insert(t, s)
    end
    return t
end

local function parseSettings(text)
    local word = ""
    local j = 0
    local start = false
    while j < #text do
        local c = text:sub(j, j)
        word = word .. c
        if word == "---*" then
            word = ""
            start = true
        end

        if start and word:sub(#word - 3) == "*---" then
            return word:sub(1, #word - 4)
        end
        if c == "\n" then
            return nil
        end
        j = j + 1
    end
end

local memberRedefinable = {

}

local ioin = io.open(arg[1])
if ioin == nil then
    error("Failed to open infile")
end

local textin = ioin:read("*all")
textin = textin:gsub("\t", "")
io.close(ioin)

local settings = parseSettings(textin)
if settings then
    for i, value in ipairs(split(settings, ",")) do
        memberRedefinable[value] = true
    end
end

local ioout = io.open(arg[2] or "out.lua", "w")
if ioout == nil then
    error("Failed to open out")
end

local symbolize, newSymbol = table.unpack(require"symbolize", 1)
local serialize = require"serialize"(newSymbol, memberRedefinable, log)

local list = symbolize(textin)
local text = serialize(list)

ioout:write(text)
io.close(ioout)
