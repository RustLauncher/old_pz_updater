require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISRichTextPanel"
require "ProjectALife/Core/ALifeText"
require "ProjectALife/Interface/ALifeDiscordLink"
require "ProjectALife/Interface/Creator/ALifeCreatorCore"

local Creator = ProjectALife.CreatorScreen

Creator.helpFileName = "alife_creator_help.ini"
Creator.helpOffered = false

function Creator.helpPages()
    local Text = ProjectALife.Text
    return {
        { title = Text.ui("What the Creator is"), body = {
            Text.ui("The Creator is the editor for everything the A-Life NPCs are made of. You build factions (groups) and member presets (the individual NPCs of a group): their names, looks, weapons, behaviour, relations and how often they appear."),
            Text.ui("The NPC SETTINGS tab is the workbench. On the left is the faction list, in the middle the member presets of the selected faction, and on the right the editor with a live character preview. The FACTION SETTINGS tab holds the rules of the selected faction. On a small screen the three columns become three tabs: FACTIONS, MEMBERS and EDITOR + MODEL."),
            Text.ui("Open the Creator from the A-Life card on the main menu, from the A-Life Creator button in the pause menu, or with the key set in Options, Key Bindings (Insert by default). On a multiplayer server only an admin can use it."),
            Text.ui("Everything saves by itself a moment after you change it. Hover a setting for a plain-language tip. Escape closes this guide, and then the Creator. The HELP button at the top left opens this guide again at any time."),
        } },
        { title = Text.ui("Making a faction"), body = {
            Text.ui("1. On the FACTION LIST press + NEW (or + NEW FACTION). A faction called New Faction is created and its settings open."),
            Text.ui("2. On the IDENTITY tab give it a name, a category and a description. Unknown faction disposition is the stance toward factions you have not set a relation for; it starts as Hostile."),
            Text.ui("3. Open RELATIONS to say how it treats the player, other factions and whole folders (see Relations and stances)."),
            Text.ui("4. Open SPAWNING to choose whether it appears on its own, how often, when and where (see Spawning rules). SUPPORT sets whether and how its squads call for backup."),
            Text.ui("5. Return to the workbench with the ROSTER button and add members. A faction with no members has nobody to spawn."),
            Text.ui("On the faction list, DUPLICATE FACTION copies a faction with all its NPCs and DELETE removes the selected one after asking. COPY CODE turns a faction into a share code you can paste to a friend or on Discord, and LOAD CODE adds a faction from a code in your clipboard. RESET FACTIONS TO DEFAULT puts the built-in factions back as shipped and keeps the ones you made."),
        } },
        { title = Text.ui("Making a member"), body = {
            Text.ui("Pick a faction, then press + NEW MEMBER in the MEMBER PRESETS column. The new preset is selected and ready to edit. DUPLICATE NPC is the quickest way to make a variation of a member you already like. The arrow buttons above the editor step through the members and save first. The search box and the ALL, RANGED, MELEE and ISSUES buttons help with long rosters."),
            Text.ui("The editor has seven tabs: IDENTITY, APPEARANCE, FACES, LOADOUT, COMBAT, BEHAVIOR and MODULES."),
            Text.ui("IDENTITY is the person. Display name and Gender come first. NPC name chooses where the name comes from: a random name that matches the gender (the default), a random male name, a random female name, or Set name, which gives every NPC of this preset the name you type. With the random choices each spawned NPC gets its own name, never repeated in the world. An empty Set name falls back to a random name."),
            Text.ui("Tag describes the member's job. Class sets how the member acts under threat: Civilian is the most easily frightened, Worker and Rescue less easily, and Police, Military and Criminal stay steady. Same as faction follows the faction's class."),
            Text.ui("Spawn Weight In Group (Common, Uncommon, Rare, Very Rare, Unseen) sets how often this preset is picked inside its faction. Rare and Very Rare keep specialists from taking over a squad. Filter tags and Notes are for your own organisation."),
        } },
        { title = Text.ui("Outfits and weapons"), body = {
            Text.ui("APPEARANCE: choose skin tone, hair and beard, then build up to six outfit sets, A to F. Tick Enable this set for spawning on every set you want used; only ticked sets are picked. A set can be limited to a season (Any season, Spring only, Summer only, Autumn only or Winter only). In its season a seasonal set replaces the any-season sets. The season follows the outdoor temperature when the NPC is dressed and again while it lives (the date only picks spring or autumn between 4 and 22 C)."),
            Text.ui("Under BODY SLOTS click a slot to open the icon catalog, click an item to preview it and press APPLY to keep it. Switch on Enable multiple options to keep up to four random choices for the slot. Keep an item's own colour (NATIVE ITEM COLOR) or pick a CUSTOM COLOR. PREVIEW VARIATION cycles through the enabled sets."),
            Text.ui("FACES offers face overlays from other mods. It has choices only when the mod that supplies them is enabled."),
            Text.ui("LOADOUT: pick a PRIMARY firearm, a SIDEARM and a MELEE / BELT weapon the same way, with up to four random choices each. AMMUNITION is counted in whole magazines, not loose rounds. Infinite ammunition removes the reload limit, and Drop magazines on death with its chance controls what can be looted. FIREARM ATTACHMENTS sets scopes, sights and other parts."),
            Text.ui("COMBAT holds Health, Strength, Endurance and Awareness, aiming accuracy against players and zombies, damage dealt and damage blocked, and what drops after death (weapon and armor drop chance and condition)."),
        } },
        { title = Text.ui("Behaviour, class and modules"), body = {
            Text.ui("BEHAVIOR tab: Behavior profile is the complete baseline package of priorities, engagement style and allowed abilities, and the summary under it spells out what it does. Primary doctrine adds one specialist role: None, Leader, Gunner, Medic, Sniper, Stealth or Ambusher. Combat ready decides whether the NPC starts out armed and prepared (Default, Yes, No or Mixed)."),
            Text.ui("The voice profile picks the voice pack used for warnings, combat reactions and death sounds. PLAYTEST VOICE plays the chosen reaction so you can hear it; it does not change behaviour."),
            Text.ui("Class (IDENTITY tab) decides who the Fear of the dead ability affects: Civilian members, and less easily Rescue and Worker members, leave distant zombies alone and run as a group when too many close in, while Police, Military and Criminal members stay steady. The world Fear switch also applies."),
            Text.ui("MODULES tab (NPC ABILITIES): every ability can be Inherit, On or Off. Inherit uses the faction setting; On and Off apply to this NPC only. The abilities are grouped as ORDERS, DANGER RESPONSE, COMBAT MOVEMENT, SURVIVAL & ROUTINE and OUTLAW CONDUCT. RESET ALL TO INHERIT clears this NPC's overrides, and APPLY ABILITIES TO FACTION applies this NPC's ability choices to the whole faction."),
            Text.ui("To set defaults for everyone at once use FACTION SETTINGS, BEHAVIOR DEFAULTS. An NPC's own override wins over the faction default, and the world (sandbox) switches still apply on top. For example a member cannot flee while the world Flee switch is off."),
        } },
        { title = Text.ui("Relations and stances"), body = {
            Text.ui("FACTION SETTINGS, RELATIONS decides how this faction treats others. The stances are Allied, Friendly, Neutral, Careful and Hostile."),
            Text.ui("There are three views. BY FACTION has a row for every other faction: leave a row on Default to use the inherited stance, or set it yourself. BY FOLDER sets one stance toward every faction in a folder (see Folders). BY PROFESSION sets the stance toward the player depending on the player's profession."),
            Text.ui("The PLAYER line at the top shows the stance toward you right now, and REFRESH LIVE asks the running world for the current value."),
            Text.ui("Player disposition on the SPAWNING tab is the stance used when the faction meets you. Friendly and neutral factions can appear naturally. Scouts, ambushes and raids need a hostile faction."),
            Text.ui("Unknown faction disposition (IDENTITY tab) is the fallback for factions you have not mentioned anywhere else."),
        } },
        { title = Text.ui("Spawning rules"), body = {
            Text.ui("SPAWNING tab, SPAWN POLICY: tick Enable natural spawning if the faction should appear by itself in the world. Spawn weight is relative to the other factions - it is not a percentage - and zero turns natural spawning off. The sandbox settings control how often encounters happen overall."),
            Text.ui("Game day sets the first and last day the faction can appear (day 0 is the first; leave one end blank to keep it open). Active hours decide when new encounters may begin. Squads that are already out finish what they are doing."),
            Text.ui("PARTY SIZE lets you choose lone survivors, groups or both, with their size ranges and weights."),
            Text.ui("ALLOWED ENCOUNTERS and the place choice (Anywhere, Selected towns, Wilderness only, Roads & highways or Specific building types) limit what kind of events can use the faction and where. If no encounter is selected the faction has no natural encounters."),
            Text.ui("Spawn Weight In Group on a member preset is a separate setting: it only chooses between the members of one faction."),
        } },
        { title = Text.ui("Folders and the folder override"), body = {
            Text.ui("Folders keep a long faction list tidy. Press NEW FOLDER, type a name and press CREATE."),
            Text.ui("Drag a faction card onto a folder to file it there. While you drag, a label shows where it will land (a folder name or MOVE TO UNFILED). Click a folder header to fold it open or shut. The up and down buttons on the header move the folder, and the ... button opens FOLDER ACTIONS: rename, COPY NPC FOLDER, SHARE CODE and DELETE FOLDER."),
            Text.ui("DELETE FOLDER also deletes every faction inside the folder and all their NPCs, after a confirmation. Use it with care."),
            Text.ui("The folder override: in RELATIONS, BY FOLDER, choose a stance for a whole folder and every faction inside gets it at once. In BY FACTION those rows carry a FOLDER badge with the folder name. To make an exception, change that single row."),
        } },
        { title = Text.ui("Saving"), body = {
            Text.ui("Saving is automatic. The status text at the bottom of the editor shows where things stand: SAVED, UNSAVED - AUTOSAVING, SAVING, or a red error message."),
            Text.ui("SAVE NOW (or Ctrl+S) saves immediately. Closing the Creator and stepping to another member also save first."),
            Text.ui("Closing the Creator or switching member never waits for a save: the NPC keeps being written in the background and the main menu says Saving NPC... until it is done. SAVING - RETRY WHEN SAVED means something that needs the finished file (SAVE NOW, new, copy, delete, export or sync) was held back to protect your edits. Nothing is lost. Wait for the label to change to SAVED and then do it again."),
            Text.ui("A red message such as Could not save NPC. Your edits are still open. means the save failed. Your changes stay on screen, so press SAVE NOW again. A faction field that is not valid shows its message in the same place until you fix it."),
            Text.ui("When the Creator is opened inside a running game, SYNC TO SERVER sends your catalog to the server. The label at the bottom left says SERVER SYNC COMPLETE, or why it failed."),
        } },
        { title = Text.ui("Testing in the game"), body = {
            Text.ui("Spawn a fresh NPC to check a change. NPCs that already exist keep what they were made with."),
            Text.ui("Turn on Diagnostics in Options, Project A-Life. Then load a game (single player, or a server where you are an admin), right-click the ground and open [A-LIFE] Project A-Life."),
            Text.ui("Open spawn panel lets you choose and spawn NPCs. Spawn faction squad here lists the factions that have members. Spawn encounter here places a ready-made encounter, and Remove NPCs clears them around you."),
            Text.ui("The same menu has Open faction & NPC Creator, so you can edit, spawn and look again without leaving the game. In multiplayer press SYNC TO SERVER after editing so the server gets your catalog."),
            Text.ui("The character preview in the editor and PLAYTEST VOICE need no game at all."),
        } },
        { title = Text.ui("Tips"), body = {
            Text.ui("Names: give factions short, clear names and use the category and description to say what they are. Give members a clear Display name and Filter tags such as medic, rifle or trader so you can find them later."),
            Text.ui("Weights: start with Common everywhere, then use Uncommon and Rare for specialists. Weights are relative, so one Rare member next to three Common ones is picked roughly one time in sixteen."),
            Text.ui("Build one good member first, then use DUPLICATE NPC and change only what differs."),
            Text.ui("Change one thing at a time and spawn a fresh NPC to see it."),
            Text.ui("Share your work: COPY CODE on a faction produces a code anyone can load with LOAD CODE. Folders have a SHARE CODE button too."),
        } },
        { title = Text.ui("Where to get help"), body = {
            Text.ui("The A-Life Discord is the place for questions, bug reports and sharing factions. Press JOIN THE A-LIFE DISCORD at the top of the Creator or at the bottom of this window. The link is discord.gg/alife (https://discord.gg/alife)."),
            Text.ui("If a browser or the Steam overlay cannot be opened, a small box with the link appears so you can copy it. COPY LINK at the bottom of this window copies it to your clipboard."),
            Text.ui("When you report a problem, say what you were editing, and paste the share code if it is about a faction."),
            Text.ui("This guide opened by itself only the first time. Open it again whenever you like with the HELP button at the top left."),
        } },
    }
