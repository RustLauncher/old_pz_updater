--[[
    O carrinho so existe em dois lugares: no chao, ou nas maos.

    NUNCA no inventario desequipado. Ver docs/carrinho-nunca-no-inventario.md
    para o estudo; o resumo do que importa aqui:

    "Nunca no inventario" nao e implementavel ao pe da letra -- no PZ, mao e um
    slot que APONTA para um item do inventario, nao um lugar separado, entao um
    item equipado esta no inventario por definicao. A invariante que da para
    sustentar, e que entrega o mesmo na pratica, e a de duas posicoes.

    QUATRO REGRAS, e as tres primeiras existem pela experiencia enquanto a quarta
    existe pela garantia:

      R1  o carrinho nao entra em container nenhum
      R2  chao -> maos so pela acao cronometrada; o "Pegar" do jogo e desviado
          para ela, por qualquer caminho de menu
      R3  maos -> chao tambem pela acao cronometrada
      R4  carrinho desequipado em inventario vai para o chao

    R4 e a rede. As outras cobrem os caminhos que eu conheco; R4 cobre os que eu
    nao conheco -- spawn pelo menu de debug, morte, outro mod transferindo, algum
    fluxo do jogo que nao mapeei. Sem ela a invariante seria "verdadeira nos casos
    que eu lembrei", que e o tipo de garantia que quebra depois de publicada.

    POR QUE TUDO NUM ARQUIVO: as quatro sao uma invariante so, vista de quatro
    lados. Separadas por arquivo, a proxima pessoa mexe numa e deixa as outras
    contradizendo -- que e exatamente como o WB_Hands quebrou duas vezes.
]]

require "TimedActions/ISWheelbarrowPickUp"
require "TimedActions/ISWheelbarrowPutDown"

local WB_Cart = require "WB_Cart"
local WB_Interact = require "WB_Interact"
local WB_MP = require "WB_MP"
local WB_Spill = require "WB_Spill"
local WB_Trace = require "WB_Trace"
local WB_Transfer = require "WB_Transfer"

local WB_Placement = {}

--- Evita reentrancia: largar dispara eventos que voltam para ca.
local settling = false

--- Larga o carrinho no chao imediatamente, sem animacao.
---
--- Este e o caminho da REDE (R4), nao o do jogador. O caminho do jogador tem
--- animacao e pode ser cancelado; aqui o estado ja e invalido e o objetivo e so
--- sair dele.
---
--- A colocacao em si e de WB_Spill, que e quem as timed actions tambem usam ao
--- cancelar. Duas copias divergiriam no dia em que uma delas ganhasse um passo a
--- mais -- e aqui esquecer de tirar das maos deixaria o carrinho-fantasma.
function WB_Placement.forceToGround(character, cart)
    if settling then return end
    WB_Trace.item("R4", "carrinho solto no inventario -> chao", cart, character)
    settling = true
    WB_Spill.dropCart(character, cart)
    settling = false
end

--- R1 + R4: procura carrinho desequipado no inventario do jogador, em qualquer
--- profundidade, e poe no chao.
---
--- A busca e recursiva porque R1 tem de valer para mochila dentro de mochila. O
--- custo e baixo: so entra em containers, e o caso comum -- nenhum carrinho solto
--- -- termina na primeira varredura rasa.
--- Teto de passadas por container. Rede de seguranca, nao a regra -- a regra e a
--- conferencia de progresso abaixo. Um carrinho por passada, e nenhum inventario real
--- tem oito carrinhos soltos.
local MAX_PASSES = 8

