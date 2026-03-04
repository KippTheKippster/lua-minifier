return function (newSymbol, memberRedefinable, log)
local contextMap = {}

---comment
---@param startSymbol string?
---@param endSymbol string?
---@param name string
---@param canStoreVars boolean?
local function newContext(startSymbol, endSymbol, name, canStoreVars)
    ---@class Context
    local ctx = {
        startSymbol = startSymbol,
        endSymbol = endSymbol,
        name = name,
        canStoreVars = canStoreVars or false
    }

    if startSymbol then
        contextMap[startSymbol] = ctx
    end

    return ctx
end

local ctxRoot = newContext(nil, nil, "root", true)

local ctxLocal = newContext("local", nil, "local")
local ctxTable = newContext(nil, "}", "table")
local ctxTableVarDef = newContext(nil, nil, "tableVarDef")
local ctxTableVarInit = newContext(nil, nil, "tableVarInit")

local ctxFunction = newContext("function", nil, "function")
local ctxFunctionArgs = newContext(nil, nil, "functionArgs")
local ctxFunctionBody = newContext(nil, nil, "functionBody", true)

local ctxIf = newContext("if", "end", "if", true)
local ctxFor = newContext(nil, "end", "for", true)
local ctxWhile = newContext("while", "end", "while", true)
local ctxRepeat = newContext("repeat", "end", "repeat", true)
local ctxStructureArgs = newContext(nil, nil, "structureArgs")         -- If, for, while

local ctxComment = newContext(nil, nil, "comment")
local ctxCommentMulti = newContext(nil, nil, "commentMulti")
local ctxString = newContext("\"", "\"", "string")
local ctxStringSingle = newContext("'", "'", "stringSingle")
local ctxStringMulti = newContext("[[", "]]", "stringMulti")

---comment
---@param ctx Context
---@param next Scope?
---@param prev Scope?
---@param owner Symbol?
---@return Scope
local function newScope(ctx, prev, next, owner)
    ---@class Scope
    local scope = {
        ctx = ctx,
        next = next,
        prev = prev,
        vars = {},
        aliases = {},
        aliasCount = 0,
        owner = owner,
    }

    return scope
end

---comment
---@param scope Scope
local function isInCodeSpace(scope)
    local ctx = scope.ctx
    if ctx ~= ctxString and ctx ~= ctxStringSingle and ctx ~= ctxStringMulti and ctx ~= ctxComment and ctx ~= ctxCommentMulti then
        return true
    end

    return false
end

---comment
---@param scope Scope
---@param var string
local function isVarDeclared(scope, var)
    while scope ~= nil do
        if scope.vars[var] then
            return true
        end
        scope = scope.prev
    end
    return false
end

---@param list table
---@param i integer
---@return Symbol?, integer?
local function getDefiner(list, i)
    local symbol = list[i]
    while i > 0 do
        i = i - 1
        ---@type Symbol
        symbol = list[i]
        if symbol.src == "local" or symbol.type == "var" then
            return symbol
        end

        if ((symbol.type == "token" and symbol.src ~= "=" and symbol.src ~= "{") or
            symbol.type == "keyword") then
            return nil
        end
    end
    return nil
end

---@param scope Scope
---@return string?
local function getVarOwner(scope)
    if scope.ctx == ctxLocal then
        return "local"
    elseif scope.ctx == ctxTableVarDef then
        assert(scope.prev)
        if scope.prev.owner then
            return scope.prev.owner.src
        end
    end
    return nil
end

---comment
---@param list table
---@param i integer
---@return Context
local function getTableVarContext(list, i)
    while i < #list do
        i = i + 1

        ---@type Symbol
        local next = list[i]
        if next.src == "=" then
            return ctxTableVarDef
        elseif next.src == "}" then
            return ctxTableVarInit
        end
    end
    error("Unable to determine table var type (end of symbols reached)")
end

