require "ISUI/ISEmoteRadialMenu"

CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

CD.RADIAL_COMMANDS = {
    cd_come    = { gesture = "comehere",  cmd = "come",     shout = false },
    cd_follow  = { gesture = "followme",  cmd = "setstate",     args = { state = CD.STATE_FOLLOW } },
    cd_stay    = { gesture = "stop",      cmd = "setstate",     args = { state = CD.STATE_STAY } },
    cd_guard   = { gesture = "stop",      cmd = "setstate",     args = { state = CD.STATE_GUARD } },
    cd_alert   = { cmd = "setalertmode",  args = { mode = "full" } },
    cd_quiet   = { cmd = "setalertmode",  args = { mode = "quiet" } },
    cd_silent  = { cmd = "setalertmode",  args = { mode = "silent" } },
    cd_attack  = { gesture = "signalfire", cmd = "attack",  shout = false },
    cd_hunt    = { cmd = "sethuntmode",   toggle = true },
    cd_openbag = { cmd = "bagopen" },
}

local LEAF_ICONS = {
    cd_come    = "media/ui/emotes/comehere.png",
    cd_follow  = "media/ui/emotes/followme.png",
    cd_stay    = "media/ui/emotes/stop.png",
    cd_guard   = "media/ui/emotes/salute.png",
    cd_alert   = "media/ui/emotes/yes.png",
    cd_quiet   = "media/ui/emotes/freeze.png",
    cd_silent  = "media/ui/emotes/no.png",
    cd_attack  = "media/ui/emotes/fire.png",
    cd_hunt    = "media/textures/CDDogPaw_64.png",
    cd_openbag = "Item_Satchel_Leather",
    cd_tricks  = "media/ui/emotes/clap.png",
}

local TRICK_ICONS = {
    ["goto"] = { "media/textures/CDTrickGoto_64.png",       "media/textures/CDTrickGotoRed_64.png" },
    distract = { "media/textures/CDTrickDistract_64.png",   "media/textures/CDTrickDistractRed_64.png" },
    sniff    = { "media/ui/Sidebar/64/Search_On_64.png",    "media/textures/CDTrickSniffRed_64.png" },
    fetch    = { "media/ui/Sidebar/64/Inventory_On_64.png", "media/textures/CDTrickFetchRed_64.png" },
}

local function trickIcon(id, blocked)
    local pair = TRICK_ICONS[id]
    if not pair then
        return getTexture(blocked and "media/textures/CDDogPawGrey_64.png" or "media/textures/CDDogPaw_64.png")
    end
    return getTexture(blocked and pair[2] or pair[1])
end

---Slice callback: starts the trick on the companion of the menu's player.
---@param emoteMenu ISEmoteRadialMenu
---@param trickId string
function CD.runTrickRadial(emoteMenu, trickId)
    local player = emoteMenu and emoteMenu.character
    local def = CD.trickDef(trickId)
    if not player or not def then return end
    local dog = CD.getCompanionAnimal(player)
    if not dog then
        HaloTextHelper.addBadText(player, getText("IGUI_PD_NoCompanionNear"))
        return
    end
    CD.startTrick(player, dog, trickId)
    player:setJoypadIgnoreAimUntilCentered(true)
end

---Replaces the radial content with one slice per trick, blocked ones greyed out with the reason.
---@param emoteMenu ISEmoteRadialMenu
function CD.fillTrickRadial(emoteMenu)
    local menu = getPlayerRadialMenu(emoteMenu.playerNum)
    menu:clear()
    local dog = CD.getCompanionAnimal(emoteMenu.character)
    for _, def in ipairs(CD.tricksFor(dog)) do
        local why, a1
        if dog then
            why, a1 = CD.trickBlockReason(dog, def, emoteMenu.character)
        else
            why = "IGUI_PD_TrickUnavailable"
        end
        local unlocked = why == nil
        local label = dog and CD.trickLabel(dog, def) or getText(def.labelKey)
        if why == "IGUI_PD_TrickLocked" then
            label = label .. " (" .. getText("IGUI_PD_TrickLockLvl", a1) .. ")"
        elseif why then
            label = label .. " (" .. getText("IGUI_PD_TrickUnavailable") .. ")"
        end
        menu:addSlice(label, trickIcon(def.id, not unlocked), CD.runTrickRadial, emoteMenu, def.id)
    end
    menu:addSlice(getText("IGUI_Emote_Back"), ISEmoteRadialMenu.icons["back"], emoteMenu.fillMenu, emoteMenu, "cd_dog")
    emoteMenu:display()
