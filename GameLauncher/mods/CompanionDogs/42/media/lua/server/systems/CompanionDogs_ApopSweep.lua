-- Animal mora em <save>/apop/apop_X_Y.bin, um arquivo por celula de 256x256. Sem o mod o
-- IsoAnimal.load estoura NPE no tipo desconhecido, o AnimalCell.load devolve false e o jogo
-- repovoa a celula, apagando animais que não eram dali.
-- getAnimalChunk numa celula sem arquivo faz o jogo GERAR fauna nova ali: nunca chamar sem
-- checar fileExists antes. A lista de animais de um VirtualAnimal e package-private, entao o
-- unico acesso e findAnimalById(int) varrendo 0..9999 (animalId = Rand.Next(10000)).

CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

CD.Server = CD.Server or {}

local MAX_ANIMAL_ID = 9999
local CHUNKS_PER_CELL = 1024
local GRID = 32
local CHUNK_TILES = 8
local CELL_TILES = 256
local CELL_SCAN_MAX = 99
local WORK_PER_TICK = 20000
local FILE_TESTS_PER_TICK = 1200

local job = nil

local function say(text)
    CD.log("[CD-APOP] " .. tostring(text))
    if job and job.player then
        CD.notifyOwner(job.player, "debugmsg", { text = text })
    end
end

local function apopPath(cx, cy)
    return getCurrentSaveName() .. "/apop/apop_" .. cx .. "_" .. cy .. ".bin"
end

-- Remove pelo objeto: ArrayList tem remove(int) e remove(Object), e passar numero deixa a escolha
-- da sobrecarga por conta do Kahlua. Confere pelo tamanho: remove(Object) devolve false sem estourar.
local function listRemove(list, obj, idx)
    if not list then return false end
    local before = list:size()
    list:remove(obj)
    local after = list:size()
    if after < before then return true end
    list:remove(idx)
    return list:size() < before
end

local function scanGroupSlice(st, budget)
    local group = st.group
    local last = math.min(st.idCursor + budget - 1, MAX_ANIMAL_ID)
    for id = st.idCursor, last do
        local found = nil
        if group then
            found = group:findAnimalById(id)
        end
        if found then
            st.members = st.members + 1
            local isDog = false
            if found then
                isDog = CD.isDog(found)
            end
            if not isDog then
                st.allDogs = false
                st.idCursor = MAX_ANIMAL_ID + 1
                return true
            end
        end
    end
    st.idCursor = last + 1
    return st.idCursor > MAX_ANIMAL_ID
end

local function finishGroup(st, cell)
    if st.members > 0 and st.allDogs then
        if listRemove(st.list, st.group, st.groupIdx) then
            job.dogsRemoved = job.dogsRemoved + st.members
            job.groupsRemoved = job.groupsRemoved + 1
            cell.touched = true
            return true
        end
        job.removeFailed = job.removeFailed + 1
    end
    return false
end