end

function Creator.helpSeen()
    if type(getFileReader) ~= "function" then return true end
    local seen = false
    local ok = pcall(function()
        local reader = getFileReader(Creator.helpFileName, true)
        if reader == nil then return end
        while true do
            local line = reader:readLine()
            if line == nil then break end
            if string.find(line, "seen", 1, true) ~= nil then seen = true end
        end
        reader:close()
    end)
    return seen or not ok
end

function Creator.markHelpSeen()
    if type(getFileWriter) ~= "function" then return false end
    local ok, written = pcall(function()
        local writer = getFileWriter(Creator.helpFileName, true, false)
        if writer == nil then return false end
        writer:write("seen = true\n")
        writer:close()
        return true
    end)
    return ok and written == true
end

function Creator.offerHelp(window)
    if window == nil or Creator.helpOffered then return false end
    Creator.helpOffered = true
    if Creator.helpSeen() then return false end
    Creator.markHelpSeen()
    return Creator.openHelp(window)
end

function Creator.buildHelpHeader(window)
    if window == nil or type(Creator.addButton) ~= "function" then return false end
    local Text = ProjectALife.Text
    local px, y = Creator.px, Creator.px(10)
    local helpTitle = Text.ui("? HELP")
    local helpW = Creator.textWidth(helpTitle, UIFont.Small) + px(28)
    window.helpButton = Creator.addButton(window, px(14), y, helpW, helpTitle, function()
        Creator.openHelp(window)
    end, true)
    Creator.addTooltip(window.helpButton, Text.ui("A short guide to every part of the Creator."))
    local x = px(14) + helpW + px(8)
    local titleLeft = math.floor(window.width / 2
        - Creator.textWidth("PROJECT A-LIFE CREATOR", UIFont.Title or UIFont.Large) / 2)
    local caption = Text.ui("JOIN THE A-LIFE DISCORD")
    local width = Creator.textWidth(caption, UIFont.Small) + px(28)
    if x + width + px(12) > titleLeft then
        caption = Text.ui("DISCORD")
        width = Creator.textWidth(caption, UIFont.Small) + px(28)
    end
    window.discordButton = Creator.addButton(window, x, y, width, caption, function()
        ProjectALife.DiscordLink.open()
    end)
    Creator.addTooltip(window.discordButton,
        Text.ui("Opens discord.gg/alife in your browser or the Steam overlay."))
    return true
