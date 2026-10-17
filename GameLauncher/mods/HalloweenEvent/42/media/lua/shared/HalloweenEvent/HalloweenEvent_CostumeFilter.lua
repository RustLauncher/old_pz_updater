-- One sandbox string; IDs, group:<name>, category:<name>, or All.
-- Parsing is cached, so the natural spawn path does not parse per zombie.
HalloweenEvent = HalloweenEvent or {}
local HWE = HalloweenEvent
local Filter = {}
HWE.CostumeFilter = Filter
local cachedText, cachedDisabled, cachedUnknown, cachedItems
local function key(text)
    return tostring(text or ""):lower():gsub("[^%w]", "")
end
local function trim(text) return text:match("^%s*(.-)%s*$") end

function Filter.parse(text)
    local index, disabled, unknown = {}, {}, {}
    local function add(token, id)
        token = key(token)
        index[token] = index[token] or {}
        index[token][id] = true
    end
    for _, c in ipairs(HWE.Costumes or {}) do
        add(c.id, c.id); add("id:" .. c.id, c.id); add(c.name, c.id)
        add("All", c.id)
        for _, group in ipairs({c.poolFamily or "", c.poolGroup or "", c.menuGroup or ""}) do
            if group ~= "" then
                add("group:" .. group, c.id)
                -- Bare group aliases are allowed only when not an actual ID.
                if not HWE.getCostumeByID(group) then add(group, c.id) end
            end
        end
        add("category:" .. c.category, c.id)
    end
    -- Item keys use full types internally; legacy All remains costumes-only.
    for _,entry in ipairs(HWE.Items and HWE.Items.catalog or {}) do
        local ft=entry.fullType;local short=ft:match("[^.]+$")
        add(ft,ft);add(short,ft);add("item:"..short,ft);add(entry.name,ft)
        add("Items",ft);add("AllItems",ft);add("category:Items",ft);add("items:"..entry.group,ft)
    end
    for old, current in pairs(HWE.Items and HWE.Items.typeAliases or {}) do
        local short=old:match("[^.]+$")
        add(old,current);add(short,current);add("item:"..short,current)
    end
    for token in tostring(text or ""):gmatch("[^,;\r\n]+") do
        token = trim(token)
        if key(token) ~= "" then
            local matches = index[key(token)]
            if matches then
                for id in pairs(matches) do disabled[id] = true end
            else unknown[#unknown + 1] = token end
        end
    end
    return disabled, unknown
end

function Filter.current()
    local sb = SandboxVars and SandboxVars.HalloweenEvent or {}
    local text = tostring(sb.CostumeBlacklist or "")
    local itemCount=#(HWE.Items and HWE.Items.catalog or {})
    if text ~= cachedText or itemCount~=cachedItems then
        cachedItems=itemCount
        cachedText = text
        cachedDisabled, cachedUnknown = Filter.parse(text)
        local count, natural, disabledItems = 0, 0, 0
        for _, c in ipairs(HWE.Costumes or {}) do
            if cachedDisabled[c.id] then count = count + 1
            elseif c.natural then natural = natural + 1 end
        end
        for _, item in ipairs(HWE.Items and HWE.Items.catalog or {}) do
            if cachedDisabled[item.fullType] then disabledItems = disabledItems + 1 end
        end
        if HWE.log then
            HWE.log("COSTUME_FILTER disabled=" .. count .. " eligibleProfiles=" .. natural
                .. " disabledItems=" .. disabledItems .. " eligibleItems=" .. (itemCount-disabledItems)
                .. " unknown=" .. table.concat(cachedUnknown, ";")
                .. (natural == 0 and " EMPTY_POOL" or ""))
        end
    end
    return cachedDisabled, cachedUnknown
end

function Filter.isAllowed(costume)
    local disabled = Filter.current()
    return costume ~= nil and not disabled[costume.id]
end

function Filter.isItemAllowed(fullType)
    local disabled=Filter.current()
    return not disabled[fullType]
end

function Filter.serialize(disabled, unknown)
    local values, remaining, count = {}, {}, 0
    for _, c in ipairs(HWE.Costumes or {}) do
        if disabled[c.id] then remaining[c.id] = true; count = count + 1 end
    end
    if count == #(HWE.Costumes or {}) and count > 0 then
        values[1] = "All"
        remaining = {}
    else
        -- Compact complete selections: Sports takes one token rather than 16 IDs.
        local groups, ordered = {}, {}
        for _, c in ipairs(HWE.Costumes or {}) do
            for _, name in ipairs({c.poolFamily or "", c.poolGroup or "", c.menuGroup or ""}) do
                if name ~= "" then
                    if not groups[name] then groups[name] = {}; ordered[#ordered+1] = name end
                    groups[name][c.id] = true
                end
            end
        end
        table.sort(ordered)
        -- Broad Sports coverage precedes its team/sport subgroups.
        if groups.Sports then table.insert(ordered, 1, "Sports") end
        for _, name in ipairs(ordered) do
            local complete, n = true, 0
            for id in pairs(groups[name]) do
                n = n + 1
                if not remaining[id] then complete = false end
            end
            if complete and n > 1 then
                values[#values+1] = name == "Sports" and "Sports" or ("group:" .. name)
                for id in pairs(groups[name]) do remaining[id] = nil end
            end
        end
    end
    for _, c in ipairs(HWE.Costumes or {}) do
        if remaining[c.id] then values[#values + 1] = c.id end
    end
    local items=HWE.Items and HWE.Items.catalog or {};local blockedItems=0
    for _,entry in ipairs(items) do if disabled[entry.fullType] then blockedItems=blockedItems+1 end end
    if #items>0 and blockedItems==#items then values[#values+1]="Items"
    else for _,entry in ipairs(items) do
        if disabled[entry.fullType] then values[#values+1]="item:"..entry.fullType:match("[^.]+$") end
    end end
    table.sort(values)
    for _, token in ipairs(unknown or {}) do values[#values + 1] = token end
    return table.concat(values, ", ")
end
return Filter
