require "ProjectALife/Visitors/ALifeVisitorSchema"

ProjectALife = ProjectALife or {}

local Schema = ProjectALife.VisitorSchema
local Rule = {
    MAX_LENGTH = 400,
    MAX_TOKENS = 160,
    MAX_ATOMS = 32,
    MAX_DEPTH = 10,
    cache = {},
    cacheCount = 0,
    cacheCap = 1024,
    metrics = { parsed = 0, hits = 0, errors = 0, evals = 0, unavailable = 0 },
}
ProjectALife.VisitorRule = Rule
Rule.TRUE = { t = "true" }

function Rule.tokens(text)
    local tokens, count, size, index = {}, 0, #text, 1
    while index <= size do
        local char = string.sub(text, index, index)
        if string.find(char, "%s") ~= nil then
            index = index + 1
        elseif char == "(" or char == ")" or char == "&" or char == "|" or char == "!" then
            count = count + 1
            tokens[count] = char
            index = index + 1
        else
            local stop = string.find(text, "[%s%(%)&|!]", index) or (size + 1)
            count = count + 1
            tokens[count] = { atom = string.sub(text, index, stop - 1) }
            index = stop
        end
        if count > Rule.MAX_TOKENS then return nil, "rule_too_long" end
    end
    return tokens
end

function Rule.show(token)
    if type(token) == "table" then return token.atom end
    return tostring(token)
end

function Rule.argument(spec, name, argument)
    if spec.arg == "none" then
        if argument ~= nil then return nil, "atom_arg_forbidden:" .. name end
        return true
    end
    if argument == nil or argument == "" then return nil, "atom_arg_required:" .. name end
    if spec.arg == "word" then
        if string.match(argument, "^[%w_%-]+$") == nil then return nil, "atom_arg_invalid:" .. name end
    elseif spec.arg == "id" or spec.arg == "qid" then
        if string.match(argument, "^[%w_%-%.]+$") == nil then return nil, "atom_arg_invalid:" .. name end
    elseif spec.arg == "sex" then
        if argument ~= "m" and argument ~= "f" then return nil, "atom_arg_invalid:" .. name end
    elseif spec.arg == "hours" then
        local low, high = string.match(argument, "^(%d+)%-(%d+)$")
        low, high = tonumber(low), tonumber(high)
        if low == nil or high == nil or low > 24 or high > 24 then return nil, "atom_arg_invalid:" .. name end
    end
    return true
end

function Rule.atom(text)
    local base, comparison, literal = string.match(text, "^(.-)([<>=]=?)(%-?%d+%.?%d*)$")
    if base == nil then base = text end
    local name, argument = base, nil
    local colon = string.find(base, ":", 1, true)
    if colon ~= nil then name, argument = string.sub(base, 1, colon - 1), string.sub(base, colon + 1) end
    local spec = Schema.ATOMS[name]
    if spec == nil then return nil, "atom_unknown:" .. name end
    local ok, reason = Rule.argument(spec, name, argument)
    if not ok then return nil, reason end
    if comparison == "=" then comparison = "==" end
    if spec.cmp == "none" and comparison ~= nil then return nil, "atom_cmp_forbidden:" .. name end
    if spec.cmp == "req" and comparison == nil then return nil, "atom_cmp_required:" .. name end
    local node = { t = "atom", name = name, arg = argument, cmp = comparison, num = tonumber(literal) }
    if spec.arg == "qid" then node.arg = Schema.qid(argument) end
    if spec.arg == "hours" then
        local low, high = string.match(argument, "^(%d+)%-(%d+)$")
        node.lo, node.hi = tonumber(low), tonumber(high)
    end
    return node
end

function Rule.parsePrimary(state, depth)
    local token = state.tokens[state.pos]
    if token == nil then return nil, "rule_unexpected_end" end
    if token == "(" then
        state.pos = state.pos + 1
        local inner, reason = Rule.parseOr(state, depth + 1)
        if inner == nil then return nil, reason end
        if state.tokens[state.pos] ~= ")" then return nil, "rule_unbalanced" end
        state.pos = state.pos + 1
        return inner
    end
    if type(token) == "table" then
        state.pos = state.pos + 1
        state.atoms = state.atoms + 1
        if state.atoms > Rule.MAX_ATOMS then return nil, "rule_too_many_atoms" end
        return Rule.atom(token.atom)
    end
    return nil, "rule_unexpected:" .. token
end

function Rule.parseUnary(state, depth)
    if state.tokens[state.pos] == "!" then
        state.pos = state.pos + 1
        if depth > Rule.MAX_DEPTH + 6 then return nil, "rule_too_deep" end
        local inner, reason = Rule.parseUnary(state, depth + 1)
        if inner == nil then return nil, reason end
        return { t = "not", a = inner }
    end
    return Rule.parsePrimary(state, depth)
end