end

function Creator.closeHelp(window)
    window = window or Creator.window
    local overlay = window and window.helpOverlay
    if overlay == nil then return false end
    window.helpOverlay, window.helpBox = nil, nil
    pcall(function() overlay:setVisible(false) end)
    pcall(function() window:removeChild(overlay) end)
    return true
end

function Creator.helpMarkup(page)
    local parts = {
        "<H2> <RGB:0.55,0.78,0.84> ", page.title, " <LINE> <LINE> <TEXT> <RGB:0.80,0.82,0.80> ",
    }
    for _, paragraph in ipairs(page.body) do
        parts[#parts + 1] = paragraph
        parts[#parts + 1] = " <LINE> <LINE> "
    end
    return table.concat(parts)
end

function Creator.helpShowPage(box, index)
    local pages = box.helpPages
    index = math.max(1, math.min(#pages, index))
    box.helpIndex = index
    box.helpText:setText(Creator.helpMarkup(pages[index]))
    if type(box.helpText.paginate) == "function" then box.helpText:paginate() end
    box.helpText:setYScroll(0)
    for number, button in ipairs(box.helpNav) do
        Creator.styleButton(button, number == index)
    end
    box.helpPrev:setEnable(index > 1)
    box.helpNext:setEnable(index < #pages)
    if index > 1 then Creator.styleButton(box.helpPrev, false) end
    if index < #pages then Creator.styleButton(box.helpNext, true) end
end

function Creator.helpStep(window, delta)
    local box = window and window.helpBox
    if box == nil then return false end
    Creator.helpShowPage(box, (box.helpIndex or 1) + delta)
    return true
end

function Creator.helpScroll(window, delta)
    local box = window and window.helpBox
    if box == nil or box.helpText == nil then return false end
    box.helpText:setYScroll(box.helpText:getYScroll() - delta)
    return true
end

function Creator.helpKey(window, key)
    local box = window and window.helpBox
    if box == nil or type(Keyboard) ~= "table" then return false end
    if key == Keyboard.KEY_ESCAPE then
        Creator.closeHelp(window)
        return true
    end
    if key == Keyboard.KEY_LEFT or key == Keyboard.KEY_PRIOR then return Creator.helpStep(window, -1) end
    if key == Keyboard.KEY_RIGHT or key == Keyboard.KEY_NEXT then return Creator.helpStep(window, 1) end
    if key == Keyboard.KEY_UP then return Creator.helpScroll(window, 60) end
    if key == Keyboard.KEY_DOWN then return Creator.helpScroll(window, -60) end
    return false
end

function Creator.helpCopyLink(box)
    local Text = ProjectALife.Text
    if ProjectALife.DiscordLink.copy() then
        box.helpNote = Text.ui("Link copied to the clipboard.")
    else
        box.helpNote = Text.ui("Copy the link by hand: discord.gg/alife")
    end
end

function Creator.openHelp(window, pageIndex)
    window = window or Creator.window
    if window == nil or type(ISRichTextPanel) ~= "table" or type(Creator.addButton) ~= "function" then
        return false
    end
    Creator.closeHelp(window)
    local Text = ProjectALife.Text
    local px = Creator.px
    local overlay = ISPanel:new(0, 0, window.width, window.height)
    overlay:initialise()
    overlay.backgroundColor = { r = 0, g = 0, b = 0, a = 0.72 }
    overlay.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    overlay.moveWithMouse = false
    overlay.onMouseDown = function() return true end
    overlay.onMouseUp = function() return true end
    overlay.onRightMouseDown = function() return true end
    overlay.onMouseWheel = function() return true end
    window:addChild(overlay)
    window.helpOverlay = overlay

    local boxW = math.min(px(980), window.width - px(40))
    local boxH = math.min(px(660), window.height - px(40))
    local box = ISPanel:new(math.floor((window.width - boxW) / 2), math.floor((window.height - boxH) / 2), boxW, boxH)
    box:initialise()
    box.backgroundColor = { r = 0.010, g = 0.013, b = 0.015, a = 1 }
    box.borderColor = { r = 0.34, g = 0.52, b = 0.57, a = 1 }
    box.moveWithMouse = false
    box.onMouseWheel = function() return true end
    overlay:addChild(box)
    window.helpBox = box
    box.helpPages = Creator.helpPages()
    box.helpIndex = 1
    box.helpNote = Text.ui("This guide opens by itself only the first time.")
    local palette = Creator.palette
    local heading = Text.ui("HOW TO USE THE CREATOR")
    local footerY = boxH - px(42)
    local noteX, noteRight = px(12), boxW - px(12)
    box.prerender = function(self)
        ISPanel.prerender(self)
        self:drawText(heading, px(16), px(10), palette.TEXT.r, palette.TEXT.g, palette.TEXT.b, 1, UIFont.Medium)
        self:drawTextRight(tostring(self.helpIndex) .. " / " .. tostring(#self.helpPages),
            self.width - px(16), px(14), palette.ROSE.r, palette.ROSE.g, palette.ROSE.b, 1, UIFont.Small)
        self:drawRect(px(12), px(44), self.width - px(24), px(2), 0.9,
            palette.ROSE.r, palette.ROSE.g, palette.ROSE.b)
        self:drawRect(px(12), self.height - px(48), self.width - px(24), px(1), 0.55,
            palette.ROSE.r, palette.ROSE.g, palette.ROSE.b)
        local room = (self.noteRight or noteRight) - (self.noteLeft or noteX)
        if room > px(80) then
            self:drawText(Creator.fitText(self.helpNote, UIFont.Small, room), self.noteLeft or noteX,
                self.height - px(38), palette.MUTED.r, palette.MUTED.g, palette.MUTED.b, 1, UIFont.Small)
        end
    end

    local navTop, navW = px(54), math.min(px(240), math.floor(boxW * 0.27))
    local rowH = Creator.rowHeight(25)
    local pitch = math.max(rowH + px(2), math.min(rowH + px(5),
        math.floor((boxH - px(54) - px(56)) / #box.helpPages)))
    box.helpNav = {}
    for index, page in ipairs(box.helpPages) do
        local number = index
        box.helpNav[index] = Creator.addButton(box, px(12), navTop + (index - 1) * pitch, navW,
            tostring(index) .. ". " .. page.title, function() Creator.helpShowPage(box, number) end)
    end

    local textX = navW + px(24)
    local text = ISRichTextPanel:new(textX, navTop, boxW - textX - px(12), boxH - navTop - px(56))
    text:initialise()
    box:addChild(text)
    text:addScrollBars()
    text.background = true
    text.backgroundColor = { r = 0.017, g = 0.022, b = 0.024, a = 1 }
    text.borderColor = { r = 0.115, g = 0.145, b = 0.152, a = 1 }
    text.clip = true
    text.autosetheight = false
    text.defaultFont = UIFont.Small
    text:setMargins(px(16), px(12), px(30), px(12))
    box.helpText = text

    local prevW = Creator.textWidth(Text.ui("PREVIOUS"), UIFont.Small) + px(28)
    local nextW = Creator.textWidth(Text.ui("NEXT"), UIFont.Small) + px(28)
    box.helpPrev = Creator.addButton(box, px(12), footerY, prevW, Text.ui("PREVIOUS"), function()
        Creator.helpStep(window, -1)
    end)
    box.helpNext = Creator.addButton(box, px(12) + prevW + px(6), footerY, nextW, Text.ui("NEXT"), function()
        Creator.helpStep(window, 1)
    end, true)
    local right = boxW - px(12)
    local closeTitle = Text.ui("CLOSE")
    local closeW = Creator.textWidth(closeTitle, UIFont.Small) + px(28)
    right = right - closeW
    Creator.addButton(box, right, footerY, closeW, closeTitle, function() Creator.closeHelp(window) end)
    local discordTitle = Text.ui("JOIN THE A-LIFE DISCORD")
    local discordW = Creator.textWidth(discordTitle, UIFont.Small) + px(28)
    right = right - px(6) - discordW
    Creator.addButton(box, right, footerY, discordW, discordTitle, function()
        ProjectALife.DiscordLink.open()
    end, true)
    local copyTitle = Text.ui("COPY LINK")
    local copyW = Creator.textWidth(copyTitle, UIFont.Small) + px(28)
    right = right - px(6) - copyW
    Creator.addButton(box, right, footerY, copyW, copyTitle, function() Creator.helpCopyLink(box) end)
    box.noteLeft = px(12) + prevW + nextW + px(20)
    box.noteRight = right - px(10)

    Creator.helpShowPage(box, tonumber(pageIndex) or 1)
    overlay:bringToTop()
    return true
end

return Creator
