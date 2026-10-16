ProjectALife = ProjectALife or {}

local Text = {
    cache = {}, cacheCount = 0, keys = {}, keyCount = 0, keyCap = 8192, fillVars = nil,
    prefixes = { "IGUI_", "RD_", "Sandbox_" },
    digits = "0123456789abcdef",
    metrics = { lookups = 0, engine = 0, misses = 0, badKeys = 0, serverCalls = 0, flushes = 0 },
}
ProjectALife.Text = Text

function Text.prefixOk(key)
    if type(key) ~= "string" then return false end
    for index = 1, #Text.prefixes do
        local prefix = Text.prefixes[index]
        if string.sub(key, 1, #prefix) == prefix then return true end
    end
    return false
end

function Text.flush()
    Text.cache, Text.cacheCount, Text.keys, Text.keyCount = {}, 0, {}, 0
    Text.metrics.flushes = Text.metrics.flushes + 1
end

function Text.lookup(key)
    if type(key) ~= "string" then return nil end
    Text.metrics.lookups = Text.metrics.lookups + 1
    local cached = Text.cache[key]
    if cached == false then return nil end
    if cached ~= nil then return cached end
    local value = nil
    if not Text.prefixOk(key) then
        Text.metrics.badKeys = Text.metrics.badKeys + 1
    elseif type(getTextOrNull) == "function" then
        Text.metrics.engine = Text.metrics.engine + 1
        local ok, result = pcall(getTextOrNull, key)

        if ok and type(result) == "string" and result ~= "" and result ~= key then value = result end
    end
    if Text.cacheCount >= Text.keyCap then Text.flush() end
    Text.cacheCount = Text.cacheCount + 1
    if value == nil then
        Text.metrics.misses = Text.metrics.misses + 1
        Text.cache[key] = false
        return nil
    end
    Text.cache[key] = value
    return value
end

function Text.replace(name)
    local value = nil
    if Text.fillVars ~= nil then value = Text.fillVars[name] end
    if value == nil then return "{" .. name .. "}" end
    return tostring(value)
end

function Text.fill(template, vars)
    if type(template) ~= "string" or type(vars) ~= "table" then return template end
    if string.find(template, "{", 1, true) == nil then return template end
    Text.fillVars = vars
    local out = string.gsub(template, "{([a-z]+)}", Text.replace)
    Text.fillVars = nil
    return out
end

function Text.hex8(value)
    local out = ""
    for _ = 1, 8 do
        local digit = value % 16
        out = string.sub(Text.digits, digit + 1, digit + 1) .. out
        value = math.floor(value / 16)
    end
    return out
end

function Text.hash(text)
    local a, b = 5381.0, 52711.0
    for index = 1, #text do
        local c = string.byte(text, index)
        a = (a * 33 + c) % 2147483647
        b = (b * 131 + c) % 2147483629
    end
    return Text.hex8(a) .. Text.hex8(b)
end

function Text.key(prefix, en, ctx)
    if ctx ~= nil then return prefix .. Text.hash(tostring(ctx) .. "|" .. en) end
    local memo = Text.keys[prefix]
    if memo == nil then memo = {}; Text.keys[prefix] = memo end
    local key = memo[en]
    if key ~= nil then return key end
    if Text.keyCount >= Text.keyCap then
        Text.flush()
        memo = {}
        Text.keys[prefix] = memo
    end
    key = prefix .. Text.hash(en)
    memo[en] = key
    Text.keyCount = Text.keyCount + 1
    return key
end

function Text.noteServer()
    if type(isServer) == "function" and isServer() then Text.metrics.serverCalls = Text.metrics.serverCalls + 1 end
end

function Text.get(key, en, vars)
    local template = Text.lookup(key)
    if template == nil then template = en end
    if template == nil then return key end
    return Text.fill(template, vars)
end

function Text.ui(en, vars, ctx)
    if type(en) ~= "string" or en == "" then return en end
    Text.noteServer()
    local template = Text.lookup(Text.key("IGUI_ALifeUI_", en, ctx))
    if template == nil then template = en end
    return Text.fill(template, vars)
end

function Text.line(en) return en end

function Text.lineKey(en) return Text.key("RD_ALifeLine_", en) end

function Text.radio(en, vars)
    if type(en) ~= "string" or en == "" then return en end
    local template = Text.lookup(Text.key("RD_ALifeRadio_", en))
    if template == nil then template = en end
    return Text.fill(template, vars)
end

function Text.isFemale(shell) return shell:isFemale() end

function Text.female(shell)
    local kind = type(shell)
    if kind == "nil" or kind == "number" or kind == "string" or kind == "boolean" then return false end
    if type(shell.isFemale) ~= "function" then return false end
    local ok, female = pcall(Text.isFemale, shell)
    return ok and female == true
end

function Text.speech(text, line, shell)
    local key, vars = nil, nil
    if type(line) == "table" then key, vars = line.k, line.v end
    if type(key) ~= "string" then
        if type(text) ~= "string" or text == "" then return text end
        key = Text.lineKey(text)
    end
    local template = nil
    if Text.female(shell) then template = Text.lookup(key .. "_f") end
    if template == nil then template = Text.lookup(key) end
    if template == nil then return text end
    if string.find(template, "{", 1, true) == nil then return template end
    local speech = ProjectALife.Speech
    if speech ~= nil and type(speech.render) == "function" then
        local rendered = speech.render(template, vars, shell, true)
        if type(rendered) == "string" then return rendered end
    end
    return text
end

function Text.spoken(text, shell, line)
    if type(isServer) == "function" and isServer() then return text end
    return Text.speech(text, line, shell)
end

function Text.msg(en, vars, ctx) return { en = en, v = vars, c = ctx } end

function Text.show(value)
    if type(value) == "table" then return Text.ui(value.en, value.v, value.c) end
    return Text.ui(value)
end

function Text.forPlayer(en, vars, ctx)
    if type(isServer) == "function" and isServer() then return Text.fill(en, vars) end
    return Text.ui(en, vars, ctx)
end

function Text.reset()
    Text.cache, Text.cacheCount, Text.keys, Text.keyCount, Text.fillVars = {}, 0, {}, 0, nil
    Text.metrics = { lookups = 0, engine = 0, misses = 0, badKeys = 0, serverCalls = 0, flushes = 0 }
end

return Text
