
--- @class IASurfaceProfile
--- @field zmin number
--- @field zmax number
--- @field xmin number
--- @field xmax number
--- @field ymin number
--- @field ymax number

--- @class IAArrangableProfile
--- @field dx number
--- @field dy number
--- @field dz number
--- @field mx number?
--- @field my number?
--- @field mz number?
--- @field qz number?
--- @field fx number?
--- @field fy number?
--- @field fz number?

---@class CAIAE_MeshProfile
---@field p   string arrangableProfile key
---@field s?  number model scale the profile was measured at
---@field dx? number x distance
---@field dy? number y distance (top left to right)
---@field dz? number z distance (vertical)
---@field mz? number
---@field qz? number
---@field fx? number
---@field fy? number
---@field fz? number


---@class ItemArrangeMod
---@field surfaceProfile table<string, table<integer, IASurfaceProfile>>
---@field surfaces table<string, table<integer, IASurfaceProfile>>
---@field arrangables table<string, IAArrangableProfile>
---@field arrangableProfile table<string, IAArrangableProfile>
---@field meshProfiles table<string, string | CAIAE_MeshProfile>
---@field meshProfilesApplied boolean
---@field meshProfilesAdded table<string, IAArrangableProfile>
---@field applyMeshProfiles fun(): void
IA = IA or {}

---@type table<string, string | CAIAE_MeshProfile>
IA.meshProfiles = {}

IA.meshProfilesApplied = false

local p = "CAItemArrangeExtension"

---@class CAIAE_WorldMesh
---@field mesh        string
---@field modelScript ModelScript
---@field scale?      number parsed on first use, see getMeshScale

---@class CAIAE_ScaledProfileName
---@field name  string
---@field scale number

---@class CAIAE_LearnedProfile
---@field name      string
---@field worldMesh CAIAE_WorldMesh

---@type table<string, CAIAE_WorldMesh | false>
local meshCache = {}

local SCALE_EPSILON = 0.0001

---@type table<string, IAArrangableProfile>
local scaledProfiles = {}

--- mesh@profile@ratio -> profile with the mesh's overrides applied.
---@type table<string, IAArrangableProfile>
local overriddenProfiles = {}

--- keys of a `CAIAE_MeshProfile` that aren't profile fields.
local MESH_PROFILE_KEYS = { profile = true, scale = true }

--- mesh -> candidates with their scales, built once per mesh.
---@type table<string, CAIAE_ScaledProfileName[]>
local candidateCache = {}

---@param value number
---@param ratio number
---@return number
local function scaleDimension(value, ratio)
  return math.floor(value * ratio * 1000 + 0.5) / 1000
end

---@param source Item | InventoryItem
---@return string | nil
local function getStaticModel(source)
  local model = source:getWorldStaticModel()

  if not model or model == "" then
    model = source:getStaticModel()
  end

  if not model or model == "" then
    return nil
  end

  return model
end

--- some items (e.g. weapons) only resolve their model on the instance, so fall back to a temporary one.
---@param item Item
---@return string | nil
local function getWorldModel(item)
  local model = getStaticModel(item)

  if model then
    return model
  end

  local ok, result = pcall(function ()
    local instance = instanceItem(item)

    return instance and getStaticModel(instance)
  end)

  -- the instance was never added to a container, so dropping the reference is enough for it to be collected
  return ok and result or nil
end

---@param line string
---@param char string
---@return number
local function countChar(line, char)
  local _, count = line:gsub(char, "")

  return count
end

---@param body  string
---@param scale number
---@return number
local function parseScale(body, scale)
  body = body:lower()

  -- also covers undocorescale
  if not body:find("scale", 1, true) then
    return scale
  end

  local undoCoreScale = false
  local attachmentDepth
  local attachmentOpened = false

  body = body:gsub("/%*.-%*/", "")

  for line in (body .. "\n"):gmatch("([^\r\n]*)\r?\n") do

    if not attachmentDepth and line:match("^%s*attachment[%s{]") then
      attachmentDepth = 0
      attachmentOpened = false
    end

    if attachmentDepth then
      local opens = countChar(line, "{")

      attachmentDepth = attachmentDepth + opens - countChar(line, "}")
      attachmentOpened = attachmentOpened or opens > 0

      if attachmentOpened and attachmentDepth <= 0 then
        attachmentDepth = nil
      end
    else
      for entry in line:gmatch("[^,{}]+") do
        local key, value = entry:match("^%s*(%w+)%s*=%s*(%S+)")

        if key == "scale" then
          scale = tonumber(value) or scale
        elseif key == "undocorescale" then
          undoCoreScale = value == "true"
        end
      end
    end
  end

  if undoCoreScale then
    scale = scale * 0.6666667
  end

  return scale
end