function Rule.parseAnd(state, depth)
    local first, reason = Rule.parseUnary(state, depth)
    if first == nil then return nil, reason end
    if state.tokens[state.pos] ~= "&" then return first end
    local list = { first }
    while state.tokens[state.pos] == "&" do
        state.pos = state.pos + 1
        local nextNode, nextReason = Rule.parseUnary(state, depth)
        if nextNode == nil then return nil, nextReason end
        list[#list + 1] = nextNode
    end
    return { t = "and", list = list }
end

function Rule.parseOr(state, depth)
    if depth > Rule.MAX_DEPTH then return nil, "rule_too_deep" end
    local first, reason = Rule.parseAnd(state, depth)
    if first == nil then return nil, reason end
    if state.tokens[state.pos] ~= "|" then return first end
    local list = { first }
    while state.tokens[state.pos] == "|" do
        state.pos = state.pos + 1
        local nextNode, nextReason = Rule.parseAnd(state, depth)
        if nextNode == nil then return nil, nextReason end
        list[#list + 1] = nextNode
    end
    return { t = "or", list = list }
end

function Rule.compile(text)
    local trimmed = string.match(text, "^%s*(.-)%s*$")
    if trimmed == "" then return Rule.TRUE end
    local tokens, reason = Rule.tokens(trimmed)
    if tokens == nil then return nil, reason end
    local state = { tokens = tokens, pos = 1, atoms = 0 }
    local ast, parseReason = Rule.parseOr(state, 1)
    if ast == nil then return nil, parseReason end
    if state.pos <= #tokens then return nil, "rule_unexpected:" .. Rule.show(tokens[state.pos]) end
    return ast
end

function Rule.parse(text)
    if type(text) ~= "string" then return nil, "rule_not_string" end
    if #text > Rule.MAX_LENGTH then return nil, "rule_too_long" end
    local cached = Rule.cache[text]
    if cached ~= nil then
        Rule.metrics.hits = Rule.metrics.hits + 1
        if cached.ast ~= nil then return cached.ast end
        return nil, cached.err
    end
    local ast, reason = Rule.compile(text)
    if Rule.cacheCount >= Rule.cacheCap then
        Rule.cache, Rule.cacheCount = {}, 0
    end
    Rule.cache[text] = { ast = ast, err = reason }
    Rule.cacheCount = Rule.cacheCount + 1
    if ast == nil then
        Rule.metrics.errors = Rule.metrics.errors + 1
        return nil, reason
    end
    Rule.metrics.parsed = Rule.metrics.parsed + 1
    return ast
end

function Rule.numeric(value)
    if value == nil or value == false then return 0 end
    if value == true then return 1 end
    return tonumber(value)
end

function Rule.truthy(value)
    if value == true then return true end
    if type(value) == "number" then return value > 0 end
    if type(value) == "string" then return value ~= "" end
    return false
end

function Rule.compare(value, comparison, number)
    local left = Rule.numeric(value)
    if left == nil or number == nil then return false end
    if comparison == ">=" then return left >= number end
    if comparison == "<=" then return left <= number end
    if comparison == ">" then return left > number end
    if comparison == "<" then return left < number end
    return left == number
end

function Rule.inHours(hour, low, high)
    if hour == nil or low == nil or high == nil then return false end
    if low < high then return hour >= low and hour < high end
    if low > high then return hour >= low or hour < high end
    return false
end

function Rule.atomValue(node, state)
    local provider = nil
    if state.ctx ~= nil then provider = state.ctx[node.name] end
    if provider == nil then
        if state.missing == nil then state.missing = "atom_unavailable:" .. node.name end
        return false
    end
    local value = provider
    local kind = type(provider)
    if kind == "function" then
        value = provider(node.arg, node)
    elseif kind == "table" and node.arg ~= nil then
        value = provider[node.arg]
    end
    if node.cmp ~= nil then return Rule.compare(value, node.cmp, node.num) end
    return Rule.truthy(value)
end

function Rule.run(node, state)
    local kind = node.t
    if kind == "atom" then return Rule.atomValue(node, state) end
    if kind == "and" then
        local list = node.list
        for index = 1, #list do
            if not Rule.run(list[index], state) then return false end
        end
        return true
    end
    if kind == "or" then
        local list = node.list
        for index = 1, #list do
            if Rule.run(list[index], state) then return true end
        end
        return false
    end
    if kind == "not" then return not Rule.run(node.a, state) end
    if kind == "true" then return true end
    if state.missing == nil then state.missing = "rule_node_unknown" end
    return false
end

function Rule.eval(ast, ctx)
    if type(ast) ~= "table" then return false, "rule_missing" end
    Rule.metrics.evals = Rule.metrics.evals + 1
    local state = { ctx = ctx, missing = nil }
    local value = Rule.run(ast, state)
    if state.missing ~= nil then
        Rule.metrics.unavailable = Rule.metrics.unavailable + 1
        return false, state.missing
    end
    return value == true
end

function Rule.test(text, ctx)
    local ast, reason = Rule.parse(text)
    if ast == nil then return false, reason end
    return Rule.eval(ast, ctx)
end

function Rule.collect(node, into)
    local kind = node.t
    if kind == "atom" then
        into[#into + 1] = { name = node.name, arg = node.arg }
    elseif kind == "and" or kind == "or" then
        for index = 1, #node.list do Rule.collect(node.list[index], into) end
    elseif kind == "not" then
        Rule.collect(node.a, into)
    end
    return into
end

function Rule.atoms(ast)
    if type(ast) ~= "table" then return {} end
    return Rule.collect(ast, {})
end

function Rule.reset()
    Rule.cache, Rule.cacheCount = {}, 0
    Rule.metrics = { parsed = 0, hits = 0, errors = 0, evals = 0, unavailable = 0 }
end

return Rule
