--[[
    Coloca carrinhos pelo mundo, no CHAO.

    No chao e nao em container porque o carrinho nunca pode estar num inventario --
    e a invariante do mod, e vale tambem para como ele nasce. Um carrinho dentro de
    um armario seria imediatamente empurrado para o chao pela rede de WB_Placement,
    o que funcionaria e pareceria defeito.

    ----------------------------------------------------------------------
    RARIDADE: o alvo e "raro como gerador"

    Gerador nao e raro por ter chance baixa espalhada pelo mapa. Ele so existe numa
    tabela, CrateGenerator, com `onlyOne = true` -- ou seja, ele e raro por estar
    preso a um LUGAR especifico e aparecer uma vez por lugar.

    E o mesmo formato usado aqui: um sorteio por LUGAR, uma vez na vida do save. A
    chance nao e por square; se fosse, um galpao de cem squares teria cem sorteios e
    a raridade viraria abundancia.

    ----------------------------------------------------------------------
    DOIS TIPOS DE LUGAR

      COMODO   nome do room na lista de WB_Const.SPAWN_ROOMS -- obra, galpao,
               garagem, loja de ferramentas.

      RUA      obra na via publica, reconhecida pelo CONE. Nao ha room ao ar livre,
               entao o cone e o que marca o lugar.

    Nos dois casos o sorteio e por CELULA de mapa de 10x10 squares, nao por room --
    ver SITE_SIZE, onde a razao esta explicada.

    ----------------------------------------------------------------------
    CUSTO: LoadGridsquare dispara por SQUARE no carregamento de chunk, o que sao
    milhares de chamadas. A ordem dos testes aqui e do mais barato para o mais caro,
    e o registro de lugares ja sorteados corta o trabalho na primeira square de cada
    lugar. A varredura de objetos, que e a parte cara, so acontece ao ar livre e
    depois de um filtro de tamanho.
]]

local WB_Const = require "WB_Const"
local WB_MP = require "WB_MP"
local WB_Sandbox = require "WB_Sandbox"
local WB_Spill = require "WB_Spill"

local WB_Spawn = {}

--- Sprite do cone de obra, de media/newtiledefinitions.tiles.txt (Road Cone).
local CONE_SPRITE = "street_decoration_01_27"

--[[ Tamanho do lado, em squares, do que conta como UM lugar.

     CHAVEAMOS POR CELULA DE MAPA, e nao por room, e a razao e uma armadilha:
     IsoRoom nao expoe coordenada -- so getName, getSquares e getBuilding. A saida
     obvia seria o menor x,y das squares do room, e ela e INSTAVEL: chunk carrega
     em partes, entao um galpao que atravessa dois chunks daria chaves diferentes em
     momentos diferentes e sortearia duas vezes. O id do building tambem nao serve,
     porque e contador de carregamento.

     Coordenada absoluta de mapa nao tem nenhum desses problemas, e resolve o
     aglomerado de cones pelo mesmo mecanismo: uma fila deles cai na mesma celula e
     rende um sorteio. Um galpao grande pode ocupar duas celulas e ter dois
     sorteios, o que e razoavel -- galpao grande merece mais chance que barracao. ]]
local SITE_SIZE = 10

--- @return string chave da celula que contem esta square
local function cellKey(prefix, square)
    return string.format("%s%d,%d,%d", prefix,
        math.floor(square:getX() / SITE_SIZE),
        math.floor(square:getY() / SITE_SIZE),
        square:getZ())
end

--- @return table registro persistente de lugares ja sorteados
local function ledger()
    local data = ModData.getOrCreate(WB_Const.MODDATA_SPAWN_KEY)
    if data.places == nil then data.places = {} end
    return data.places
end

--- @return boolean true na PRIMEIRA vez que este lugar e visto
local function claimPlace(key)
    local places = ledger()
    if places[key] ~= nil then return false end
    -- Marca ANTES de sortear: o que precisa ser lembrado e que o lugar foi
    -- sorteado, nao que ele venceu. Marcar so no sucesso faria todo lugar sem
    -- carrinho sortear de novo a cada recarregamento do chunk, e ai nao existiria
    -- raridade nenhuma.
    places[key] = true
    return true