--- scale has no getter and reflection only works in debug mode, so it's parsed from the model's script text.
---@param modelScript ModelScript
---@return number
local function getModelScale(modelScript)
  local ok, scale = pcall(function ()
    local bodies = modelScript:getLoadedScriptBodies()
    local result = 1

    -- flat list of mod id, body, mod id, body, ...
    for i = 1, bodies:size() - 1, 2 do
      result = parseScale(bodies:get(i), result)
    end

    return result
  end)

  if not ok or not scale or scale <= 0 then
    return 1
  end

  return scale
end

--- The mesh of the item's world model and the scale the model script renders it at. different model scripts often
--- point at the same mesh, so this matches more items than the model name would.
---@param sm   ScriptManager
---@param item Item
---@return CAIAE_WorldMesh | nil
local function getWorldMesh(sm, item)
  local model = getWorldModel(item)

  if not model then
    return nil
  end

  local worldMesh = meshCache[model]

  if worldMesh == nil then
    local modelScript = sm:getModelScript(model)
    local mesh = modelScript and modelScript:getMeshName()

    if mesh and mesh ~= "" then
      worldMesh = { mesh = mesh, modelScript = modelScript }
    else
      worldMesh = false
    end

    meshCache[model] = worldMesh
  end

  return worldMesh or nil
end

--- parsing the script text is slow, so this only runs for meshes that have a sized profile.
---@param worldMesh CAIAE_WorldMesh
---@return number
local function getMeshScale(worldMesh)
  if not worldMesh.scale then
    worldMesh.scale = getModelScale(worldMesh.modelScript)
  end

  return worldMesh.scale
end

---@return table<table, string>
local function getProfileNames()
  local names = {}

  for name, profile in pairs(IA.arrangableProfile) do
    names[profile] = name
  end

  return names
end