local function settleLoose(character, container, depth)
    if container == nil or depth > 3 then return end

    --[[ LACO, E NAO RECURSAO NA MESMA PROFUNDIDADE. Isto travava o jogo.

         Relatado em 17/08/2026: usar "colocar no chao" do jogo base com o carrinho
         na mao enchia a pilha de settleLoose e caia no depurador de Lua.

         A versao anterior terminava assim:

             if loose ~= nil then
                 WB_Placement.forceToGround(character, loose)
                 settleLoose(character, container, depth)   -- MESMA profundidade
             end

         Ela supoe que forceToGround SEMPRE remove o carrinho do container. Nao
         remove, por dois caminhos medidos: forceToGround sai cedo quando `settling`
         esta ligado, e WB_Spill.dropCart nao faz nada quando o carrinho JA tem objeto
         de mundo -- que e precisamente o estado que o drop do jogo base produz, item
         com objeto de mundo e ainda na lista do inventario. Sem remocao, a recursao
         reencontra o mesmo carrinho para sempre.

         Agora cada passada tem de PROVAR progresso: se o carrinho continua no
         container depois da tentativa, desiste em vez de insistir. Isso garante
         terminacao sem depender de forceToGround ter funcionado. ]]
    for _pass = 1, MAX_PASSES do
        local items = container:getItems()
        local loose = nil

        for i = 0, items:size() - 1 do
            local item = items:get(i)
            if WB_Cart.is(item) then
                --[[ "SOLTO NO INVENTARIO" EXCLUI O QUE JA ESTA NO CHAO.

                     Um item recem-colocado no mundo continua na lista do container
                     por um instante: o construtor de IsoWorldInventoryObject faz
                     setContainer(null) mas NAO tira o item da lista. Ler a lista sem
                     olhar o objeto de mundo confunde "solto no inventario" com "ja
                     esta no chao, a lista e que esta velha" -- e mandar para o chao o
                     que ja esta no chao e o que nao progredia.

                     Mesma licao do conserto de pegar: o objeto de mundo e o sinal,
                     nao o container. ]]
                if item:getWorldItem() == nil
                    and not character:isPrimaryHandItem(item)
                    and not character:isSecondaryHandItem(item) then
                    loose = item
                    break
                end
            elseif instanceof(item, "InventoryContainer") then
                settleLoose(character, item:getInventory(), depth + 1)
            end
        end

        if loose == nil then return end

        WB_Placement.forceToGround(character, loose)

        -- A conferencia de progresso. contains raso de proposito: a pergunta e "saiu
        -- DESTE container", e nao "existe em algum lugar".
        if container:contains(loose) then
            WB_Trace.log("R4", "carrinho #" .. loose:getID()
                .. " nao saiu do inventario -- desistindo em vez de insistir")
            return
        end
    end
end

--[[ @return boolean se ja ha um largar nosso a caminho para este personagem

     A R4 NAO PODE VENCER A CORRIDA CONTRA UM LARGAR JA ENFILEIRADO.

     Os caminhos do jogo base que desviamos enfileiram um ISUnequipAction ANTES da
     acao de largar -- dropItem faz isso com reason "drop", o cursor de posicionamento
     com reason "place". Entre o desequipar terminar e a nossa acao comecar, o carrinho
     fica solto no inventario por alguns quadros, e e exatamente esse o estado que a R4
     existe para desfazer.

     Sem esta guarda a R4 ganharia: poria o carrinho no chao na hora, sem animacao, e a
     acao cronometrada chegaria depois encontrando servico feito -- nenhuma janela para
     cancelar, ou seja, a mecanica de derrubar some justamente nos caminhos que
     acabamos de desviar para preserva-la.

     A R4 continua valendo para o que interessa: carrinho que aparece solto num
     inventario SEM largar a caminho -- craft, /additem, outro mod, morte. ]]
local function putDownPending(character)
    local queue = ISTimedActionQueue.queues[character]
    if queue == nil or queue.queue == nil then return false end
    for _, action in ipairs(queue.queue) do
        if action ~= nil and action.Type == "ISWheelbarrowPutDown" then return true end
    end
    return false
end

