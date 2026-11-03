--[[
    Largar um cadaver arrastado dentro do carrinho.

    ----------------------------------------------------------------------
    O DEFEITO: a pagina da Workshop promete carregar cadaver e o jogo nao deixava.

    O carrinho ACEITA cadaver -- WB_AcceptItem libera quando a sandbox permite. O
    que faltava era um caminho para o jogador pedir isso. Cadaver no chao nao e item
    de inventario: e um IsoDeadBody, objeto de mundo. Nao existe no painel do chao,
    entao nao ha o que arrastar para dentro do carrinho.

    ----------------------------------------------------------------------
    O JOGO JA TEM O FLUXO, e ele nao alcanca o carrinho

    Arrastando um cadaver, o clique direito oferece "largar cadaver em <container>".
    Isso e corpseStorageCheck.lua, e ele nunca mostra o nosso carrinho por DOIS
    motivos independentes, os dois medidos no bytecode:

      1. a lista de containers vem de IsoGridSquare.getAllContainers, que varre
         getObjectContainers e getVehicleItemContainers -- objeto de mundo e
         veiculo. Item largado no chao nao entra nessa varredura.

      2. o teste ItemContainer.canHumanCorpseFit exige que o TIPO do container
         esteja numa lista fixa: bin, cardboardbox, crate, coffin, dumpster,
         fridge, freezer e mais alguns. Container que vem de item nao esta la.

    Consertar qualquer um dos dois exigiria mexer no que e do jogo. Adicionar a
    nossa opcao ao mesmo menu nao exige nada disso.

    ----------------------------------------------------------------------
    NAO PRECISOU DE ACAO CUSTOMIZADA

    ISDropCorpseIntoContainer nao refaz nenhum dos dois testes: ela so chama
    throwGrappledIntoInventory, que checa se o personagem esta agarrando e usa a
    posicao do container para virar o corpo. Conferido no bytecode -- nenhuma
    chamada a canHumanCorpseFit ali dentro. O filtro estava no menu, nao na acao.

    ----------------------------------------------------------------------
    O TEXTO E O DO JOGO, de proposito

    IGUI_Option_DropCorpseIntoContainerName ("Drop Corpse Into ") existe em todos os
    idiomas que o jogo suporta. Concatenado com o nome do item, que ja traduzimos,
    a opcao fica traduzida sem uma unica string nova -- e em mais idiomas do que os
    23 que geramos.
]]

require "TimedActions/ISDropCorpseIntoContainer"

local WB_Const = require "WB_Const"
local WB_Cart = require "WB_Cart"
local WB_Sandbox = require "WB_Sandbox"

local WB_Corpse = {}

--- Diagnostico. Cada saida antecipada diz o motivo, porque "a opcao nao aparece"
--- tem cinco causas possiveis e nenhuma delas deixa rastro sozinha.
local function trace(reason)
    if getDebug() then print("[Wheelbarrow][CADAVER] " .. reason) end
end

--- Distancia, em squares, para o carrinho aparecer no menu.
---
--- Dois porque e o alcance com que o jogador enxerga o carrinho como "aquele ali",
--- e porque a caminhada ate ele e curta o bastante para nao virar uma viagem.
local REACH = 2

--- Peso de um cadaver humano. Usado so para nao oferecer a opcao quando nao cabe.
--- Bate com Base.CorpseMale e Base.CorpseFemale em generated/items/normal.txt.
local CORPSE_WEIGHT = 20

--- @return InventoryItem|nil carrinho no chao ao alcance, com espaco
local function reachableCart(character)
    local found, seen = nil, 0
    WB_Cart.forEachOnGround(character, REACH, function(cart)
        seen = seen + 1
        if found ~= nil then return end
        local inventory = cart:getInventory()
        if inventory == nil then return end
        --[[ getEffectiveCapacity(personagem), e nao getCapacity().

             E a mesma conta que o engine faz em canHumanCorpseFit, e ela depende de
             QUEM esta carregando: Organizado multiplica a capacidade por 1.3 e
             Desorganizado por 0.7. Com getCapacity() o menu escondia a opcao num
             ponto e o engine aceitaria em outro -- duas ideias de "cabe" para a
             mesma pergunta, que e o defeito que este projeto mais repetiu.

             Capacidade e teto sobre o peso BRUTO do conteudo; a reducao de peso nao
             entra aqui. Ver o cabecalho de WB_Weight. ]]
        local room = inventory:getEffectiveCapacity(character)
        if inventory:getCapacityWeight() + CORPSE_WEIGHT > room then
            return
        end
        found = cart
    end)
    if found == nil then
        trace(string.format("nenhum carrinho utilizavel em %d square(s); vistos: %d",
            REACH, seen))
    end
    return found
end

