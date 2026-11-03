--[[
    Faz o carrinho ocupar as DUAS maos, e conserta estados de mao invalidos.

    ESTADO VALIDO, unico:  o mesmo objeto na mao primaria e na secundaria.

    POR QUE A REGRA TAMBEM VIVE EM LUA, e nao so em RequiresEquippedBothHands:
    o campo de script cuida da UI -- e ele que troca "equipar na primaria" /
    "na secundaria" pela opcao unica de duas maos. Ele nao impede que outra coisa
    entre na mao livre depois, e nao conserta estados quebrados. Os dois se
    completam.

    Qualquer outra combinacao com o carrinho envolvido e desfeita. O que isso cobre
    e uma coisa so: arma ou item pesado entrando na mao livre, o que anularia o
    custo de usar o carrinho.

    O modelo do PERSONAGEM sumindo constava aqui como segundo motivo, e NAO era:
    era a tecla F3, que em modo debug tambem chama ToggleModelsEnabled. Ver
    docs/personagem-invisivel.md. A correlacao com "item pesado disputando a mao"
    foi um dos tres diagnosticos errados daquela investigacao.

    ----------------------------------------------------------------------
    NAO HA OPTION PARA DESLIGAR ISTO, e a ausencia foi decidida.

    Existiu uma, BlockWeapons, com um ramo que deixava o carrinho numa mao so. Ela
    prometia mais do que entregava: pela mao secundaria funcionava, pela PRIMARIA --
    que e onde um clique no inventario poe a arma -- o ramo sobrescrevia a arma e o
    jogador ficava com a mao vazia, sem aviso. E nem no caminho que funcionava dava
    para atacar, porque a investida usa o item da mao primaria, onde esta o carrinho.

    Consertar exigiria escolher entre manter a arma na mao de folga (equipada e
    inutil) ou por o carrinho na secundaria, que e onde o primaryAnimMask dele deixa
    de valer e a pose de dois bracos se desfaz. Duas mecanicas de risco por uma
    option que ninguem pediu: ela saiu.

    CUIDADO AO EDITAR -- ja quebrou duas vezes, das duas por invariante
    desatualizada:

      1. a versao que exigia as duas maos nasceu junto com
         RequiresEquippedBothHands. Quando aquele campo saiu do script, a
         invariante virou impossivel e este codigo passou a desequipar o carrinho
         no mesmo frame em que ele era equipado -- sem erro nenhum no log. Isso
         me levou a culpar tres campos inocentes do script antes de achar a causa.
      2. depois, ao largar o carrinho, o repair via o item ainda na outra mao e
         REEQUIPAVA nas duas -- ressuscitando na mao um item que ja estava no
         chao.

    A licao das duas: este arquivo REEQUIPA, entao antes de decidir qualquer
    coisa ele precisa perguntar se o item ainda e do jogador.
]]

local WB_Cart = require "WB_Cart"
local WB_MP = require "WB_MP"
local WB_UI = require "WB_UI"

local WB_Hands = {}

-- Guarda de reentrancia. Nao e defensividade generica: setPrimaryHandItem
-- dispara OnEquipPrimary, que chama repair de volta. Sem ela, a primeira
-- correcao recursa e trava o jogo.
local repairing = false

--- Tira o item das duas maos, sem destruir nem largar nada.
function WB_Hands.release(character, item)
    if repairing or character == nil or item == nil then return end
    repairing = true
    if character:isPrimaryHandItem(item) then character:setPrimaryHandItem(nil) end
    if character:isSecondaryHandItem(item) then character:setSecondaryHandItem(nil) end
    repairing = false
    -- O modelo do personagem so e reconstruido quando alguem pede, e mexer nas
    -- maos por Lua nao pede. Sem isto o carrinho continua desenhado numa mao que
    -- nao o tem mais. E o que toda acao do jogo base faz depois de trocar o que
    -- esta na mao.
    character:resetModelNextFrame()
    WB_UI.refreshContainers()
end

--- O carrinho ainda pertence a este jogador?
---
--- Pergunta obrigatoria antes de reequipar. Largar tira o carrinho de UMA das
--- maos e dispara OnEquipPrimary; sem esta checagem o repair encontraria o item
--- na outra mao e o traria de volta, ja fora do inventario.
local function stillOwned(character, cart)
    if cart:getWorldItem() ~= nil then return false end
    local inv = character:getInventory()
    return inv ~= nil and inv:containsRecursive(cart)
end

--- Restaura o estado valido: o carrinho nas duas maos.
function WB_Hands.repair(character)
    if repairing then return end

    --[[ SO O JOGADOR DESTA MAQUINA, e este e o caso mais perigoso dos tres.

         setPrimaryHandItem/setSecondaryHandItem disparam OnEquipPrimary e
         OnEquipSecondary incondicionalmente, e EquipPacket.parse os chama no
         cliente PARA JOGADORES REMOTOS, com um item recem-desserializado. Como
         este arquivo REEQUIPA e DESEQUIPA, sem a guarda ele arranca o que esta na
         mao de outro jogador -- na maquina de quem esta olhando, o que produz uma
         divergencia que so o observador enxerga.

         instanceof antes de isLocalPlayer porque o evento tambem dispara para
         zumbi e animal, que nao tem esse metodo. ]]
    if not WB_MP.isLocalPlayer(character) then return end

    local cart = WB_Cart.equipped(character)
    if cart == nil then return end

    if not stillOwned(character, cart) then
        WB_Hands.release(character, cart)
        return
    end

    local primary = character:getPrimaryHandItem()
    local secondary = character:getSecondaryHandItem()
    if primary == cart and secondary == cart then return end

    repairing = true
    -- O carrinho reivindica as duas maos: quem perde a mao e a outra coisa. Assim
    -- um clique numa arma nao interrompe quem ja esta empurrando.
    character:setPrimaryHandItem(cart)
    character:setSecondaryHandItem(cart)
    repairing = false
    character:resetModelNextFrame()
    -- Toda saida deste arquivo que muda as maos avisa a UI. Este ramo e o que
    -- EQUIPA, entao e justamente onde o compartimento do carrinho precisa
    -- aparecer na barra de containers.
    WB_UI.refreshContainers()
end

Events.OnEquipPrimary.Add(function(character, _item) WB_Hands.repair(character) end)
Events.OnEquipSecondary.Add(function(character, _item) WB_Hands.repair(character) end)

return WB_Hands
