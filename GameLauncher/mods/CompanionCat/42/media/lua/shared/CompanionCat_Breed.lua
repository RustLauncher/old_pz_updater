local CD = CompanionDogs
-- API 5 traz a tabela skills e o descKey. Num base anterior os campos seriam ignorados em silencio.
if not (CD and CD.registerBreed and (CD.API_VERSION or 0) >= 5) then return end

if CD.DISTRACT_CHANCE == nil then
    CD.log("CompanionCat: este base nao tem a distracao por presa; o gato funciona normal, so nunca vai " ..
          "largar tudo pra correr atras de rato. Atualize o Companion Dogs para a versao que a trouxe.")
end

local API10 = (CD.API_VERSION or 0) >= 10
if not API10 then
    CD.log("CompanionCat: este base nao tem sexo por raca; tricolor e escaminha voltam a nascer macho " ..
          "metade das vezes, o que na vida real quase nao acontece. Atualize o Companion Dogs.")
end

local API6 = (CD.API_VERSION or 0) >= 6
if API6 then
    CD.registerSpecies({ key = "cat", nounKey = "IGUI_PD_SpeciesNoun_cat",
                         youngKey = "IGUI_PD_Young_cat", labelKey = "IGUI_PD_SpeciesDisplay_cat" })
else
    CD.log("CompanionCat: este base nao tem especie por raca; o gato funciona normal, so continua sem " ..
          "cruzar (liberar sem a especie o faria cruzar com cachorro). Atualize o Companion Dogs.")
end

-- A chance e POR PELAGEM, entao ela cai toda vez que entram pelagens novas: com onze e 5/11 do que
-- era com cinco, e a quantidade total de gato no mundo nao muda.
CD.CAT_HOUSE_CHANCE = 0.909
CD.CAT_PETVET_CHANCE = 1.091
CD.CAT_SHOP_CHANCE = 0.909

---The CatSpawnMultiplier sandbox option: 1 when it is not a number, 0 when negative.
---@return number
---@nodiscard
local function catSpawnMultiplier()
    local sv = SandboxVars.CompanionCat
    local m = sv and sv.CatSpawnMultiplier
    if type(m) ~= "number" then return 1.0 end
    if m < 0 then return 0 end
    return m
end

CD.registerBuildingClass("catshop", function(def)
    if not def then return false end
    if not def:isShop() then return false end
    if CD.isPetVetBuilding(def) then return false end
    return true
end)

CD.registerVoices({
    CDCatMeow = "bark", CDCatGrowl = "bark", CDCatHiss = "bark", CDCatPurr = "bark",
    CDCatPet = "fx", CDCatMeowAmbient = "ambient",
}, nil, {
    CDCatMeow = 22, CDCatMeowAmbient = 22, CDCatHiss = 14, CDCatGrowl = 10, CDCatPet = 8,
    CDCatPurr = 6,
})

local PROFILE = {
    typePrefix = "cat",
    species = "cat",
    descKey = "IGUI_PD_BreedDesc_cat",
    -- O Cat_Body.glb traz os quatro clips de manqueira; a pata e a ESQUERDA na frente e atras, e a
    -- mesma nos dois, entao a marca da textura tem que sair nessas duas.
    limpAnim = true,
    litter = { 2, 4 },
    puppySize = 1.265,
    xpMult = { scent = 1.5, combat = 1, obedience = 0.7, hunt = 2.0, herding = 1.0 },
    combatPower = 0.10,
    lethalityCurve = { min = 0.40, max = 1.3 },
    canKill = false,
    canKnockdown = false,
    skills = { combat = false, herding = false },
    canBreed = API6,
    huntMaxPrey = "small",
    distract = { prey = { chance = 0.25 } },
    -- Trazer a presa morta de presente e instinto de gato, nao treino: entrega desde o nivel 0, igual
    -- ao Labrador. O prazo de 15 tambem e o dele; o default de 5 game-minutes encolhe com o Day Length
    -- e nao cobre as duas pernas (ate a carcaca, depois ate o dono).
    huntFetchLevel = 0,
    huntDeliverTimeoutMin = 15,
    voices = { bark = "CDCatMeow", growl = "CDCatGrowl", idle = "CDCatPurr",
               wildbark = "CDCatMeowAmbient", pet = "CDCatPet", whine = "CDCatHiss" },
    sentinelMult = 1.4,
    barkNoiseMult = 0.5,
    loyaltyDecayMult = 1.5,
    bagMult = 0.5,
    -- Descansando, o gato sorteia entre deitar (o do base) e sentar, com transicao e paradas para
    -- se lamber. Os clips de sentar so existem no Cat_Body.glb; num base de API 8 o campo e ignorado
    -- e ele so deita.
    restPoses = {
        "cdRest",
        { var = "cdSit", enter = "cdSitIn", exit = "cdSitOut",
          variation = { "cdSitGroom", "cdSitGroom2" } },
    },
    -- Tabela, e nao um numero so: chave ausente cai no default do base, entao as de idle tem que
    -- estar aqui junto com as de sentar. Cada valor e a duracao do clip.
    idleAnimMs = { cdIdle2 = 3800, cdIdle3 = 3800, cdSitIn = 1375, cdSitOut = 1417,
                   cdSitGroom = 19833, cdSitGroom2 = 25167 },
    geneRange = {
        strength       = { 0.00, 0.10 },
        aggressiveness = { 0.00, 0.15 },
        resistance     = { 0.00, 0.15 },
        stress         = { 0.55, 0.85 },
    },
}

