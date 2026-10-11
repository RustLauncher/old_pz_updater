--[[
    O que a tecla de interagir faz quando o jogador esta com o carrinho.

    ----------------------------------------------------------------------
    OS DOIS DEFEITOS ERAM O MESMO DEFEITO

      1. dava para pular cerca baixa com o carrinho nas maos;
      2. apertar E perto de uma porta LARGAVA o carrinho em vez de abrir.

    A causa comum: o nosso handler de E vivia em Events.OnKeyPressed e nao
    conversava com as acoes contextuais do engine. Os dois disputavam a mesma
    tecla sem arbitro.

    Isso tambem explica um comportamento que parecia projetado e era acidente:
    "cerca alta larga o carrinho antes de escalar". Ninguem escreveu isso.
    Escalada de cerca alta exige SEGURAR o E, e o nosso largar dispara no
    apertar -- o carrinho caia primeiro por diferenca de tempo, nao por regra.
    Um acidente que da o resultado certo continua sendo um acidente: some no dia
    em que o tempo da tecla mudar.

    ----------------------------------------------------------------------
    COMO O ARBITRIO FUNCIONA

    O engine decide sozinho o que o E faz e despacha por UM ponto em Lua:

        Hook.ContextualAction  ->  ContextualActionHandlers[nome](...)

    Como o despachante resolve `ContextualActionHandlers[nome]` na HORA DA
    CHAMADA, trocar um campo da tabela intercepta a acao. E o que fazemos, e da
    duas capacidades de uma vez:

      RECUSAR   escalar cerca, janela e lencol com o carrinho na mao;
      OBSERVAR  quando o engine reivindicou o E, para nao largar o carrinho em
                cima de uma porta que ele ja vai abrir.

    ----------------------------------------------------------------------
    POR QUE A NOSSA ACAO ESPERA DOIS QUADROS

    Nao ha garantia de ordem entre Events.OnKeyPressed e o despacho do engine no
    mesmo quadro. Em vez de apostar numa ordem -- que muda entre versoes e nao da
    para verificar sem o jogo aberto --, registramos a intencao e resolvemos
    depois: se uma acao contextual apareceu nesse meio, ela ganha.

    Dois quadros, nao um, para tolerar o engine despachar um quadro atras. A
    trinta quadros por segundo isso e menos de setenta milesimos, e a acao de
    largar tem animacao de segundos -- o atraso nao existe para o jogador.
]]

local WB_Cart = require "WB_Cart"

local WB_Interact = {}

--- Acoes contextuais que o carrinho IMPEDE.
---
--- Todas envolvem tirar os pes do chao ou passar o corpo por um vao. Nao ha como
--- fazer nenhuma delas com um carrinho de mao carregado, e a lista existe como
--- DADO para nao virar uma cadeia de ifs quando aparecer a quarta.
local BLOCKED = {
    ClimbOverFence = true,
    ClimbThroughWindow = true,
    ClimbSheetRope = true,
}

--- Os dois funis de entrada em veiculo. Nomeado, e nao literal na chamada, porque
--- ipairs sobre tabela literal e recusado pelo verificador -- ele nao tem como
--- saber que nenhum elemento e nil, e o defeito que ele previne ja apareceu aqui.
local VEHICLE_ENTRIES = { "onEnter", "onEnter2" }

--- Relogio de quadros, avancado no OnTick no fim deste arquivo.
local tick = 0
--- Ultimo quadro em que o engine reivindicou a tecla de interagir.
local claimed = -1
--- Quadro em que o jogador apertou a tecla, enquanto a intencao nao foi resolvida.
local pending = nil
--- Quem apertou. Guardado porque a resolucao acontece quadros depois.
local pendingFor = nil

local function refuse(character)
    -- HaloTextHelper e como o jogo base recusa: texto curto acima do personagem,
    -- sem janela e sem som de erro. Ver ISVehicleMenu.onEnter, que usa o mesmo
    -- para "tem alguem nesse assento".
    HaloTextHelper.addBadText(character, getText("IGUI_MNWB_Refuse"))
