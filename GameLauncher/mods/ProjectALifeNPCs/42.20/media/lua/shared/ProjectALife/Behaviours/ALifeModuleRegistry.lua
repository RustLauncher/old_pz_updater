require "ProjectALife/Records/ALifeModuleSwitches"
require "ProjectALife/Behaviours/ALifeModuleRules"

ProjectALife = ProjectALife or {}

local Registry = {
    modules = {}, order = {}, disabled = {},

    generation = 1,
    chains = {},

    profileKeys = {},
}
ProjectALife.ModuleRegistry = Registry
if ProjectALife.ModuleRules ~= nil then ProjectALife.ModuleRules.bind(Registry) end

Registry.kinds = {
    doctrine = true, 
    orders = true,   
    reaction = true, 
    craft = true,    
    upkeep = true,   
}

Registry.kindMigration = {
    behavior = "doctrine",
    decision = "upkeep",
    response = "reaction",
    positioning = "craft",
    craft = "craft",
}

local dispatchKinds = { decision = true, response = true, positioning = true }
local defaultDispatch = {
    orders = "decision",
    reaction = "response",
    upkeep = "decision",
}

function Registry.resolveKind(kind)
    if Registry.kinds[kind] == true then return kind end
    return Registry.kindMigration[kind]
end

Registry.priorities = {
    orders = 10,        
    patrolRest = 92,    
    flee = 30,          
    warning = 40,       

    stance = 95,        
    activity = 94,
    investigate = 100,  
    regroup = 110,      
    scavenge = 118,     
    search = 117,      
    spread = 150,       
    healing = 90,       
    groupMarch = 200,   
    withdraw = 45,      
    stealth = 30,       
    sniper = 38,        
    ambusher = 42,      
    medic = 85,         
    cover = 50,         
    weave = 55,         
    strafe = 60,        
}

local function sortModules()
    table.sort(Registry.order, function(left, right)
        if left.priority ~= right.priority then
            return left.priority < right.priority
        end
        return left.id < right.id
    end)
end

function Registry.invalidate()
    Registry.generation = Registry.generation + 1
    Registry.chains = {}
end

local function invalidate()
    Registry.generation = Registry.generation + 1
    Registry.chains = {}
end

