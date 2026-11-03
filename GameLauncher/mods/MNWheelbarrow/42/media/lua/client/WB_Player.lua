--[[
    O UNICO trabalho por quadro do mod.

    POR QUE UM ARQUIVO SO: antes havia dois OnPlayerUpdate registrados, um em
    WB_Hands e outro em WB_Move, cada um refazendo a mesma pergunta -- "o jogador
    esta com o carrinho?". Dois handlers por quadro para uma condicao comum e
    desperdicio, e pior: espalha por dois arquivos a ordem em que as correcoes
    acontecem, que passa a depender da ordem de carregamento do Lua.

    Aqui a condicao e avaliada uma vez e as regras derivam dela.

    O QUE ESTE ARQUIVO NAO FAZ, de proposito:

      - nao impede entrar em predio, atravessar porta ou subir escada. O carrinho
        e um item de inventario comum para o motor de movimento; nada aqui toca
        nisso, e e assim que deve continuar.
      - nao recalcula peso nem capacidade. Isso e por evento em WB_Weight, e nao
        por quadro.
      - NAO mexe no alpha de render do jogador. Ja mexeu, e era conserto de um
        defeito que nao existia -- ver docs/personagem-invisivel.md.
]]

local WB_Cart = require "WB_Cart"
local WB_Hands = require "WB_Hands"
local WB_MP = require "WB_MP"
local WB_Parking = require "WB_Parking"
local WB_Sandbox = require "WB_Sandbox"
local WB_Transfer = require "WB_Transfer"

local WB_Player = {}

--[[ Se fomos NOS que ligamos o bloqueio de auto-vault, POR JOGADOR.

     TABELA E NAO BOOLEANO, e a diferenca e um defeito de tela dividida: este handler
     dispara para cada jogador local, e com um booleano de arquivo o primeiro a passar
     por aqui ligava a marca e o SEGUNDO nunca recebia a flag. Pior no caminho de
     volta -- o primeiro a largar o carrinho zerava a marca compartilhada com o outro
     ainda empurrando, e a partir dai os dois se atrapalhavam a cada quadro.

     A chave e a mesma de WB_Parking, que ja tinha resolvido o mesmo problema: nome de
     usuario em multiplayer, indice do jogador fora dele. ]]
local vaultBlocked = {}

--- O carrinho continua na mao mas ja esta no chao?
---
--- E o carrinho-fantasma: o modelo segue renderizado numa mao que nao tem mais o
--- item. O jogador nao consegue desfazer isso sozinho, entao vale uma checagem
--- por quadro.
---
--- Usa so getWorldItem, que e um getter. A checagem completa de posse percorre a
--- arvore do inventario -- e o carrinho e um container, entao essa arvore
--- carrega o conteudo dele junto. Por quadro, isso pesaria. O caso completo e
--- tratado em WB_Hands, nos eventos de equipar.
local function ghostInHand(character)
    local primary = character:getPrimaryHandItem()
    if WB_Cart.is(primary) and primary:getWorldItem() ~= nil then return primary end
    local secondary = character:getSecondaryHandItem()
    if WB_Cart.is(secondary) and secondary:getWorldItem() ~= nil then return secondary end
    return nil
end

Events.OnPlayerUpdate.Add(function(character)
    --[[ SO O JOGADOR DESTA MAQUINA.

         OnPlayerUpdate dispara para todo personagem que o cliente simula,
         inclusive os jogadores remotos. Tudo daqui para baixo MUDA estado --
         desequipa carrinho fantasma, liga isIgnoreAutoVault, cancela corrida --
         e sem esta guarda mudaria o estado de outro jogador na tela dele.

         Um cliente so nao revela isso: e preciso um segundo jogador conectado. ]]
    if not WB_MP.isLocalPlayer(character) then return end

    -- Enquanto uma acao do mod move o carrinho, a checagem de fantasma nao vale:
    -- durante a transicao o item legitimamente aparece nos dois lugares. Sem esta
    -- guarda, a rede desfaz a propria acao -- o mesmo defeito que WB_Placement
    -- teve, e que aqui apareceria de forma ainda mais dificil de ver, por rodar
    -- em silencio a cada quadro.
    if WB_Transfer.active() then return end

    -- Antes da saida por "nao tem carrinho na mao": enquanto o carrinho esta
    -- estacionado ele legitimamente NAO esta na mao, e e justo esse o estado que
    -- precisa ser desfeito quando a fila de acoes termina.
    WB_Parking.restoreIfIdle(character)

    local ghost = ghostInHand(character)
    if ghost ~= nil then
        WB_Hands.release(character, ghost)
        return
    end

    local carrying = WB_Cart.inHands(character)

    --[[ AUTO-VAULT: portao baixo e pulado em vez de aberto.

         doContextDoor e doContextThumpableDoor consultam isIgnoreAutoVault antes de
         decidir entre pular por cima e abrir -- conferido no bytecode de IsoPlayer,
         que sao os DOIS unicos lugares da classe que leem a flag. Com o carrinho na
         mao, pular esta fora de questao, entao ligamos a flag e o portao volta a ser
         aberto.

         Guardamos se fomos NOS que ligamos para nao desligar a flag de outro mod
         que a tenha ligado por conta propria. ]]
    local key = WB_MP.playerKey(character)
    if carrying and not vaultBlocked[key] then
        character:setIgnoreAutoVault(true)
        vaultBlocked[key] = true
    elseif not carrying and vaultBlocked[key] then
        character:setIgnoreAutoVault(false)
        vaultBlocked[key] = nil
    end

    if not carrying then return end

    if WB_Sandbox.get("BlockRunning") then
        -- RunSpeedModifier no script so ESCALA a velocidade; nao existe campo
        -- que proiba correr. E ele nao pode virar sandbox option porque
        -- InventoryItem nao expoe setRunSpeedModifier -- o valor e lido uma vez
        -- no carregamento do script.
        --
        -- Sprint e run sao estados SEPARADOS: desligar um nao desliga o outro.
        if character:isSprinting() then character:setSprinting(false) end
        if character:isRunning() then character:setRunning(false) end
    end
end)

return WB_Player