-- Os sufixos |ct e |cv sao chave do store de spawn: NUNCA renomear num save vivo.
local COATS = {
    { key = "cat",       engine = "cat",        tex = "Cat",        house = "|ct",  petvet = "|cv",  shop = "|cs"  },
    { key = "catwhite",  engine = "cat_white",  tex = "Cat_White",  house = "|ctw", petvet = "|cvw", shop = "|csw" },
    { key = "catorange", engine = "cat_orange", tex = "Cat_Orange", house = "|cto", petvet = "|cvo", shop = "|cso" },
    { key = "catcalico", engine = "cat_calico", tex = "Cat_Calico", house = "|ctc", petvet = "|cvc", shop = "|csc" },
    { key = "cattuxedo", engine = "cat_tuxedo", tex = "Cat_Tuxedo", house = "|ctx", petvet = "|cvx", shop = "|csx" },
    { key = "catbrowntabby",  engine = "cat_brown_tabby",  tex = "Cat_BrownTabby",
      house = "|ctbt", petvet = "|cvbt", shop = "|csbt" },
    { key = "catgreytabby",   engine = "cat_grey_tabby",   tex = "Cat_GreyTabby",
      house = "|ctgt", petvet = "|cvgt", shop = "|csgt" },
    { key = "catorangetabby", engine = "cat_orange_tabby", tex = "Cat_OrangeTabby",
      house = "|ctot", petvet = "|cvot", shop = "|csot" },
    { key = "catbarley",      engine = "cat_barley",       tex = "Cat_Barley",
      house = "|ctby", petvet = "|cvby", shop = "|csby" },
    { key = "catcow",         engine = "cat_cow",          tex = "Cat_Cow",
      house = "|ctcw", petvet = "|cvcw", shop = "|cscw" },
    { key = "cattortie",      engine = "cat_tortie",       tex = "Cat_Tortie",
      house = "|ctto", petvet = "|cvto", shop = "|csto" },
}

-- O mosaico de laranja e preto e ligado ao cromossomo X: gata tricolor e gata escaminha sao quase
-- sempre femeas, e o macho que sai e XXY, cerca de 1 em 3000 e esteril.
local FEMALE_ONLY = { catcalico = true, cattortie = true }

-- Quem le "isto e um gato" fora daqui: o moodle de olho no escuro e as duas pontas do presente
-- noturno tinham cada um a sua copia da lista com as cinco pelagens do comeco, e as seis que
-- entraram depois nao recebiam nenhum dos dois. Uma fonte so, preenchida no mesmo laco do registro.
CompanionCat = CompanionCat or {}
CompanionCat.COAT_KEYS = {}

for _, p in ipairs(COATS) do
    CompanionCat.COAT_KEYS[p.key] = true
    local def = {}
    for k, v in pairs(PROFILE) do def[k] = v end
    def.key = p.key
    def.engineBreed = p.engine
    def.nameKey = "IGUI_PD_Breed_" .. p.key
    def.bandSkin = { base = p.tex, front = p.tex .. "_BandFront", back = p.tex .. "_BandBack",
                     cutFront = p.tex .. "_CutFront", cutBack = p.tex .. "_CutBack" }
    if API10 and FEMALE_ONLY[p.key] then
        def.maleChance = 0.00033
        def.sterileMale = true
    end
    def.spawns = {
        { id = p.key .. "house", class = "house", suffix = p.house, breed = p.key, indoor = 50,
          chance = function() return CD.CAT_HOUSE_CHANCE * catSpawnMultiplier() end },
        { id = p.key .. "petvet", class = "petvet", suffix = p.petvet, breed = p.key, indoor = 50,
          chance = function() return CD.CAT_PETVET_CHANCE * catSpawnMultiplier() end },
        { id = p.key .. "shop", class = "catshop", suffix = p.shop, breed = p.key, indoor = 50,
          chance = function() return CD.CAT_SHOP_CHANCE * catSpawnMultiplier() end },
    }
    CD.registerBreed(def)
end