--[[ Tipo de container que o jogo aceita para cadaver.

     canHumanCorpseFit termina em "o meu getType() esta nesta lista?" -- e a lista e
     fixa no engine: bin, cardboardbox, crate, militarycrate, clothingdryer,
     clothingwasher, coffin, doghouse, dumpster, fireplace, fridge, freezer, locker,
     militarylocker, postbox, shelter, tent, wardrobe. Container que nasce de item tem
     tipo "Container" e nunca passa.

     Nao ha outra alavanca. Nao e uma lista de exclusao, nao ha caminho por peso que
     dispense o tipo, e o teste e refeito no evento de animacao do deposito -- foi
     por isso que a animacao rodava inteira e o corpo caia no chao.

     "crate" e o analogo honesto: caixa aberta em que se despeja coisa. O tipo so e
     lido para escolher IGUI_ContainerTitle_<tipo>, e esse caminho vale para container
     de objeto de mundo e de corpo, nao para o que vem de item -- ali o titulo e o
     nome do item. Conferido em ISInventoryPage. ]]
local CORPSE_CONTAINER_TYPE = WB_Const.CORPSE_CONTAINER_TYPE

--- Da uma square ao container, se ele nao souber onde esta.
local function anchorToSquare(container, square)
    if container == nil or container:getSquare() ~= nil then return end
    container:setSourceGrid(square)
end

local function onDropCorpse(playerNum, cart)
    local character = getSpecificPlayer(playerNum)
    if character == nil or cart == nil then return end

    local worldItem = cart:getWorldItem()
    local square = worldItem and worldItem:getSquare()
    if square == nil then return end

    -- walkAdj e nao walkToContainer: walkToContainer chega em
    -- container:getParent():getSquare(), e o parent de um container que vem de item
    -- nao e um IsoObject. walkAdj recebe a square direto e e o idioma que o jogo
    -- usa em 282 lugares.
    luautils.walkAdj(character, square)

    --[[ INFORMAR A SQUARE AO CONTAINER DE FORA, senao a acao estoura.

         throwGrappledIntoInventory chama ItemContainer.getWorldPosition para virar o
         personagem na direcao do container. E getWorldPosition, ANTES de qualquer
         outra coisa, recursa no getOutermostContainer -- e para um item largado no
         chao o container de fora nao e o do carrinho, e o container "floor" da
         square. Esse nao tem square nenhuma, e o getX() nele e o
         NullPointerException.

         A primeira tentativa escreveu a square no container DO CARRINHO e nao
         mudou nada, porque a recursao nunca chega nele. A pista estava no proprio
         rastro: duas chamadas empilhadas de getWorldPosition, uma chamando a outra.

         Por isso o alvo aqui e quem devolve nil em getSquare(), seja quem for. E
         escrever a square nao e mentira: o container "floor" pertence aquela
         square e sempre pertenceu -- so ninguem tinha preenchido o campo. ]]
    local inventory = cart:getInventory()
    anchorToSquare(inventory:getOutermostContainer(), square)
    anchorToSquare(inventory, square)

    -- Sem isto o deposito e recusado no meio da animacao e o cadaver cai no chao.
    inventory:setType(CORPSE_CONTAINER_TYPE)

    ISTimedActionQueue.add(ISDropCorpseIntoContainer:new(character, inventory))
end

function WB_Corpse.onFillWorldObjectContextMenu(playerNum, context, _worldObjects)
    local character = getSpecificPlayer(playerNum)
    if character == nil then return end

    if not character:isDraggingCorpse() then
        -- isDraggingCorpse exige TRES coisas, medidas no bytecode: estar agarrando,
        -- o alvo ser IsoZombie, e isReanimatedForGrappleOnly. Cadaver arrastado e
        -- representado como zumbi reanimado so para o agarre.
        if character:isGrappling() then
            trace("agarrando, mas isDraggingCorpse e falso -- alvo nao e cadaver")
        end
        return
    end

    -- O portao da sandbox vive AQUI, e nao so em WB_AcceptItem: nao ficou
    -- estabelecido que throwGrappledIntoInventory consulte AcceptItemFunction, e
    -- uma opcao que nao deveria existir e pior do que uma que falha -- ela promete.
    if WB_Sandbox.get("AllowCorpses") ~= true then
        trace("AllowCorpses esta desligada na sandbox deste save")
        return
    end

    local cart = reachableCart(character)
    if cart == nil then return end

    trace("opcao adicionada para " .. tostring(cart:getName()))
    context:addOptionOnTop(
        getText("IGUI_Option_DropCorpseIntoContainerName") .. cart:getName(),
        playerNum, onDropCorpse, cart)
end

Events.OnFillWorldObjectContextMenu.Add(WB_Corpse.onFillWorldObjectContextMenu)

-- Prova de vida do arquivo. Lua novo so passa a existir depois de reiniciar o jogo,
-- e sem esta linha "a opcao nao aparece" e indistinguivel de "o arquivo nem carregou".
trace("WB_Corpse carregado")

return WB_Corpse