--- get mesh -> profile mappings from items already registered with IA, one per model. scales are resolved later,
--- only for the meshes that are actually needed.
---@param sm ScriptManager
---@return table<string, CAIAE_LearnedProfile[]>
local function learnMeshProfiles(sm)
  local profileNames = getProfileNames()
  local learned = {}
  local seen = {}

  -- no scales here, writing them would mean parsing every model's script
  local fileWriter = isDebugEnabled() and getFileWriter(p .. "_meshes.txt", true, false) or nil

  for fullType, profile in pairs(IA.arrangables) do
    local name = profileNames[profile]
    local item = name and sm:getItem(fullType)
    local worldMesh = item and getWorldMesh(sm, item)

    if worldMesh and not seen[worldMesh] then
      seen[worldMesh] = true

      local entries = learned[worldMesh.mesh]

      if not entries then
        entries = {}
        learned[worldMesh.mesh] = entries
      end

      entries[#entries + 1] = { name = name, worldMesh = worldMesh }

      if fileWriter then
        fileWriter:writeln(
          string.format('IA.meshProfiles["%-50s = "%s" -- %s', worldMesh.mesh .. '"]', name, fullType)
        )
      end
    end
  end

  if fileWriter then
    fileWriter:close()
  end

  return learned
end

---@param name  string
---@param ratio number
---@return IAArrangableProfile | nil
local function getScaledProfile(name, ratio)
  local profile = IA.arrangableProfile[name]

  if not profile then
    return nil
  end

  local key = name .. "@" .. string.format("%.3f", ratio)
  local scaled = scaledProfiles[key]

  if not scaled then
    scaled = {
      dx = scaleDimension(profile.dx, ratio),
      dy = scaleDimension(profile.dy, ratio),
      dz = scaleDimension(profile.dz, ratio),
    }

    for k, v in pairs(profile) do
      if scaled[k] == nil then
        scaled[k] = v
      end
    end

    if profile.mz then scaled.mz = scaleDimension(profile.mz, ratio) end
    if profile.mx then scaled.mx = scaleDimension(profile.mx, ratio) end
    if profile.my then scaled.my = scaleDimension(profile.my, ratio) end

    scaledProfiles[key] = scaled
  end

  return scaled
end

---@param learned table<string, CAIAE_LearnedProfile[]>
---@param mesh    string
---@return CAIAE_ScaledProfileName[]
local function getCandidates(learned, mesh)
  local candidates = candidateCache[mesh]

  if candidates then
    return candidates
  end

  candidates = {}

  local manual = IA.meshProfiles[mesh]

  if type(manual) == "table" and manual.p and manual.s then
    candidates[1] = { name = manual.p, scale = manual.s }
  end

  local entries = learned[mesh]

  if entries then
    for i = 1, #entries do
      local entry = entries[i]

      candidates[#candidates + 1] = { name = entry.name, scale = getMeshScale(entry.worldMesh) }
    end
  end

  candidateCache[mesh] = candidates

  return candidates
end

---@param learned   table<string, CAIAE_LearnedProfile[]>
---@param worldMesh CAIAE_WorldMesh
---@return IAArrangableProfile?, string?, number?
local function resolveBaseProfile(learned, worldMesh)
  local manual = IA.meshProfiles[worldMesh.mesh]

  if type(manual) == "string" then
    return IA.arrangableProfile[manual], manual, 1
  end

  if type(manual) == "table" and manual.p and not manual.s then
    return IA.arrangableProfile[manual.p], manual.p, 1
  end

  local candidates = getCandidates(learned, worldMesh.mesh)

  if #candidates == 0 then
    return nil, nil, nil
  end

  local scale = getMeshScale(worldMesh)
  ---@type CAIAE_ScaledProfileName
  local best
  ---@type number
  local bestDistance

  for i = 1, #candidates do
    local candidate = candidates[i]

    ---@diagnostic disable-next-line: unnecessary-if
    if IA.arrangableProfile[candidate.name] then
      local distance = math.abs(math.log(scale / candidate.scale))

      if not best or distance < bestDistance - SCALE_EPSILON then
        best = candidate
        bestDistance = distance
      end
    end
  end

  if not best then
    return nil, nil, nil
  end

  local ratio = scale / best.scale

  if math.abs(ratio - 1) < SCALE_EPSILON then
    return IA.arrangableProfile[best.name], best.name, 1
  end

  return getScaledProfile(best.name, ratio), best.name, ratio
end

--- copy of the profile with the mesh entry's own fields on top, or the profile itself when the entry has none.
---@param mesh    string
---@param profile IAArrangableProfile
---@param name    string
---@param ratio   number
---@return IAArrangableProfile
local function applyOverrides(mesh, profile, name, ratio)
  local manual = IA.meshProfiles[mesh]

  if type(manual) ~= "table" then
    return profile
  end

  local key = string.format("%s@%s@%.3f", mesh, name, ratio)
  local result = overriddenProfiles[key]

  ---@diagnostic disable-next-line: unnecessary-if
  if result then
    return result
  end

  local hasOverrides = false

  for k in pairs(manual) do
    ---@diagnostic disable-next-line: unnecessary-if
    if not MESH_PROFILE_KEYS[k] then
      hasOverrides = true
      break
    end
  end

  if not hasOverrides then
    return profile
  end

  result = {}

  for k, v in pairs(profile) do
    result[k] = v
  end

  for k, v in pairs(manual) do
    ---@diagnostic disable-next-line: unnecessary-if
    if not MESH_PROFILE_KEYS[k] then
      result[k] = v
    end
  end

  overriddenProfiles[key] = result

  return result
end

---@param learned   table<string, CAIAE_LearnedProfile[]>
---@param worldMesh CAIAE_WorldMesh
---@return IAArrangableProfile?, string?, number?
local function resolveProfile(learned, worldMesh)
  local profile, name, ratio = resolveBaseProfile(learned, worldMesh)

  if not profile then
    return nil, nil, nil
  end

  ---@cast name string
  ---@cast ratio number
  return applyOverrides(worldMesh.mesh, profile, name, ratio), name, ratio
end

function IA.applyMeshProfiles()
  if IA.meshProfilesApplied then
    return
  end

  if type(IA.arrangables) ~= "table" or type(IA.arrangableProfile) ~= "table" then
    print(string.format("%s: Item Arrange is not loaded, skipping.", p))
    return
  end

  IA.meshProfilesApplied = true

  local sm = getScriptManager()
  local fileWriter = isDebugEnabled() and getFileWriter(p .. "_added.txt", true, false) or nil

  local learned = learnMeshProfiles(sm)

  local arrangables = IA.arrangables
  local items = sm:getAllItems()

  local added = 0
  local addedByMod = {}

  for i = 0, items:size() - 1 do
    local item = items:get(i)
    local fullType = item:getFullName()

    if not arrangables[fullType] then
      local worldMesh = getWorldMesh(sm, item)
      local profile, profileName, ratio

      if worldMesh then
        profile, profileName, ratio = resolveProfile(learned, worldMesh)
      end

      if profile then
        arrangables[fullType] = profile
        added = added + 1
        local modID = item:getModID()

        addedByMod[modID] = addedByMod[modID] and addedByMod[modID] + 1 or 1

        if fileWriter then
          local scaleNote = ratio ~= 1 and string.format(", x%.2f", ratio) or ""

          fileWriter:writeln(
            string.format(
              'IA.arrangables["%-40s = IA.arrangableProfile.%-12s -- %s (%s @%s%s)', fullType .. '"]', profileName, modID,
              worldMesh and worldMesh.mesh or "N/A", tostring(worldMesh and worldMesh.scale or "N/A"), scaleNote
            )
          )
        end
      end
    end
  end

  if fileWriter then
    fileWriter:close()
  end

  for modID, count in pairs(addedByMod) do
    print(string.format("%s: [%s] Made %d extra items arrangeable.", p, modID, count))
  end
end

Events.OnGameStart.Add(IA.applyMeshProfiles)
Events.OnServerStarted.Add(IA.applyMeshProfiles)