end

--- @return boolean se o sorteio de raridade venceu
local function rollSucceeds()
    local chance = WB_Sandbox.get("SpawnChance")
    if chance <= 0 then return false end
    -- Milesimos em vez de inteiros: o padrao e baixo o suficiente para a resolucao
    -- de inteiro perder metade do ajuste.
    return ZombRand(100000) < chance * 1000
end

--- @return boolean se um cone de obra esta nesta square
local function hasCone(square)
    local objects = square:getObjects()
    -- O piso ja e um objeto, entao uma square vazia de rua tem tamanho 1. Cortar
    -- aqui evita a varredura na esmagadora maioria das squares ao ar livre.
    if objects == nil or objects:size() < 2 then return false end
    for i = 0, objects:size() - 1 do
        local sprite = objects:get(i):getSprite()
        if sprite ~= nil and sprite:getName() == CONE_SPRITE then return true end
    end
    return false
end

local function place(square)
    if not WB_Spill.canRest(nil, square) then return false end

    --[[ A sobrecarga que recebe o NOME DO TIPO cria e posiciona num passo.

         A versao anterior criava o item por InventoryItemFactory.CreateItem para
         girar antes de por no mundo, e QUEBROU o jogo ao andar pelo mapa: essa
         classe nao e chamada de Lua em lugar nenhum do jogo base -- aparece uma
         vez, dentro de um comentario -- e CreateItem tem dez sobrecargas
         genericas que o Lua do PZ nao resolve.

         E nao era preciso. A direcao sorteada que eu queria o engine ja da de
         graca: o construtor de IsoWorldInventoryObject sorteia worldZRotation
         quando ela chega negativa, que e o estado de um item recem-criado.
         Conferido no bytecode -- ele le worldZRotation e chama Rand.Next.

         A regra de "girar antes de entrar no mundo" continua valendo em
         WB_Spill.placeOnGround, onde o carrinho JA EXISTE e tem uma direcao
         especifica a preservar. Aqui nao ha o que preservar. ]]
    local cart = square:AddWorldInventoryItem(WB_Const.CART_TYPE, 0.5, 0.5, 0.0)
    if cart == nil then return false end
    if getDebug() then
        print(string.format("[Wheelbarrow][SPAWN] carrinho em %d,%d,%d",
            square:getX(), square:getY(), square:getZ()))
    end
    return true
end

--- @return string|nil chave do lugar, ou nil se a square nao serve
local function placeKey(square)
    local room = square:getRoom()
    if room ~= nil then
        local name = room:getName()
        if name == nil or not WB_Const.SPAWN_ROOMS[name] then return nil end
        return cellKey("r", square)
    end

    if not hasCone(square) then return nil end
    return cellKey("s", square)
end

function WB_Spawn.onLoadGridsquare(square)
    if square == nil then return end
    if WB_Sandbox.get("EnableWorldSpawn") ~= true then return end

    local key = placeKey(square)
    if key == nil then return end
    if not claimPlace(key) then return end
    if not rollSucceeds() then return end

    place(square)
end

--[[ SO QUEM DECIDE GERA CARRINHO.

     lua/server/ NAO e do servidor: GameLoadingState.enter() carrega "server" no
     cliente tambem, e e por isso que o jogo base guarda cursores de interface em
     server/BuildingObjects/. Sem esta guarda, cada cliente conectado rodava o
     proprio sorteio e criava o proprio carrinho -- que, alem de multiplicar, nao
     existiria para mais ninguem, porque AddWorldInventoryItem so transmite quando
     GameServer.server e verdadeiro.

     A guarda e `not isClient()` e nao `isServer()`: em single player os dois sao
     falsos, e ali o sorteio precisa acontecer. ]]
if WB_MP.isAuthority() then
    Events.LoadGridsquare.Add(WB_Spawn.onLoadGridsquare)
end

return WB_Spawn