local function dirtyTouchedCells()
    local cells = {}
    for _, c in ipairs(job.cells) do
        if c.touched then
            cells[#cells + 1] = c
        end
    end
    if #cells == 0 then return 0 end
    local p = job.player
    local sq = p and p:getCurrentSquare()
    if not sq then
        job.dirtyWait = (job.dirtyWait or 0) + 1
        if job.dirtyWait < 300 then return nil end
        say("could not find a valid square to flag the cells from; NOTHING was written to disk")
        return 0
    end
    local throwaway = CD.spawnDog(sq:getX(), sq:getY(), sq:getZ(), "dogmale", CD.breedEngineName(CD.DEFAULT_BREED))
    if not throwaway then
        say("could not spawn the throwaway dog used to flag cells for rewrite; nothing was written")
        return 0
    end
    local n = 0
    for _, c in ipairs(cells) do
        throwaway:setLastCellSavedTo(c.x, c.y)
        throwaway:removeFromWorld()
        n = n + 1
    end
    throwaway:delete()
    CD.regInvalidate()
    return n
end

local function step()
    if job.phase == "cells" then
        local tests = 0
        while job.cx <= CELL_SCAN_MAX do
            local exists = fileExists(apopPath(job.cx, job.cy))
            if exists then
                job.cells[#job.cells + 1] = { x = job.cx, y = job.cy }
            end
            job.cy = job.cy + 1
            if job.cy > CELL_SCAN_MAX then
                job.cy = 0
                job.cx = job.cx + 1
            end
            tests = tests + 1
            if tests >= FILE_TESTS_PER_TICK then return end
        end
        job.phase = "scan"
        job.cellIdx = 1
        job.chunkIdx = 0
        say(string.format("%d animal cell(s) with data on disk; scanning", #job.cells))
        return
    end

    if job.phase == "scan" then
        local work = WORK_PER_TICK
        while work > 0 do
            local cell = job.cells[job.cellIdx]
            if not cell then
                job.phase = "dirty"
                return
            end
            local st = job.group
            if st then
                local spend = work
                work = 0
                if scanGroupSlice(st, spend) then
                    if not finishGroup(st, cell) then
                        job.groupIdx = job.groupIdx + 1
                    end
                    job.group = nil
                end
            elseif job.list then
                work = work - 1
                local size = 0
                if job.list then
                    size = job.list:size()
                end
                if job.groupIdx >= size then
                    job.list = nil
                    job.chunkIdx = job.chunkIdx + 1
                else
                    local g = nil
                    if job.list then
                        g = job.list:get(job.groupIdx)
                    end
                    if not g then
                        job.groupIdx = job.groupIdx + 1
                    else
                        job.groupsSeen = job.groupsSeen + 1
                        job.group = { group = g, list = job.list, groupIdx = job.groupIdx,
                                      idCursor = 0, members = 0, allDogs = true }
                    end
                end
            elseif job.chunkIdx >= CHUNKS_PER_CELL then
                local done, tot = job.cellIdx, #job.cells
                local secs = (getTimestampMs() - job.startedMs) / 1000
                local eta = (done > 0) and ((secs / done) * (tot - done)) or 0
                say(string.format("cell %d/%d done -- %d dog(s) removed so far, %d group(s) inspected, %.0fs elapsed, ~%.0fs left",
                    done, tot, job.dogsRemoved, job.groupsSeen, secs, eta))
                job.cellIdx = job.cellIdx + 1
                job.chunkIdx = 0
            else
                work = work - 1
                local x = cell.x * CELL_TILES + (job.chunkIdx % GRID) * CHUNK_TILES
                local y = cell.y * CELL_TILES + math.floor(job.chunkIdx / GRID) * CHUNK_TILES
                local chunk = getAnimalChunk(x, y)
                local list = nil
                if chunk then
                    list = chunk:getVirtualAnimals()
                end
                local size = 0
                if list then
                    size = list:size()
                end
                if size > 0 then
                    job.list = list
                    job.groupIdx = 0
                else
                    job.chunkIdx = job.chunkIdx + 1
                end
            end
        end
        return
    end

    if job.phase == "dirty" then
        local flagged = dirtyTouchedCells()
        if flagged == nil then return end
        local secs = (getTimestampMs() - job.startedMs) / 1000
        say(string.format(
            "sweep done: %d dog(s) in %d group(s) removed across %d cell(s), %d group(s) inspected, %.0fs. SAVE THE GAME now so the files are rewritten.",
            job.dogsRemoved, job.groupsRemoved, flagged, job.groupsSeen, secs))
        if job.removeFailed > 0 then
            say(string.format("WARNING: %d group(s) could not be removed from the list", job.removeFailed))
        end
        local finished = job
        job = nil
        Events.OnTick.Remove(step)
        if finished.onDone then
            finished.onDone()
        end
    end
end

-- Pre-voo obrigatorio: carregar celula com um tipo de animal que nao existe mais e destrutivo,
-- e e a propria falha que este comando existe pra evitar.
local function missingBreeds()
    local missing, any = {}, false
    local store = CD.kennelGlobalAll()
    if type(store) ~= "table" then return missing, any end
    for _, recs in pairs(store) do
        if type(recs) == "table" then
            for _, snap in pairs(recs) do
                local b = (type(snap) == "table") and snap.breed or nil
                if b ~= nil and not (CD.BREEDS and CD.BREEDS[b]) then
                    missing[b] = true
                    any = true
                end
            end
        end
    end
    return missing, any
end

---Admin cleanup that removes every saved dog from the animal store, cell by cell; refused while a saved dog's breed is not registered.
---@param player IsoPlayer
---@param args table|nil { skipload }
CD.Server.wipedogsapop = function(player, args)
    if isClient() then return end
    if not CD.debugAllowed(player) then return end
    if job then
        CD.notifyOwner(player, "debugmsg", { text = "apop sweep already running" })
        return
    end

    local missing, any = missingBreeds()
    if any then
        local names = ""
        for b in pairs(missing) do names = (names == "" and b) or (names .. ", " .. b) end
        local msg = "REFUSED: this save has dogs of breed(s) not registered right now (" .. names ..
            "). Re-enable the breed addon(s) for this save and run again. Loading those cells without the " ..
            "definitions is what destroys the animals in the first place."
        CD.log("[CD-APOP] " .. msg)
        CD.notifyOwner(player, "debugmsg", { text = msg })
        return
    end

    local sq = player and player:getCurrentSquare()
    if not sq then
        CD.notifyOwner(player, "debugmsg", { text = "REFUSED: stand on solid ground before running the sweep" })
        return
    end
    if not (args and args.skipload) and CD.Server.deletealldogs then
        CD.Server.deletealldogs(player, { nosweep = true })
    end
    job = {
        player = player, phase = "cells", cx = 0, cy = 0, cells = {},
        cellIdx = 1, chunkIdx = 0, groupIdx = 0, list = nil, group = nil,
        groupsSeen = 0, groupsRemoved = 0, dogsRemoved = 0, removeFailed = 0,
        startedMs = getTimestampMs(),
    }
    say("apop sweep started: looking for animal cells on disk")
    Events.OnTick.Add(step)
end