---comment
---@param scope Scope
---@return Scope
local function getRootScope(scope)
    while scope.prev ~= nil do
        scope = scope.prev
    end

    return scope
end

---comment
---@param scope Scope
---@return string
local function getScopeContextPath(scope)
    local path = ""
    while scope ~= nil do
        path = scope.ctx.name .. "/" .. path
        scope = scope.prev
    end
    return path
end


---comment
---@param scope Scope
---@param var string
---@return Scope?
local function storeVar(scope, var)
    repeat
        if scope.ctx.canStoreVars then
            scope.vars[var] = true
            log("Store var: ", getScopeContextPath(scope), var)
            return scope
        end

        scope = scope.prev
    until scope == nil
    error("Store var reached invalid scope")
end

---comment
---@param scope Scope
---@param alias string
---@return Scope?
local function storeAlias(scope, var, alias)
    repeat
        if scope.ctx.canStoreVars then
            if not scope.aliases[var] then
                scope.aliases[var] = alias
                scope.aliasCount = scope.aliasCount + 1
                return scope
            end
            return
        end

        scope = scope.prev
    until scope == nil
    error("Store alias reached invalid scope")
end

---@param scope Scope
---@param list table
---@param i integer
---@return boolean
local function isAliasAllowed(scope, list, i)
    ---@type Symbol
    local symbol = list[i]
    if symbol == nil or symbol.type ~= "var" then
        return false
    end

    ---@type Symbol
    local prevSymbol = list[i - 1]
    if prevSymbol == nil then
        return false
    end

    -- var extractors
    if (prevSymbol.src == "." or prevSymbol.src == ":" ) then
        local owner = list[i - 2]
        return memberRedefinable[getVarOwner(scope)] == true
    end

    if scope.ctx == ctxStructureArgs then
        return true
    end

    if scope.ctx == ctxLocal then
        return true
    end

    if scope.ctx == ctxTableVarDef then
        -- This doesn't work
        local owner = getVarOwner(scope)
        --print("IN DEF", owner.src)
        if memberRedefinable[owner] then
            return true
        end
        return false
    end


    return isVarDeclared(scope, symbol.src)
end

local nameCharsStart = {
    "A", "B", "C", "D", "E", "F", "G", "H", "I",
    "J", "K", "L", "M", "N", "O", "P", "Q", "R",
    "S", "T", "U", "V", "W", "X", "Y", "Z",
    "a", "b", "c", "d", "e", "f", "g", "h", "i",
    "j", "k", "l", "m", "n", "o", "p", "q", "r",
    "s", "t", "u", "v", "w", "x", "y", "z",
}