function WB_Placement.enforce(character)
    if settling or WB_Transfer.active() then return end
    if putDownPending(character) then return end

    --[[ A R4 NAO RODA NO CLIENTE MP, e isto foi aprendido em jogo do jeito caro.

         O SINTOMA: transferir troncos do chao para o carrinho duplicava o carrinho.
         O jogador terminava com dois carrinhos vazios e a carga em lugar nenhum.

         A CAUSA: quando o servidor conclui o pegar, ele manda dois pacotes -- o
         AddInventoryItemToContainer e depois o Equip. Entre um e outro, no cliente,
         o carrinho esta no inventario e ainda NAO esta na mao. Esse e exatamente o
         estado que a R4 existe para destruir. Ela dispara no meio do caminho, larga
         o carrinho no chao localmente, e o AddWorldInventoryItem do cliente nao
         chega a ninguem: sobra o carrinho do servidor mais um fantasma local.

         Nao ha guarda de temporizacao que resolva. O estado "no inventario, ainda
         nao equipado" nao e invalido em multiplayer -- e um passo legitimo da
         sincronizacao, e passar por ele e obrigatorio. Uma regra que trata passo
         legitimo como corrupcao esta simplesmente no processo errado.

         E a R4 e uma REGRA DE MUNDO: ela decide onde um item existe. Isso e do
         dono do mundo. O cliente nao pode nem executa-la corretamente (nao consegue
         por objeto no mundo) nem julgar corretamente (nao sabe se o estado e dele
         ou do servidor).

         O QUE ISSO CUSTA, dito por inteiro: em multiplayer a rede de seguranca das
         quatro regras deixa de existir. Um carrinho que apareca desequipado num
         inventario por um caminho que o mod nao conhece -- /additem, morte, outro
         mod -- fica la ate alguem equipar. Isso e pior que hoje? Nao: hoje ele vira
         um fantasma que contradiz o servidor. Mas e divida, e ela tem dono: a R4
         precisa de uma versao que rode no servidor, e isso e o que sobrou do item 3
         do HANDOFF.

         A guarda de jogador local continua junto, e nao e redundante: em single
         player com tela dividida enforce roda por jogador. ]]
    if not WB_MP.isAuthority() then return end
    if not WB_MP.isLocalPlayer(character) then return end

    settleLoose(character, character:getInventory(), 0)
end

--- getNumActivePlayers/getSpecificPlayer so enxergam a tela LOCAL -- no maximo
--- quatro, em tela dividida -- e nunca os jogadores remotos. Aqui isso e
--- exatamente o que se quer, e a guarda de enforce cobre o resto.
local function enforceAll()
    for i = 0, getNumActivePlayers() - 1 do
        WB_Placement.enforce(getSpecificPlayer(i))
    end
end

Events.OnContainerUpdate.Add(enforceAll)

-- R3 por tabela: desequipar deixa o carrinho no inventario, e OnContainerUpdate
-- nem sempre dispara nesse caminho. Estes dois pegam o momento exato em que a
-- mao esvazia.
Events.OnEquipPrimary.Add(function(character, _item) WB_Placement.enforce(character) end)
Events.OnEquipSecondary.Add(function(character, _item) WB_Placement.enforce(character) end)

