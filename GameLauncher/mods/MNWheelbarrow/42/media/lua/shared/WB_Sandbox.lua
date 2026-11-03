--[[
    Leitura das sandbox options, com um padrao seguro para cada uma.

    POR QUE ISTO E UM ARQUIVO E NAO UMA LINHA EM CADA LUGAR:

    SandboxVars nao existe antes de o save carregar, e uma option recem-criada
    e nil em saves feitos antes dela. Ou seja, todo ponto de leitura precisa de
    dois guardas -- e antes deste arquivo eles estavam copiados em quatro lugares,
    cada um com um padrao proprio escrito na mao. Isso e como duas fontes de
    verdade nascem: basta alguem mudar o default do sandbox-options.txt e
    esquecer de um dos quatro.

    Aqui o padrao aparece UMA vez, e a tabela DEFAULTS existe para casar com o
    sandbox-options.txt. Divergir dela nao e erro de sintaxe, entao vale conferir
    os dois lados ao mexer em qualquer um.
]]

local WB_Const = require "WB_Const"

local WB_Sandbox = {}

--- Espelho dos defaults de sandbox-options.txt. So vale enquanto as options nao
--- carregaram, ou para uma option que ainda nao existe no save do jogador.
local DEFAULTS = {
    EnableWorldSpawn = true,
    SpawnChance = 3.0,
    EnableCrafting = true,
    -- 38, e nao 200: e o teto que applyCapacity mede no orcamento de chao. Ver o
    -- bloco da option em sandbox-options.txt.
    Capacity = 38,
    LightCapacity = 20,
    HeavyThreshold = 8.0,
    HeavyReduction = 95,
    ActionDuration = 80,
    SpillOnCancel = true,
    BlockRunning = true,
    AllowCorpses = true,
}

--- @param name string nome da option, sem o prefixo do modulo
--- @return any valor da option, ou o default quando ela ainda nao existe
function WB_Sandbox.get(name)
    local vars = SandboxVars and SandboxVars[WB_Const.SANDBOX_NS]
    local value = vars and vars[name]
    if value == nil then return DEFAULTS[name] end
    return value
end

return WB_Sandbox
