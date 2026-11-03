-- 1. Tabela com os multiplicadores por Categoria
local multiplicadoresCategoria = {
    ["RecipeResource"] 	= 0.2,
    ["SkillBook"]      	= 0.2,
    ["Literature"]      = 0.2,
    ["Cartography"]     = 0.5,
    ["Electronics"]     = 0.2,
}

-- 2. Tabela de Filtros por Nome (Padrões / Wildcards)
local multiplicadoresNomes = {
    {"^Shirt_", 0.1},
    {"^Tshirt_", 0.1},
    {"^Hoodie", 0.1},
    {"^Jumper_", 0.1},
    {"^Football_", 0.1},
    {"^Jacket", 0.3},
    {"^Ice_", 0.3},
    {"^Poncho", 0.1},
    {"^Apron", 0.1},
    {"^Dress", 0.5},
    {"^Trousers", 0.1},
    {"^Shorts", 0.1},
    {"^Skirt", 0.1},
    {"^Socks", 0.5},
    {"^Shoes", 0.5},
    {"^Boob", 0.1},
    {"^Bra_", 0.1},
    {"^Boxers", 0.1},
    {"^Briefs", 0.1},
    {"^Underpants", 0.1},
    {"^Stockings", 0.1},
    {"^Tights", 0.1},
    {"^Hat_", 0.2},
    {"^Glasses_", 0.5},
    {"GasMask", 0.2},
    {"^Scarf_", 0.2},
    {"^Necklace", 0.3},
    {"^Nose", 0.1},
    {"^Earring_", 0.1},
    {"^Gloves_", 0.5},
    {"^WristWatch_", 0.3},
    {"^Bracelet_", 0.1},
    {"^Ring_Right", 0.1},
    {"^Ring_Left", 0.1},
    {"^Belly", 0.1},
    {"^Generator", 0.5}
}

