--[[
    Reaponta, nas acoes ja enfileiradas, tudo que apontava para um carrinho que o
    multiplayer trocou por baixo.

    ----------------------------------------------------------------------
    O FATO QUE OBRIGA ISTO A EXISTIR

    Em multiplayer o cliente NAO recebe atualizacoes de um objeto: ele recebe
    objetos NOVOS. AddInventoryItemToContainerPacket.processClient cria um
    InventoryItem a partir do pacote e o adiciona ao container (offsets 156-162);
    AddItemToMapPacket faz o equivalente para o objeto de mundo, e o item que vem
    dentro dele traz o CONTEUDO junto, tambem desserializado.

    Ou seja: toda vez que o servidor confirma uma operacao com o carrinho, o
    carrinho vivo no cliente passa a ser outro objeto Java -- e os itens dentro dele
    tambem. O identificador numerico sobrevive; a referencia nao.

    Quem guardou referencia antes fica com um objeto que nao esta em lugar nenhum:
    sem container, sem objeto de mundo, sem dono. Endereca-lo para a rede termina em

        IllegalStateException: Unable to resolve container location.
            at ContainerID.set(ContainerID.java:145)

    que foi o erro que apareceu ao transferir tronco para o carrinho estacionado.

    ----------------------------------------------------------------------
    POR QUE UM MODULO E NAO UM CONSERTO NO LUGAR ONDE DOEU

    Porque o mesmo aprendizado ja apareceu TRES vezes neste porte, cada vez num
    lugar diferente e cada vez custando uma rodada de teste em jogo:

      1. WB_Parking guardava o carrinho estacionado e pedia o objeto de mundo dele
         na volta -- passou a procurar por id (findOnGround);
      2. o cliente ficava com objeto de mundo obsoleto depois de pegar -- passou a
         apagar por id (forgetStrayWorldObjects);
      3. ISInventoryTransferAction guardava o compartimento do carrinho no new() e
         nao transferia nada -- e o que trouxe este arquivo.

    Tres sintomas, uma causa. O quarto lugar vai aparecer, e quando aparecer o
    conserto e uma chamada e nao uma investigacao.

    ----------------------------------------------------------------------
    O QUE ELE REAPONTA, e por que a fila inteira

    ISInventoryTransferAction e ISGrabItemAction guardam quatro coisas que podem
    envelhecer: srcContainer, destContainer, item, e a lista queueList de levas
    agrupadas. Reapontar so a que doeu deixaria as outras tres para a proxima
    rodada.

    A regra e sempre a mesma e e conservadora: SO troca quando o id bate e o objeto
    difere. Nunca inventa destino, nunca mexe em acao que ja esta correta.
]]

local WB_Cart = require "WB_Cart"
local WB_Const = require "WB_Const"
local WB_MP = require "WB_MP"
local WB_Trace = require "WB_Trace"

local WB_Rebind = {}

--- O carrinho vivo acabou de ser posto ao alcance do braco do personagem. Mesmo
--- alcance de todo o resto -- ver WB_Const.CART_REACH.
local SEARCH_RADIUS = WB_Const.CART_REACH

--- Campos em que as acoes do jogo base guardam um ItemContainer.
local CONTAINER_FIELDS = { "destContainer", "srcContainer", "targetContainer" }

--- @return InventoryItem|nil o carrinho de identificador `id` como ele existe AGORA
---
--- Procura nos tres lugares em que ele pode estar, porque esta funcao serve tanto
--- ao largar (vai para o chao) quanto ao pegar (vai para as maos).
local function findLive(character, id)
    local inv = character:getInventory()
    if inv ~= nil then
        local live = inv:getItemWithID(id)
        if live ~= nil then return live end
    end

    local found = nil
    WB_Cart.forEachOnGround(character, SEARCH_RADIUS, function(item, _obj, _sq)
        if found == nil and item:getID() == id then found = item end
    end)
    return found
end

--- Mapa id -> objeto vivo, do carrinho e de tudo que esta dentro dele.
---
--- O conteudo entra porque ele e trocado junto: o item serializado carrega o
--- proprio compartimento, entao um tronco dentro do carrinho tambem vira objeto
--- novo. Tirar carga do carrinho estacionado passaria pelo mesmo defeito.
local function liveIndex(live)
    local index = { [live:getID()] = live }
    local inside = live:getInventory()
    if inside ~= nil then
        local items = inside:getItems()
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            index[item:getID()] = item
        end
    end
    return index
end