--[[
    R2: pegar um carrinho do chao vira a NOSSA acao, por qualquer caminho.

    A primeira tentativa removia a opcao "Pegar" do menu por NOME, e nao
    funcionou por dois motivos. O nome nao e unico -- ha oito pontos no jogo que
    criam essa opcao, e o menu do chao nao e o mesmo do painel de chao do
    inventario. E remover por nome e grosseiro: "Pegar" vale para a square
    inteira, entao tira-la com outros itens caidos ali deixaria o jogador sem
    como pegar aquilo.

    Interceptar a ACAO resolve os dois de uma vez. Todos os oito caminhos
    terminam em ISGrabItemAction:new, entao envolvemos o construtor: quando o
    objeto e um carrinho, devolvemos a nossa acao no lugar. Ela deriva da mesma
    base, entao a fila trata as duas igual, e quem chamou nao precisa saber.

    O menu continua com as opcoes do jogo, no lugar de sempre -- so o que elas
    fazem muda.
]]
Events.OnGameStart.Add(function()
    if ISGrabItemAction ~= nil then
        local original = ISGrabItemAction.new
        ISGrabItemAction.new = function(self, character, worldItem, time)
            if worldItem ~= nil and instanceof(worldItem, "IsoWorldInventoryObject")
                and WB_Cart.is(worldItem:getItem()) then
                return ISWheelbarrowPickUp:new(character, worldItem)
            end
            return original(self, character, worldItem, time)
        end
    end

    --[[ SEGUNDO caminho, e foi por ele que o "Pegar" continuou funcionando: o
         painel de CHAO do inventario nao usa ISGrabItemAction. Ele chama
         onGrabItems, que enfileira uma transferencia comum. Dois menus com o
         mesmo rotulo e implementacoes diferentes -- razao a mais para o desvio
         ser por acao e nao por nome de opcao.

         Aqui a lista e PARTIDA: carrinhos vao para a nossa acao e o resto segue
         pelo caminho do jogo. Desviar a lista inteira faria pegar um carrinho
         junto com outros itens deixar os outros para tras. ]]
    --[[ O ESPELHO DO DESVIO DE PEGAR, e ele existe para a MECANICA sobreviver.

         Pedido do Marcos em 17/08/2026, e a razao esta certa: largar o carrinho pelos
         caminhos do jogo base -- a opcao "colocar no chao" e arrastar para fora do
         inventario -- punha o carrinho no chao SEM passar pela nossa acao
         cronometrada, e portanto sem a janela em que interromper derruba a carga. A
         mecanica central do mod desaparecia por duas portas laterais.

         O conserto anterior tinha so ensinado o estacionamento a nao brigar com esses
         caminhos. Isto e melhor: em vez de tolerar o caminho do jogo, ele passa a ser
         o NOSSO caminho, exatamente como ja acontece com o "Pegar" acima.

         UM GANCHO SO COBRE OS DOIS, e isso foi medido. O menu termina em

             ISInventoryTransferUtil.newInventoryTransferAction(playerObj, item,
                 item:getContainer(), ISInventoryPage.GetFloorContainer(player))

         e o arraste para o chao faz a mesma chamada -- ISInventoryPane.lua:651, dentro
         do ramo `elseif container:getType() == "floor"`. A fabrica devolve
         ISInventoryTransferAction:new, entao envolver o construtor pega os dois e mais
         qualquer caminho futuro que mande o carrinho para o chao por transferencia.

         A CONDICAO E ESTREITA de proposito: so carrinho, e so quando o destino e um
         container de tipo "floor". Transferir o carrinho para uma mochila, ou qualquer
         outro item para o chao, segue pelo caminho do jogo intacto. ]]
    if ISInventoryTransferAction ~= nil then
        local originalTransfer = ISInventoryTransferAction.new
        ISInventoryTransferAction.new = function(self, character, item, srcContainer,
                                                destContainer, time)
            local toContainer = destContainer ~= nil
                and instanceof(destContainer, "ItemContainer")

            if character ~= nil and WB_Cart.is(item) and toContainer then
                if destContainer:getType() == "floor" then
                    WB_Trace.log("DESVIO",
                        "transferencia do carrinho para o chao -> acao cronometrada")
                    return ISWheelbarrowPutDown:new(character, item)
                end

                --[[ O CARRINHO NAO ENTRA EM CONTAINER NENHUM. Regra do Marcos,
                     17/08/2026, e ela e fisica antes de ser de jogo: nao se carrega
                     um carrinho de mao dentro de uma mochila, do porta-malas de um
                     carro ou de um armario.

                     O mod ja tinha a regra, mas so na forma CORRETIVA -- a R4 de
                     settleLoose, que tira o carrinho depois de ele ja ter entrado.
                     E a R4 nao roda no cliente MP, entao la a regra simplesmente nao
                     existia: o jogador guardava o carrinho na mochila e ele ficava.

                     Este e o lado PREVENTIVO, e ele cobre tudo de uma vez porque todo
                     caminho de guardar passa por aqui: arrastar no inventario, as
                     opcoes de mover do menu, o porta-malas, o "pegar tudo" de um
                     container. Bloquear por menu exigiria enumerar caminhos, e
                     enumerar caminhos e a lista que envelhece.

                     A RECUSA E DO JOGO BASE, nas duas pontas. `ignoreAction` e o que
                     ISTimedActionQueue.add consulta na PRIMEIRA linha para descartar
                     uma acao sem executar nada, e HaloTextHelper.addBadText e o que
                     ele mesmo usa duas linhas abaixo para recusar acao com cadaver
                     nos bracos. E a acao devolvida continua sendo um objeto valido --
                     quem guardar a referencia em vez de enfileirar nao quebra.

                     A mensagem e IGUI_ToHeavy, "muito pesado para o inventario", que
                     e chave do jogo base e portanto ja vem nos 23 idiomas. Uma chave
                     nossa seria mais precisa e viria em ingles para quase todo mundo.

                     LIMITE, dito por inteiro: isto e regra de CLIENTE. WB_Placement
                     mora em client/, que o servidor dedicado nao executa. Para
                     jogador honesto vale; cliente modificado ignora. E o mesmo
                     trade-off do teto de carga leve, e pela mesma razao -- enforcar no
                     servidor exigiria expulsar item ja aceito. ]]
                local refused = originalTransfer(self, character, item, srcContainer,
                    destContainer, time)
                refused.ignoreAction = true
                WB_Trace.log("DESVIO", "recusado: carrinho nao entra em container "
                    .. tostring(destContainer:getType() or "?"))
                if HaloTextHelper ~= nil and instanceof(character, "IsoPlayer")
                    and character:isLocalPlayer() then
                    HaloTextHelper.addBadText(character, getText("IGUI_ToHeavy"))
                end
                return refused
            end

            return originalTransfer(self, character, item, srcContainer,
                destContainer, time)
        end
    end

    --[[ E O MENU DE LARGAR TAMBEM, porque so o desvio acima nao bastaria.

         ISInventoryPaneContextMenu.dropItem enfileira DUAS coisas quando o item esta
         na mao:

             if playerObj:isHandItem(item) then
                 ISTimedActionQueue.add(ISUnequipAction:new(playerObj, item, 1, "drop"))
             ...
             ISTimedActionQueue.add(<a transferencia, ja desviada acima>)

         Com apenas o desvio da transferencia, o desequipar continuaria rodando ANTES
         dela e deixaria o carrinho solto no inventario por um instante -- e a R4 poe
         no chao todo carrinho solto, sem animacao. A R4 ganharia a corrida e a acao
         cronometrada chegaria depois, encontrando servico feito: nenhuma janela para
         cancelar, que e justamente o que este conserto quer preservar.

         Desviando o dropItem inteiro, o carrinho vai para o chao por UMA acao, a
         nossa, que ja tira das maos sozinha em WB_Spill.dropCart. ]]
    if ISInventoryPaneContextMenu ~= nil and ISInventoryPaneContextMenu.dropItem then
        local originalDrop = ISInventoryPaneContextMenu.dropItem
        ISInventoryPaneContextMenu.dropItem = function(item, player)
            local character = getSpecificPlayer(player)
            if character ~= nil and WB_Cart.is(item) then
                WB_Trace.log("DESVIO", "largar do menu -> acao cronometrada")
                ISTimedActionQueue.add(ISWheelbarrowPutDown:new(character, item))
                return
            end
            return originalDrop(item, player)
        end
    end

    --[[ O CURSOR DE POSICIONAMENTO, e ele merece tratamento proprio.

         "Colocar item no chao" nao e um largar: e o ISPlace3DItemCursor, que deixa o
         jogador ESCOLHER a square e termina em

             ISDropWorldItemAction:new(chr, item, selectedSqDrop, ...)

         Essa acao do jogo base ja e cronometrada -- por isso ela nao parecia um
         buraco --, mas e a cronometragem DELA: cancelar no meio nao derrama a carga
         nem tomba o carrinho, que e a mecanica inteira do mod.

         Desviar aqui sem mais nada custaria ao jogador a unica forma de escolher onde
         o carrinho fica. Entao a square escolhida VAI JUNTO, como terceiro argumento
         da nossa acao -- ver ISWheelbarrowPutDown:new. O jogador mantem a precisao e
         ganha a mecanica. ]]
    --[[ OS NOMES DOS PARAMETROS ABAIXO SAO COPIA EXATA DA ORIGINAL, E ISSO NAO E
         ESTILO -- E O CONTRATO DE REDE. NAO TROQUE, NAO ABREVIE, NAO USE `...`.

         ISDropWorldItemAction mora em shared/ e declara complete(), logo e REPLICADA.
         NetTimedAction.set (offsets 58-141) le o Prototype da funcao que estiver em
         .new e usa os NOMES DOS PARAMETROS dela como os campos a serializar.

         Envolver `new` com outra assinatura troca essa lista. Foi o que eu fiz, e
         quebrou COLOCAR QUALQUER ITEM, para todos os jogadores, em multiplayer --
         relatado em 17/08/2026:

             Lua(Vanilla).complete(ISDropWorldItemAction.lua:81)
             attempted index: AddWorldInventoryItem of non-table: null
                 at NetTimedAction.perform -> GameServer.main

         O envelope declarava `square` onde a original declara `sq`, entao o cliente
         deixou de serializar o campo `sq` e o servidor reconstruiu a acao com a square
         nula. Nada disso e do carrinho: o defeito atingia todo item do jogo, porque o
         envelope substitui `new` para todas as chamadas, nao so as nossas.

         O aviso ja estava escrito neste repositorio -- cabecalho de WB_CorpseTrace,
         que explica por que ele envolve start/perform/complete e NAO `new` -- e eu
         fiz assim mesmo. Existe agora um checker: assets/tools_check_wrappers.py. ]]
    if ISDropWorldItemAction ~= nil then
        local originalDropWorld = ISDropWorldItemAction.new
        ISDropWorldItemAction.new = function(self, character, item, sq, xoffset,
                                             yoffset, zoffset, rotation, isMultiple)
            if character ~= nil and WB_Cart.is(item) then
                WB_Trace.log("DESVIO",
                    "cursor de posicionamento -> acao cronometrada, com a square escolhida")
                return ISWheelbarrowPutDown:new(character, item, sq)
            end
            return originalDropWorld(self, character, item, sq, xoffset, yoffset,
                zoffset, rotation, isMultiple)
        end
    end

    if ISInventoryPaneContextMenu ~= nil and ISInventoryPaneContextMenu.onGrabItems then
        local original = ISInventoryPaneContextMenu.onGrabItems
        ISInventoryPaneContextMenu.onGrabItems = function(items, player)
            local character = getSpecificPlayer(player)
            local actual = ISInventoryPane.getActualItems(items)
            local rest = {}

            for _, item in ipairs(actual or {}) do
                local worldItem = WB_Cart.is(item) and item:getWorldItem() or nil
                if character ~= nil and worldItem ~= nil then
                    ISTimedActionQueue.add(
                        ISWheelbarrowPickUp:new(character, worldItem))
                else
                    rest[#rest + 1] = item
                end
            end

            if #rest > 0 then return original(rest, player) end
        end
    end
end)

--[[
    Tecla de interagir: pega o carrinho perto, ou larga o que esta na mao.

    A mesma tecla nos dois sentidos, como num veiculo. E ela e tratada por NOS,
    de proposito: o caminho de veiculo do jogo depende de BaseVehicle.getBestSeat,
    cujo bytecode inteiro e `iconst_m1; ireturn` -- sempre -1, para qualquer
    veiculo, na B42. Aquele caminho nunca funciona sozinho, e isso ja custou tres
    rodadas de investigacao neste projeto.
]]
local SEARCH_RADIUS = 1

local function nearestCartOnGround(character)
    local best, bestObject = nil, nil
    WB_Cart.forEachOnGround(character, SEARCH_RADIUS, function(item, obj, _sq)
        if best == nil then
            best, bestObject = item, obj
        end
    end)
    return best, bestObject
end

--- Pegar ou largar o carrinho. Chamado por WB_Interact SO quando o engine nao
--- reivindicou a tecla de interagir -- por isso nao precisa perguntar aqui se ha
--- uma porta, um portao ou um veiculo por perto.
local function onInteract(character)
    if character == nil or character:isDead() then return end

    --[[ PORTA OU PORTAO NA FRENTE: a tecla e do jogo, nao nossa.

         getContextDoorOrWindowOrWindowFrame e a PROPRIA pergunta que o engine faz
         ao decidir o que a tecla de interagir vai fazer -- ela cobre porta, portao
         (IsoThumpable com isDoor), janela e vao de janela. Usar a funcao do engine
         em vez de varrer a square por conta propria e o que impede a nossa ideia de
         "tem uma porta aqui" de divergir da dele.

         Isto nao depende do gancho de acoes contextuais, e e de proposito: a
         primeira tentativa de resolver este defeito dependia dele e nao funcionou
         em jogo. ]]
    if character:getContextDoorOrWindowOrWindowFrame(character:getDir()) ~= nil then
        return
    end
    -- Nao atropela outra acao em andamento: a tecla de interagir e compartilhada
    -- com o resto do jogo.
    if ISTimedActionQueue.isPlayerDoingAction(character) then return end

    local carried = WB_Cart.equipped(character)
    if carried ~= nil then
        ISTimedActionQueue.add(ISWheelbarrowPutDown:new(character, carried))
        return
    end

    local _item, worldItem = nearestCartOnGround(character)
    if worldItem ~= nil then
        ISTimedActionQueue.add(ISWheelbarrowPickUp:new(character, worldItem))
    end
end

WB_Interact.setCartAction(onInteract)

Events.OnKeyPressed.Add(function(key)
    if not getCore():isKey("Interact", key) then return end
    local character = getSpecificPlayer(0)
    if character ~= nil then WB_Interact.press(character) end
end)

return WB_Placement