end

---Rebuilds the dog category of the emote radial with the commands this dog accepts.
---@param dog IsoAnimal|nil nil skips the per-dog checks and leaves the bag out
function CD.injectDogRadialCategory(dog)
    local menu = ISEmoteRadialMenu.menu
    if not menu then return end
    menu["cd_dog"] = {
        name = (dog and CD.breedNoun(dog)) or getText("IGUI_PD_RadialCategory"),
        subMenu = {
            cd_come    = getText("IGUI_PD_CmdCome"),
            cd_follow  = getText("IGUI_PD_CmdFollow"),
            cd_stay    = getText("IGUI_PD_CmdStay"),
            cd_alert   = getText("IGUI_PD_AlertOn"),
        },
    }
    if CD.huntEnabled() and (not dog or CD.breedCanHunt(dog)) then
        menu["cd_dog"].subMenu.cd_hunt =
            (dog and CD.getHuntMode(dog)) and getText("IGUI_PD_CmdHuntOff") or getText("IGUI_PD_CmdHunt")
    end
    if not dog or CD.breedCanFight(dog) then
        menu["cd_dog"].subMenu.cd_guard  = getText("IGUI_PD_CmdGuard")
        menu["cd_dog"].subMenu.cd_attack = getText("IGUI_PD_CmdAttack")
    end
    if not (dog and CD.alertModeLocked(dog)) then
        menu["cd_dog"].subMenu.cd_quiet  = getText("IGUI_PD_AlertQuiet")
        menu["cd_dog"].subMenu.cd_silent = getText("IGUI_PD_AlertSilent")
    end
    if CD.tricksEnabled() and (not dog or #CD.tricksFor(dog) > 0) then
        menu["cd_dog"].subMenu.cd_tricks = getText("IGUI_PD_TrickRoot")
    end
    if dog and CD.hasBag(dog) then
        menu["cd_dog"].subMenu.cd_openbag = getText("IGUI_PD_OpenBag")
    end
    local icons = ISEmoteRadialMenu.icons
    if icons then
        icons["cd_dog"] = getTexture("media/textures/CDDogPaw_64.png")
        for id, path in pairs(LEAF_ICONS) do
            icons[id] = getTexture(path)
        end
    end
end

---Plays the gesture and sends the command to the player's companion.
---@param player IsoPlayer
---@param spec table one entry of CD.RADIAL_COMMANDS
function CD.runRadialDogCommand(player, spec)
    if not player then return end
    if spec.gesture then
        player:playEmote(spec.gesture)
    end
    if spec.shout then
        player:Callout(false)
    end
    local dog = CD.getCompanionAnimal(player)
    if dog then
        if spec.cmd == "bagopen" then
            CD.openBagWindow(dog, player)
        else
            local extra = nil
            if spec.args then
                extra = {}
                for k, v in pairs(spec.args) do extra[k] = v end
            end
            if spec.toggle and spec.cmd == "sethuntmode" then
                extra = extra or {}
                extra.on = not CD.getHuntMode(dog)
            end
            CD.request(spec.cmd, dog, extra, player)
        end
    end
    player:setJoypadIgnoreAimUntilCentered(true)
end

local Emote_fillMenu = ISEmoteRadialMenu.fillMenu
function ISEmoteRadialMenu:fillMenu(submenu)
    if not submenu and self.character and ISEmoteRadialMenu.menu then
        local dog = CD.getCompanionAnimal(self.character)
        if dog then
            CD.injectDogRadialCategory(dog)
        else
            ISEmoteRadialMenu.menu["cd_dog"] = nil
        end
    end
    return Emote_fillMenu(self, submenu)
end

local Emote_emote = ISEmoteRadialMenu.emote
function ISEmoteRadialMenu:emote(emote)
    if emote == "cd_tricks" then
        CD.fillTrickRadial(self)
        return
    end
    local spec = CD.RADIAL_COMMANDS[emote]
    if spec then
        CD.runRadialDogCommand(self.character, spec)
        return
    end
    return Emote_emote(self, emote)
end