-- 3. Tabela de Exceções e Pesos Manuais
local pesosManuais = {
    ["BottleCrafted"] = 0.05,
    ["JuiceCranberry"] = 0.05,
    ["JuiceFruitpunch"] = 0.05,
    ["JuiceGrape"] = 0.05,
    ["JuiceLemon"] = 0.05,
    ["JuiceOrange"] = 0.05,
    ["JuiceTomato"] = 0.05,
    ["MilkBottle"] = 0.05,
    ["PopBottleRare"] = 0.05,
    ["SimpleSyrup"] = 0.05,
    ["Disinfectant"] = 0.05,
    ["IndustrialDye"] = 0.05,
    ["BucketEmpty"] = 0.6,
    ["BucketWaterDebug"] = 0.6,
    ["Bucket"] = 0.6,
    ["BucketForged"] = 0.6,
    ["Canteen"] = 0.1,
    ["CanteenClay"] = 0.1,
    ["CanteenMilitary"] = 0.1,
    ["CanteenMilitaryFull"] = 0.1,
    ["WaterBottle"] = 0.05,
    ["PopBottle"] = 0.05,
    ["PopBottleRare"] = 0.05,
    ["CanteenCowboy"] = 0.1,
    ["Plasticbag"] = 0.01,
    ["Plasticbag_Clothing"] = 0.01,
    ["Plasticbag_Bags"] = 0.01,
    ["GroceryBag1"] = 0.01,
    ["GroceryBag2"] = 0.01,
    ["GroceryBag3"] = 0.01,
    ["GroceryBag4"] = 0.01,
    ["GroceryBag5"] = 0.01,
    ["GroceryBagGourmet"] = 0.01,
    ["EmptySandbag"] = 0.08,
    ["Bag_DeadRats"] = 0.08,
    ["Bag_DeadMice"] = 0.08,
    ["Bag_DeadRoaches"] = 0.08,
    ["Bag_TreasureBag"] = 0.08,
    ["WheatSack"] = 0.08,
    ["WheatSeedSack"] = 0.08,
    ["Soap2"] = 0.08,
    ["Eraser"] = 0.01,
    ["PenFancy"] = 0.05,
    ["MarkerBlack"] = 0.05,
    ["MarkerBlue"] = 0.05,
    ["MarkerGreen"] = 0.05,
    ["MarkerRed"] = 0.05,
    ["PenMultiColor"] = 0.05,
    ["Pen"] = 0.01,
    ["BluePen"] = 0.01,
    ["GreenPen"] = 0.01,
    ["RedPen"] = 0.01,
    ["PenSpiffo"] = 0.02,
    ["Pencil"] = 0.01,
    ["PencilSpiffo"] = 0.02,
    ["Scissors"] = 0.1,
    ["ScissorsBlunt"] = 0.08,
    ["ScissorsBluntMedical"] = 0.15,
    ["Multitool"] = 0.1,
    ["ScissorsForged"] = 0.1,
    ["StraightRazor"] = 0.08,
    ["IDcard"] = 0.02,
    ["IDcard_Female"] = 0.02,
    ["IDcard_Male"] = 0.02,
    ["IDcard_Stolen"] = 0.02,
    ["IDcard_Blank"] = 0.02,
    ["Cigar"] = 0.05,
    ["SmokingPipe_Tobacco"] = 0.1,
    ["ToiletPaper"] = 0.1,
    ["HandTorch"] = 0.2,
    ["FlashLight_AngleHead"] = 0.2,
    ["FlashLight_AngleHead_Army"] = 0.2,
    ["Torch"] = 0.5,
    ["Flashlight_Crafted"] = 0.35,
    ["GunLight"] = 0.1,
    ["Lighter"] = 0.05,
    ["PenLight"] = 0.08,
    ["Candle"] = 0.1,
    ["CandleBox"] = 0.5,
    ["CandleLit"] = 0.1,
    ["Aluminum"] = 0.1,
    ["RippedSheets"] = 0.05,
    ["RippedSheetsDirty"] = 0.06,
    ["AlcoholRippedSheets"] = 0.06,
    ["RippedSheetsBundle"] = 0.5,
    ["RippedSheetsDirtyBundle"] = 0.6,
    ["RippedSheetsSterilizedBundle"] = 0.6,
    ["Sheet"] = 0.6,
    ["SheetRope"] = 0.6,
    ["SheetRopeBundle"] = 6.0,
    ["Twine"] = 0.1,
    ["Thread"] = 0.05,
    ["Yarn"] = 0.1,
    ["LeatherStrips"] = 0.1,
    ["LeatherStripsDirty"] = 0.11,
    ["LeatherStripsBundle"] = 1.0,
    ["LeatherStripsDirtyBundle"] = 1.1,
    ["Scotchtape"] = 0.1,
    ["DuctTape"] = 0.1,
    ["Epoxy"] = 0.1,
    ["FiberglassTape"] = 0.4,
    ["Glue"] = 0.25,
    ["Woodglue"] = 0.5,
    ["PropaneTank"] = 0.5,
    ["Bandage"] = 0.08,
    ["BandageDirty"] = 0.081,
    ["AlcoholBandage"] = 0.08,
    ["Bandaid"] = 0.01,
    ["DenimStrips"] = 0.1,
    ["DenimStripsDirty"] = 0.11,
    ["DenimStripsBundle"] = 1.0,
    ["DenimStripsDirtyBundle"] = 1.1,
    ["AlcoholWipes"] = 0.1,
    ["AlcoholedCottonBalls"] = 0.01,
    ["Antibiotics"] = 0.02,
    ["AdhesiveBandageBox"] = 0.2,
    ["AntibioticsBox"] = 0.2,
    ["BandageBox"] = 1.0,
    ["CottonBallsBox"] = 0.1,
    ["SutureNeedleBox"] = 0.1,
    ["CottonBalls"] = 0.01,
    ["SutureNeedle"] = 0.01,
    ["SutureNeedleHolder"] = 0.1,
    ["Forceps_Forged"] = 0.1,
    ["Scalpel"] = 0.1,
    ["Tweezers"] = 0.05,
    ["Tweezers_Forged"] = 0.05,
    ["PillsAntiDep"] = 0.05,
    ["PillsBeta"] = 0.05,
    ["PillsVitamins"] = 0.05,
    ["Pills"] = 0.05,
    ["PillsSleepingTablets"] = 0.05,
    ["Hat_SurgicalCap"] = 0.01,
    ["Gloves_Surgical"] = 0.01,
    ["Hat_SurgicalMask"] = 0.01,
    ["Awl"] = 0.1,
    ["Handiknife"] = 0.1,
    ["IcePick"] = 0.1,
    ["HeadingTool"] = 0.2,
    ["SmallPunchSet"] = 0.3,
    ["SheetMetalSnips"] = 0.35,
    ["Screwdriver"] = 0.1,
    ["Screwdriver_Old"] = 0.1,
    ["Key1"] = 0.01,
    ["Key_Blank"] = 0.01,
    ["KeyPadlock"] = 0.01,
    ["Disc_Retail"] = 0.05,
    ["VHS_Retail"] = 0.1,
    ["VHS_Home"] = 0.1,
    ["3030Bullets"] = 0.021,
    ["Bullets357"] = 0.016,
    ["Bullets38"] = 0.0158,
    ["Bullets44"] = 0.023,
    ["Bullets45"] = 0.021,
    ["ShotgunShells"] = 0.04,
    ["556Bullets"] = 0.012,
    ["308Bullets"] = 0.025,
    ["Bullets9mm"] = 0.012,
    ["3030Box"] = 0.42,
    ["Bullets357Box"] = 0.8,
    ["Bullets38Box"] = 0.8,
    ["Bullets44Box"] = 0.46,
    ["Bullets45Box"] = 1.05,
    ["ShotgunShellsBox"] = 1.0,
    ["556Box"] = 0.24,
    ["308Box"] = 0.5,
    ["Bullets9mmBox"] = 0.6,
    ["3030BulletsCarton"] = 4.2,
    ["Bullets357Carton"] = 8.0,
    ["Bullets38Carton"] = 8.0,
    ["Bullets44Carton"] = 4.6,
    ["Bullets45Carton"] = 10.5,
    ["ShotgunShellsCarton"] = 10.0,
    ["556Carton"] = 2.4,
    ["308Carton"] = 5.0,
    ["Bullets9mmCarton"] = 6.0,
    ["44Clip"] = 0.085,
    ["JS14_Clip"] = 0.12,
    ["556Clip"] = 0.11,
    ["45Clip"] = 0.075,
    ["M14Clip"] = 0.23,
    ["9mmClip"] = 0.09,
    ["Vest_BulletCivilian"] = 3.5,
    ["Vest_BulletArmy"] = 3.5,
    ["Vest_BulletDesert"] = 3.5,
    ["Vest_BulletDesertNew"] = 3.5,
    ["Vest_BulletOliveDrab"] = 3.5,
    ["Vest_BulletPolice"] = 3.5,
    ["Vest_BulletSWAT"] = 3.5,
	["Nails"] = 0.00354,
	["NailsBox"] = 0.15,
	["NailsCarton"] = 1.5,
	["Screws"] = 0.006,
	["ScrewsBox"] = 0.24,
	["ScrewsCarton"] = 2.4,
	["Garbagebag_box"] = 0.15,
	["Garbagebag"] = 0.015,
	["Bag_TrashBag"] = 0.015,
	["Battery"] = 0.025,
	["BatteryBox"] = 0.25,
	["LightBulbBox"] = 0.34,
	["LightBulb"] = 0.1,	
	["FishingHookBox"] = 0.06,
	["FishingHook"] = 0.01,
	["FishingHook_Forged"] = 0.02,
	["JigLure"] = 0.02,
	["MinnowLure"] = 0.02,
	["Scotchtape"] = 0.1,
	["AdhesiveTapeBox"] = 1.0,
	["DuctTape"] = 0.3,
	["DuctTapeBox"] = 3.0,
	["Paperclip"] = 0.002,
	["PaperclipBox"] = 0.06,
}