local nameChars = { "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "_", }
for i, v in ipairs(nameCharsStart) do
    table.insert(nameChars, v)
end

local function newAlias(scope, count)
    local alias = ""
    local i = count + 1
    if i < #nameCharsStart then
        alias = nameCharsStart[i]
        assert(alias, "A")
    else
        local extraI = i - #nameCharsStart
        local extraCount = 0
        while extraI >= 0 do
            extraI = extraI - #nameChars
            extraCount = extraCount + 1
        end


        local indexStart = (extraCount)
        alias = nameCharsStart[indexStart]

        assert(alias)
        i = i - #nameCharsStart
        --while i >= 0 do -- TODO RE-ADD
        --i = i - #nameChars
        local index = i % #nameChars + 1
        alias = alias .. nameChars[index]
        i = i - #nameChars
        --end
    end
    return alias
end

---comment
---@param scope Scope
---@param var string
---@param list table
---@param i integer
---@return string
local function nextAlias(scope, var, list, i)
    local owner = getVarOwner(scope)
    if owner and memberRedefinable[owner] then
        scope = getRootScope(scope)
    end

    local count = 0
    local l = scope
    while l ~= nil do
        if l.aliases[var] then
            log("Got alias:", var, l.aliases[var])
            return l.aliases[var]
        end

        count = count + l.aliasCount
        l = l.prev
    end

    local alias = newAlias(scope, count)
    local storer = storeAlias(scope, var, alias)
    if storer then
        log("New alias:", getScopeContextPath(storer), var, alias)
    end
    return alias
end

---@param scope Scope
---@param ctx Context
---@param owner Symbol?
---@return Scope, Context
local function appendScope(scope, ctx, owner)
    local next = newScope(ctx, scope, nil, owner)
    scope.next = next
    scope = next
    return scope, scope.ctx
end

---comment
---@param scope Scope
---@return Scope
---@return Context
local function detachScope(scope)
    assert(scope.prev)
    scope = scope.prev
    scope.next = nil
    return scope, scope.ctx
end


local function cleanSymbols(list)
    local cleanList = {}
    local rootScope = newScope(ctxRoot)
    local scope = rootScope
    local stringSymbol = nil
    for i, v in ipairs(list) do
        ---@type Symbol
        local symbol = v
        local skip = false
        if isInCodeSpace(scope) then
            if symbol.src == "--" then
                scope = appendScope(scope, ctxComment)
            elseif symbol.src == "--[[" then
                scope = appendScope(scope, ctxCommentMulti)
            elseif symbol.src == ctxString.startSymbol then
                stringSymbol = newSymbol("", "string")
                scope = appendScope(scope, ctxString)
                skip = true
            elseif symbol.src == ctxStringSingle.startSymbol then
                stringSymbol = newSymbol("", "string")
                scope = appendScope(scope, ctxStringSingle)
                skip = true
            elseif symbol.src == ctxStringMulti.startSymbol then
                stringSymbol = newSymbol("", "string")
                print("SETTING")
                scope = appendScope(scope, ctxStringMulti)
                skip = true
            end
        end

        log("cleaning:", "'" .. symbol.src .. "'", getScopeContextPath(scope))

        if scope.ctx == ctxString or scope.ctx == ctxStringSingle or scope.ctx == ctxStringMulti then
            assert(stringSymbol)
            stringSymbol.src = stringSymbol.src .. symbol.src
        else
            if isInCodeSpace(scope) and symbol.type ~= "format" then
                table.insert(cleanList, symbol)
            end
        end

        if skip == false then
            if symbol.src == "\n" and scope.ctx == ctxComment then
                scope = detachScope(scope)
            elseif symbol.src == "]]" and scope.ctx == ctxCommentMulti then
                scope = detachScope(scope)
            elseif symbol.src == ctxString.endSymbol and scope.ctx == ctxString then
                scope = detachScope(scope)
                table.insert(cleanList, stringSymbol)
                stringSymbol = nil
            elseif symbol.src == ctxStringSingle.endSymbol and scope.ctx == ctxStringSingle then
                scope = detachScope(scope)
                table.insert(cleanList, stringSymbol)
                stringSymbol = nil                
            elseif symbol.src == ctxStringMulti.endSymbol and scope.ctx == ctxStringMulti then
                scope = detachScope(scope)
                table.insert(cleanList, stringSymbol)
                stringSymbol = nil
            end
        end
    end

    return cleanList
end


---comment
---@param list table
local function serialize(list)
    list = cleanSymbols(list)

    local text = ""
    local rootScope = newScope(ctxRoot)
    local scope = rootScope
    local ctx = scope.ctx
    for i, v in ipairs(list) do
        ---@type Symbol
        local symbol = v
        local skip = false

        local inCodeSpace = isInCodeSpace(scope)

        -- Detach scope
        if ctx then
            if ctx.endSymbol == symbol.src then
                scope, ctx = detachScope(scope)
                skip = true -- Note: skip is used to prevent pre-mature detachment. For strings and things with the 'end' keyword
            else
                if ctx == ctxStructureArgs then
                    if symbol.type == "keyword" or symbol.src == "=" then
                        scope, ctx = detachScope(scope)
                        skip = true
                    end
                elseif ctx == ctxLocal then
                    if symbol.type == "keyword" or symbol.src == "=" then
                        scope, ctx = detachScope(scope)
                    end
                elseif ctx == ctxTableVarDef then
                    if symbol.src == "=" then
                        scope, ctx = detachScope(scope)
                        scope, ctx = appendScope(scope, ctxTableVarInit)
                    elseif symbol.src == "}" then
                        scope, ctx = detachScope(scope)
                    end
                elseif ctx == ctxTableVarInit then
                    if symbol.src == "," then
                        scope, ctx = detachScope(scope)
                    elseif symbol.src == "}" then
                        scope, ctx = detachScope(scope)
                        scope, ctx = detachScope(scope)
                    end
                elseif ctx == ctxStructureArgs then
                    if symbol.src == "=" or symbol.type == "keyword" then
                        scope, ctx = detachScope(scope)
                    end
                end
            end
        end

        -- Append scope
        local nextCtx = contextMap[symbol.src]
        if not skip and inCodeSpace then
            if nextCtx ~= nil then
                scope, ctx = appendScope(scope, contextMap[symbol.src])
            else
                --if structures[symbol.src] then -- if, while, for
                if symbol.src == "for" then
                    scope, ctx = appendScope(scope, ctxFor)
                    scope, ctx = appendScope(scope, ctxStructureArgs)
                elseif symbol.src == "{" then
                    scope, ctx = appendScope(scope, ctxTable, getDefiner(list, i))
                elseif ctx == ctxFunction then -- function declaration
                    if symbol.src == "(" then
                        scope, ctx = appendScope(scope, ctxFunctionArgs)
                    end
                elseif ctx == ctxFunctionArgs then -- function args
                    if symbol.src == ")" then
                        scope, ctx = detachScope(scope)
                        scope, ctx = appendScope(scope, ctxFunctionBody)
                    end
                elseif ctx == ctxFunctionBody then -- function body
                    if symbol.src == "end" then
                        scope, ctx = detachScope(scope)
                        scope, ctx = detachScope(scope)
                    end
                elseif ctx == ctxTable then
                    if symbol.type == "var" then
                        scope, ctx = appendScope(scope, getTableVarContext(list, i))
                    end
                end
            end
        end

        log("'" .. symbol.src .. "'", getScopeContextPath(scope))


        -- Variable declaration
        if symbol.type == "var" and inCodeSpace then
            if ctx == ctxFunction then
                storeVar(scope, symbol.src)
            elseif ctx == ctxFunctionArgs then
                storeVar(scope, symbol.src)
            elseif ctx == ctxLocal then
                storeVar(scope, symbol.src)
            elseif ctx == ctxStructureArgs then
                storeVar(scope, symbol.src)
            else
                if memberRedefinable[symbol.src] then
                    storeVar(rootScope, symbol.src)
                end
            end
        end

        local src = symbol.src

        -- Alias
        if inCodeSpace and isAliasAllowed(scope, list, i) then
            local alias = nextAlias(scope, symbol.src, list, i)
            src = alias
        end

        if symbol.type == "string" then
            text = text .. symbol.src
        else
            ---@type Symbol
            local next = list[i + 1]
            if next == nil then
                text = text .. src
            elseif symbol.src == "end" then
                text = text .. src .. "\n"
            elseif symbol.type == "var" and next.type == "var" then
                text = text .. src .. ";"
            elseif symbol.type == "var" and next.type == "token" then
                if tonumber(symbol.src) and next.src == ".." then -- Prevents '10 .. "kB"' becoming '10.."kB"' as it is invalid, it should be '10 .."kB' instead
                   text = text .. src .. " "
                else
                    text = text .. src
                end
            elseif symbol.type ~= "token" and next.type == "keyword" then
                text = text .. src .. " "
            elseif symbol.type == "keyword" and next.type ~= "token" then
                text = text .. src .. " "
            else
                text = text .. src
            end
        end
    end

    return text
end

return serialize
end