CompanionDogs = CompanionDogs or {}
local CD = CompanionDogs

CD.DEFAULT_SPECIES = "dog"

CD.SPECIES = {
    -- nounKey e o substantivo CRU, minusculo: ele preenche "This %1 already belongs to another
    -- survivor". labelKey e a forma de exibicao, capitalizada, pro rotulo Especie da ficha. Sao chaves
    -- separadas porque nao da pra capitalizar texto UTF-8 no Lua do PZ de um jeito que sirva as 14 linguas.
    dog = { key = "dog", nounKey = "IGUI_PD_DogNoun", youngKey = "IGUI_PD_Puppy",
            labelKey = "IGUI_PD_SpeciesDisplay_dog" },
}

---@param def table { key, nounKey, youngKey, labelKey? }
---@return table|nil def the registered entry; nil when refused
function CD.registerSpecies(def)
    if type(def) ~= "table" or not def.key then
        CD.log("registerSpecies: recusado, argumento nao e tabela ou nao tem 'key'")
        return nil
    end
    if CD.SPECIES[def.key] then
        CD.log("registerSpecies: a chave de especie '" .. tostring(def.key) ..
              "' JA existe; o registro novo foi ignorado (dois addons disputando a mesma chave?)")
        return CD.SPECIES[def.key]
    end
    for _, field in ipairs({ "nounKey", "youngKey" }) do
        if type(def[field]) ~= "string" then
            CD.log("registerSpecies: especie '" .. tostring(def.key) .. "' recusada, falta o campo '" ..
                  field .. "' (API_VERSION " .. tostring(CD.API_VERSION) .. ")")
            return nil
        end
    end
    CD.SPECIES[def.key] = def
    return def
end

---CD.DEFAULT_SPECIES when the breed is unknown or declares no species.
---@param breedKey string|nil
---@return string speciesKey
---@nodiscard
function CD.speciesOf(breedKey)
    local def = breedKey and CD.BREEDS[breedKey]
    return (def and def.species) or CD.DEFAULT_SPECIES
end

---@param animal IsoAnimal
---@return string speciesKey
---@nodiscard
function CD.getSpecies(animal)
    return CD.speciesOf(CD.getBreed(animal))
end

---@param a IsoAnimal
---@param b IsoAnimal
---@return boolean
---@nodiscard
function CD.sameSpecies(a, b)
    return CD.getSpecies(a) == CD.getSpecies(b)
end

local function speciesDef(key)
    return CD.SPECIES[key] or CD.SPECIES[CD.DEFAULT_SPECIES]
end

---Lowercase species noun for running text; unregistered species use the dog's.
---@param breedKey string|nil
---@return string
---@nodiscard
function CD.speciesNounFromKey(breedKey)
    return getText(speciesDef(CD.speciesOf(breedKey)).nounKey)
end

---@param animal IsoAnimal|nil
---@return string
---@nodiscard
function CD.speciesNoun(animal)
    return CD.speciesNounFromKey(animal and CD.getBreed(animal))
end

---Label of the species' young, such as Puppy; unregistered species use the dog's.
---@param breedKey string|nil
---@return string
---@nodiscard
function CD.youngNounFromKey(breedKey)
    return getText(speciesDef(CD.speciesOf(breedKey)).youngKey)
end

---@param animal IsoAnimal|table|nil the dog, or the stash proxy
---@return string
---@nodiscard
function CD.youngNoun(animal)
    return CD.youngNounFromKey(animal and CD.getBreed(animal))
end

-- Forma de exibicao ("Cao" / "Gato"), pro rotulo Especie da ficha. Especie sem labelKey cai no
-- nounKey, que sai minusculo mas legivel.
---@param breedKey string|nil
---@return string
---@nodiscard
function CD.speciesLabelFromKey(breedKey)
    local def = speciesDef(CD.speciesOf(breedKey))
    return getText(def.labelKey or def.nounKey)
end

-- Texto por especie: procura "<chave>_<especie>" antes da chave crua, pra frase com "dog" fixo no
-- texto sair na versao do gato. Cao nunca faz a segunda busca. Mesma assinatura do getText.
---@param breedKey string|nil
---@param key string translation key
---@param ... any getText arguments
---@return string
---@nodiscard
function CD.speciesTextFromKey(breedKey, key, ...)
    local sp = CD.speciesOf(breedKey)
    if sp ~= CD.DEFAULT_SPECIES then
        local t = getTextOrNull(key .. "_" .. sp, ...)
        if t then return t end
    end
    return getText(key, ...)
end

---@param animal IsoAnimal|table|nil the dog, or the stash proxy
---@param key string translation key
---@param ... any getText arguments
---@return string
---@nodiscard
function CD.speciesText(animal, key, ...)
    return CD.speciesTextFromKey(animal and CD.getBreed(animal), key, ...)
end