TrueWeightTotal = 0
local pesosCustomizadosSandbox = {}

local function lerPesosDoSandbox()
    -- Lê a string do Sandbox. Se estiver vazia, retorna ""
    local customString = SandboxVars.TrueWeight.CustomWeights or ""
    
    -- Limpa a tabela para não duplicar se rodar mais de uma vez
    pesosCustomizadosSandbox = {}
    
    for idItem, strPeso in string.gmatch(customString, "([^:;]+):([^:;]+)") do
        local peso = tonumber(strPeso)
        if peso then
            idItem = string.match(idItem, "^%s*(.-)%s*$")
            pesosCustomizadosSandbox[idItem] = peso
        end
    end
end

local function aplicarTodosOsPesos()
    lerPesosDoSandbox()

    local allItems = ScriptManager.instance:getAllItems()
    
    -- Verifica se a caixa "Use the mod's preset balance" está marcada
    local usarPresetDoMod = SandboxVars.TrueWeight.UseModPreset
    if usarPresetDoMod == nil then usarPresetDoMod = true end

    -- Captura o multiplicador geral (se não existir, é 1.0)
    local multiplicadorGeral = SandboxVars.TrueWeight.GeneralMultiplier
    if type(multiplicadorGeral) ~= "number" then multiplicadorGeral = 1.0 end

    -- [GERADOR DE LOG]
     local logFile = getFileWriter("TrueWeight_Log.txt", true, false)
     if logFile then
         logFile:write("ID_Item,Categoria,Peso_Original,Peso_Modificado,Fonte_Modificacao\n")
     end

    for i = 0, allItems:size() - 1 do
        local item = allItems:get(i)
        
        local itemId = item:getName()
        local categoria = item:getDisplayCategory()
        local pesoAtual = item:getActualWeight()
        local modificado = false
         local fonteMod = "Original" -- [GERADOR DE LOG] (Descomente se for usar o Log para rastrear) 

        ---------------------------------------------------------
        -- BLOCO 1: PRIORIDADE ABSOLUTA (Opções do Jogador no Sandbox)
        ---------------------------------------------------------
        
        -- PRIORIDADE 1: O item está na caixa de texto customizada do Sandbox?
        if pesosCustomizadosSandbox[itemId] then
            item:setActualWeight(pesosCustomizadosSandbox[itemId])
            modificado = true
             fonteMod = "Sandbox_Texto" -- [GERADOR DE LOG] 
            TrueWeightTotal = TrueWeightTotal + 1
        end

        -- PRIORIDADE 2: A categoria do Sandbox foi alterada de 1.0 pelo jogador?
        if not modificado and categoria then
            local multiplicadorSandbox = SandboxVars.TrueWeight[categoria]
            
            if multiplicadorSandbox and type(multiplicadorSandbox) == "number" and multiplicadorSandbox ~= 1.0 then
                item:setActualWeight(pesoAtual * multiplicadorSandbox)
                modificado = true
                 fonteMod = "Sandbox_Categoria" -- [GERADOR DE LOG] 
                TrueWeightTotal = TrueWeightTotal + 1
            end
        end

        ---------------------------------------------------------
        -- BLOCO 2: PRESETS DO MOD (Só roda se usarPresetDoMod == true E item não foi modificado acima)
        ---------------------------------------------------------
        
        if usarPresetDoMod and not modificado then
            
            -- PRIORIDADE 3: Pesos Manuais do Mod
            if pesosManuais[itemId] then
                item:setActualWeight(pesosManuais[itemId])
                modificado = true
                 fonteMod = "Mod_PesosManuais" -- [GERADOR DE LOG] 
                TrueWeightTotal = TrueWeightTotal + 1
            
            -- PRIORIDADE 4: Filtros por Nome (Wildcards) do Mod
            else
                for _, regra in ipairs(multiplicadoresNomes) do
                    local padraoBusca = regra[1]
                    local multiplicador = regra[2]
                    
                    if string.find(itemId, padraoBusca) then
                        item:setActualWeight(pesoAtual * multiplicador)
                        modificado = true
                         fonteMod = "Mod_NomesWildcard" -- [GERADOR DE LOG] 
                        TrueWeightTotal = TrueWeightTotal + 1
                        break
                    end
                end
                
                -- PRIORIDADE 5: Categorias do Mod
                if not modificado and categoria and multiplicadoresCategoria[categoria] then
                    item:setActualWeight(pesoAtual * multiplicadoresCategoria[categoria])
                    modificado = true
                     fonteMod = "Mod_Categorias" -- [GERADOR DE LOG] 
                    TrueWeightTotal = TrueWeightTotal + 1
                end
            end
        end

        ---------------------------------------------------------
        -- BLOCO 3: MULTIPLICADOR GERAL
        ---------------------------------------------------------
        
        -- Se o multiplicador geral for diferente de 1.0, ele afeta TODOS os itens
        if multiplicadorGeral ~= 1.0 then
            -- Puxamos o peso que resultou dos blocos 1 e 2 (ou o peso vanilla se ele não foi modificado)
            local pesoAposRegras = item:getActualWeight()
            
            -- Aplicamos a multiplicação final
            item:setActualWeight(pesoAposRegras * multiplicadorGeral)
            
            -- Se o item não havia sido contado nos blocos anteriores, adicionamos ao contador
            if not modificado then
                modificado = true
                 fonteMod = "Sandbox_Geral" -- [GERADOR DE LOG] 
                TrueWeightTotal = TrueWeightTotal + 1
            end
        end

        -- [GERADOR DE LOG]
         if modificado and logFile then
             local pesoNovo = item:getActualWeight()
             logFile:write(tostring(itemId) .. "," .. tostring(categoria) .. "," .. tostring(pesoAtual) .. "," .. tostring(pesoNovo) .. "," .. fonteMod .. "\n")
         end

    end

    -- [GERADOR DE LOG] 
     if logFile then
        logFile:close()
     end
end

Events.OnLoadedTileDefinitions.Add(aplicarTodosOsPesos)