local function chainFor(dispatch)
    local cached = Registry.chains[dispatch]
    if cached ~= nil and cached.generation == Registry.generation then
        return cached.modules
    end
    local resolved = {}
    for _, module in ipairs(Registry.order) do
        if module.dispatch == dispatch then
            resolved[#resolved + 1] = module
        end
    end
    Registry.chains[dispatch] = { generation = Registry.generation, modules = resolved }
    return resolved
end

function Registry.register(definition)
    if type(definition) ~= "table" then return false, "definition_invalid" end
    local id = definition.id
    if type(id) ~= "string" or #id == 0 then return false, "id_invalid" end
    local authoredKind = definition.kind
    local kind = Registry.resolveKind(authoredKind)
    if kind == nil then return false, "kind_invalid" end
    local dispatch = definition.dispatch
    if dispatch == nil then
        if authoredKind == "decision" or authoredKind == "response"
                or authoredKind == "positioning" then
            dispatch = authoredKind
        else
            dispatch = defaultDispatch[kind]
        end
    end
    if dispatch ~= nil and dispatchKinds[dispatch] ~= true then
        return false, "dispatch_invalid"
    end
    if type(definition.evaluate) ~= "function" then return false, "evaluate_invalid" end
    if Registry.modules[id] ~= nil then return false, "duplicate_module:" .. id end

    local module = {
        id = id,
        label = definition.label or id,
        summary = definition.summary or "",
        kind = kind,
        dispatch = dispatch,

        primary = definition.primary == true,
        priority = tonumber(definition.priority)
            or Registry.priorities[id] or 500,
        evaluate = definition.evaluate,
    }
    Registry.modules[id] = module
    Registry.order[#Registry.order + 1] = module
    sortModules()
    if definition.defaultEnabled == false then Registry.disabled[id] = true end
    invalidate()
    return true
end

function Registry.get(id)
    return Registry.modules[id]
end

function Registry.setEnabled(id, enabled)
    if Registry.modules[id] == nil then return false end
    local wanted = (enabled == false) or nil
    if Registry.disabled[id] == wanted then return true end
    Registry.disabled[id] = wanted
    invalidate()
    return true
end

function Registry.isEnabled(id)
    if Registry.modules[id] == nil then return false end

    local switches = ProjectALife.ModuleSwitches
    if switches ~= nil and type(switches.get) == "function" then
        local wanted = switches.get(id)
        if wanted == false then return false end
    end
    return Registry.disabled[id] ~= true
end

function Registry.conductOf(actor)
    local memory = type(actor) == "table" and actor.memory or nil
    local conduct = type(memory) == "table" and memory.conduct or nil
    return type(conduct) == "string" and conduct or nil
end

function Registry.override(actor, id)
    local memory = type(actor) == "table" and actor.memory or nil
    local overrides = type(memory) == "table" and memory.moduleOverrides or nil
    if type(overrides) ~= "table" then return nil end

    local authored = overrides[id]
    if authored == false or authored == "off" then return "off" end
    if authored == true or authored == "on" then return "on" end
    return nil
end

function Registry.allows(actor, id)
    if not Registry.allowsBase(actor, id) then return false end
    local rules = ProjectALife.ModuleRules
    if rules == nil or rules.byModule[id] == nil then return true end
    return rules.permit(actor, id)
end

function Registry.allowsBase(actor, id)
    local module = Registry.modules[id]

    if module ~= nil and module.primary == true
            and Registry.conductOf(actor) ~= id then
        return false
    end
    if not Registry.isEnabled(id) then return false end
    local authored = Registry.override(actor, id)
    if authored == "off" then return false end
    if authored == "on" then return true end

    if id == "flee" and type(actor) == "table" and actor.factionId ~= nil then
        return false
    end
    local profiles = ProjectALife.BehaviorProfiles
    if profiles == nil then return true end
    return profiles.allows(actor, id) == true
end

function Registry.evaluate(kind, actor, shell, context, only)
    if dispatchKinds[kind] ~= true then return nil end
    local chain = chainFor(kind)
    local count = #chain
    if count == 0 then return nil end

    local decisions = ProjectALife.DecisionLoop
    local profile = decisions ~= nil and type(decisions.profileAdd) == "function" and type(getTimestampMs) == "function"
    for index = 1, count do
        local module = chain[index]
        if (only == nil or module.id == only) and Registry.allows(actor, module.id) then
            local startedMs = profile and getTimestampMs() or 0
            local ok, result = pcall(module.evaluate, actor, shell, context)
            if profile then
                local key = Registry.profileKeys[module.id]
                if key == nil then
                    key = "module:" .. module.id
                    Registry.profileKeys[module.id] = key
                end
                local spent = getTimestampMs() - startedMs
                decisions.profileAdd(key, spent)
                if spent > 16 then
                    local runtime = ProjectALife.Runtime
                    if runtime ~= nil and type(runtime.noteDetail) == "function" then runtime.noteDetail(key, spent) end
                end
            end
            if ok then
                if result ~= nil then return result, module.id end
            else
                Registry.lastError = module.id .. ": " .. tostring(result)
            end
        end
    end
    return nil
end

function Registry.list()
    local result = {}
    for _, module in ipairs(Registry.order) do
        result[#result + 1] = {
            id = module.id, label = module.label, kind = module.kind,
            dispatch = module.dispatch, priority = module.priority,
            summary = module.summary,
            enabled = Registry.isEnabled(module.id),
            optIn = ProjectALife.ModuleRules ~= nil and ProjectALife.ModuleRules.optIn(module.id) == true,
        }
    end
    return result
end

function Registry.reset()
    Registry.modules = {}
    Registry.order = {}
    Registry.disabled = {}
    Registry.chains = {}
    Registry.generation = Registry.generation + 1
    Registry.lastError = nil
    if ProjectALife.ModuleRules ~= nil then ProjectALife.ModuleRules.reset() end
end

return Registry