--[[ ESTA FILA NAO E NOSSA, E OS CAMPOS DELA NAO TEM TIPO GARANTIDO.

     Relatado em 17/08/2026 num servidor com 113 mods, versao 0.3.0:

         Object tried to call nil in rebindItem   (WB_Rebind.lua:111)
             <- queuedActions (WB_Rebind.lua:175)
             <- perform (ISWheelbarrowPutDown.lua:259)

     `item:getID` era nil: o campo `action.item` de uma acao de OUTRO mod nao guardava
     um InventoryItem. E o nome mais comum que existe numa timed action -- outro mod
     pode guardar ali uma tabela de opcoes, um IsoObject, uma string.

     A versao anterior tinha um comentario dizendo que era "conservadora de proposito"
     e que uma acao apontando para "outra coisa" sairia intacta. O engano estava no
     que "outra coisa" queria dizer: eu pensei em outro ITEM -- uma mochila, o chao --
     e nunca em outro TIPO. Com 113 mods na fila, e outro tipo.

     Daqui sai a regra para as proximas: percorrer a fila de acoes e ler dado de
     terceiro, e todo campo lido precisa de instanceof antes do primeiro metodo. O
     mesmo vale para os containers logo abaixo, que tinham a suposicao identica e
     ainda nao estouraram so porque destContainer/srcContainer sao nomes menos
     disputados que `item`. ]]

--- @return any o objeto vivo equivalente, ou o proprio quando nao ha troca a fazer
---
--- Conservador de proposito: devolve o original sempre que o tipo nao for de item ou
--- o id nao estiver no indice. Uma acao que aponte para outra coisa -- uma mochila, o
--- chao, um item que nunca passou pelo carrinho, ou um campo de outro mod que nem e
--- item -- sai daqui intacta.
local function rebindItem(index, item)
    if item == nil then return item, false end
    if not instanceof(item, "InventoryItem") then return item, false end
    local live = index[item:getID()]
    if live == nil or live == item then return item, false end
    return live, true
end

--- @return ItemContainer|nil, boolean
local function rebindContainer(index, container, liveContainer)
    if container == nil or container == liveContainer then return container, false end
    if not instanceof(container, "ItemContainer") then return container, false end
    local holder = container:getContainingItem()
    if holder == nil then return container, false end
    if index[holder:getID()] == nil then return container, false end
    return liveContainer, true
end

--- Reaponta a fila de acoes do personagem para o carrinho vivo.
---
--- @param character IsoGameCharacter
--- @param id number identificador do carrinho que acabou de mudar de lugar
function WB_Rebind.queuedActions(character, id)
    --[[ SO NO CLIENTE MP.

         Em single player e no processo que hospeda nao ha troca de objeto: o
         carrinho que a acao guardou continua sendo o mesmo, e reapontar seria
         percorrer a fila para nao trocar nada.

         No servidor dedicado nao ha fila de Lua nenhuma -- ISTimedActionQueue e do
         cliente -- entao a guarda tambem evita um nil. ]]
    if WB_MP.isAuthority() then return end
    if character == nil or id == nil then return end

    local queue = ISTimedActionQueue.queues[character]
    if queue == nil or queue.queue == nil or queue.queue[1] == nil then return end

    local live = findLive(character, id)
    if live == nil then
        WB_Trace.log("FILA", "reapontar: carrinho #" .. id .. " nao encontrado")
        return
    end

    local index = liveIndex(live)
    local liveContainer = live:getInventory()
    local changed = 0

    for _, action in ipairs(queue.queue) do
        local swapped

        --[[ POR NOME DE CAMPO, e a lista tem dono.

             Cada acao do jogo base batiza o container dela como quer.
             ISInventoryTransferAction usa srcContainer e destContainer;
             ISDropCorpseIntoContainer usa targetContainer -- e foi ele que
             apareceu depois, exatamente como o cabecalho deste arquivo previu.

             Reapontar por nome e feio e e o que da para fazer: nao ha interface
             comum entre as acoes, e varrer TODOS os campos da tabela procurando
             ItemContainer trocaria um problema conhecido por um risco desconhecido
             -- mexeria em campo de outro mod sem saber o que ele significa.

             Quando o quinto nome aparecer, ele entra aqui. ]]
        for _, field in ipairs(CONTAINER_FIELDS) do
            action[field], swapped = rebindContainer(index, action[field], liveContainer)
            if swapped then changed = changed + 1 end
        end

        action.item, swapped = rebindItem(index, action.item)
        if swapped then changed = changed + 1 end

        -- As levas agrupadas: ISInventoryTransferAction e ISGrabItemAction juntam
        -- itens do mesmo tipo em queueList para transferir de uma vez, e cada
        -- entrada guarda a propria lista de referencias.
        if type(action.queueList) == "table" then
            for _, entry in ipairs(action.queueList) do
                if type(entry) == "table" and type(entry.items) == "table" then
                    for i = 1, #entry.items do
                        entry.items[i], swapped = rebindItem(index, entry.items[i])
                        if swapped then changed = changed + 1 end
                    end
                end
            end
        end
    end

    if changed > 0 then
        WB_Trace.log("FILA", string.format(
            "reapontar: %d acoes na fila, %d referencias trocadas para o carrinho vivo #%d",
            #queue.queue, changed, id))
    end
end

return WB_Rebind