end

--- @return boolean se o carrinho impede esta acao agora
function WB_Interact.blocks(action, character)
    return BLOCKED[action] == true and WB_Cart.equipped(character) ~= nil
end

Events.OnGameStart.Add(function()
    -- Colhe os nomes ANTES de trocar qualquer campo. Mutar a tabela durante o
    -- proprio pairs e comportamento que Lua nao garante, e a primeira versao deste
    -- arquivo fazia isso -- ela nao bloqueou nada em jogo, e esta e a suspeita mais
    -- concreta do porque.
    local names = {}
    for action in pairs(ContextualActionHandlers) do
        names[#names + 1] = action
    end

    for _, action in ipairs(names) do
        local handler = ContextualActionHandlers[action]
        ContextualActionHandlers[action] = function(name, character, ...)
            if getDebug() then
                print("[Wheelbarrow][CONTEXTO] " .. tostring(name))
            end
            if character ~= nil and instanceof(character, "IsoPlayer") then
                if WB_Interact.blocks(name, character) then
                    -- NAO marca como reivindicado: recusamos, entao a tecla fica
                    -- livre e o mesmo aperto larga o carrinho. O jogador aperta E
                    -- uma vez e o carrinho desce, aperta de novo e escala -- que e
                    -- o que a cerca alta ja fazia, agora de proposito.
                    refuse(character)
                    return
                end
                claimed = tick
            end
            return handler(name, character, ...)
        end
    end

    if getDebug() then
        print("[Wheelbarrow][CONTEXTO] " .. #names
            .. " acoes contextuais interceptadas")
    end

    --[[ O carrinho tambem nao entra em veiculo.

         Nao passa pelo despachante contextual, entao precisa do proprio gancho.
         ISVehicleMenu.onEnter e onEnter2 sao os dois funis por onde todo caminho
         de entrada passa -- radial, menu de contexto e tecla. Recusar em
         ISEnterVehicle:isValid() seria mais fundo e mais silencioso: a acao
         falharia sem dizer por que. ]]
    for _, name in ipairs(VEHICLE_ENTRIES) do
        local original = ISVehicleMenu[name]
        ISVehicleMenu[name] = function(character, vehicle, seat)
            if character ~= nil and WB_Cart.equipped(character) ~= nil then
                refuse(character)
                return
            end
            return original(character, vehicle, seat)
        end
    end
end)

--- O que fazer com o carrinho quando o engine NAO reivindicou a tecla.
---
--- Registrado de fora em vez de chamado daqui para evitar require circular: quem
--- sabe pegar e largar o carrinho e WB_Placement, e WB_Placement precisa deste
--- arquivo para anunciar o aperto de tecla.
local cartAction = nil

--- @param fn function(character) chamada quando a tecla sobra para o mod
function WB_Interact.setCartAction(fn)
    cartAction = fn
end

--- Registra que o jogador apertou a tecla de interagir.
function WB_Interact.press(character)
    -- Ja ha uma intencao esperando: apertos repetidos dentro da janela de dois
    -- quadros sao um aperto, nao dois.
    if pending ~= nil then return end
    pending = tick
    pendingFor = character
end

--[[ O relogio de quadros vive aqui, e em OnTick e nao em OnPlayerUpdate.

     A disputa e pela TECLA, que e uma so para o jogo inteiro -- nao e estado por
     personagem. Em OnPlayerUpdate o relogio andaria uma vez por jogador em tela
     dividida, e a janela de dois quadros encurtaria sem ninguem notar. WB_Player
     segue sendo o unico trabalho POR PERSONAGEM por quadro; este e por quadro. ]]
Events.OnTick.Add(function()
    tick = tick + 1
    if pending == nil or tick < pending + 2 then return end

    local engineActed = claimed >= pending
    local character = pendingFor
    pending, pendingFor = nil, nil

    if engineActed or character == nil or cartAction == nil then return end
    cartAction(character)
end)

return WB_Interact
