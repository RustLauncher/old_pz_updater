--[[
    Derrama o conteudo do carrinho no chao.

    Usado quando o jogador CANCELA a acao de pegar ou de largar: o carrinho
    desequilibra e a carga vai ao chao. E a punicao por interromper a manobra, e
    o que da peso a decisao de parar no meio.

    POR QUE ESPALHA EM VEZ DE JOGAR TUDO NUMA SQUARE:

    O jogo limita o peso de itens no chao POR SQUARE. Esta em
    ISDropWorldItemAction:isValid():

        local ground = self.sq:getTotalWeightOfItemsOnFloor()
        if ground + self.item:getUnequippedWeight() > 50 then return false end

    Um carrinho cheio passa facil desse limite -- e o ponto dele e justamente
    carregar mais que isso. Despejar tudo numa square so criaria uma pilha que o
    proprio jogo considera invalida, e itens em square sobrecarregada tem
    comportamento imprevisivel ao salvar e recarregar.

    Entao o derrame respeita o mesmo orcamento que o jogo usa, e transborda para
    as squares vizinhas. Espalhar tambem e o que PARECE certo: carga que tomba
    de um carrinho rola para os lados.

    ----------------------------------------------------------------------
    MULTIPLAYER: NADA DAQUI SINCRONIZA QUANDO RODA NO CLIENTE.

    AddWorldInventoryItem so transmite quando quem executa e o servidor --
    medido em IsoGridSquare.AddWorldInventoryItem(InventoryItem,FFFZZ), offsets
    520-536: `iload 5; ifeq; getstatic GameServer.server; ifeq;
    transmitCompleteItemToClients`. O quinto argumento e um interruptor
    (a sobrecarga de quatro argumentos passa `true`), mas o `getstatic` depois
    dele nao tem alternativa: nao existe pacote cliente->servidor que ponha item
    no mundo.

    Entao as funcoes deste arquivo tem UM lugar correto de execucao em
    multiplayer -- dentro dos ganchos de servidor da acao cronometrada
    (serverStart, complete, serverStop). Chamadas do cliente continuam mudando o
    mundo LOCAL e nunca sincronizam.

    Sobrou UM chamador de cliente, e ele e divida conhecida: a rede R4 de
    WB_Placement, que larga no chao todo carrinho desequipado que encontre num
    inventario. Em multiplayer ela conserta um estado que pode ser do servidor,
    mexendo so no mundo local -- e e o que falta decidir do item 3 do HANDOFF. O
    estacionamento, que era o outro chamador, deixou de ser: ele passou a largar e
    a pegar o carrinho pelas acoes cronometradas, que rodam no servidor.

    O que MUDA de lado esta marcado com WB_MP.isAuthority(), e a regra e sempre a
    mesma: quem nao pode POR o item no mundo tambem nao pode avisar a rede que o
    tirou do container -- senao o servidor apaga o carrinho e ninguem o recria.
]]

local WB_Spill = {}
local WB_Const = require "WB_Const"
local WB_MP = require "WB_MP"
local WB_Trace = require "WB_Trace"
local WB_UI = require "WB_UI"

--- Mesmo teto que ISDropWorldItemAction usa para recusar um item no chao.
local SQUARE_WEIGHT_BUDGET = 50

--- Ordem de busca a partir da square de origem: o centro primeiro, depois os
--- oito vizinhos. Empilhar no centro ate o limite e so entao transbordar deixa a
--- pilha visualmente coerente com "caiu daqui".
local OFFSETS = {
    { 0, 0 },
    { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 },
    { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 },
}

--- Onde qualquer coisa deste mod pode ser deixada no chao.
---
--- Vale para o carrinho E para a carga derramada, de proposito: as duas ja tiveram
--- testes diferentes, e o resultado foi carga caindo em lugar que o carrinho
--- recusaria. Uma pergunta, uma resposta.
---
--- O `false` de isFree e CARGA UTIL, nao enfeite. Lido no bytecode: com `true` a
--- primeira coisa que a funcao faz e recusar square que tenha personagem em cima --
--- o que incluiria a square do proprio jogador, justamente a que mais usamos. Com
--- `false` esse teste e pulado e sobram os que interessam: solid, solidtrans,
--- arvore, ausencia de solidfloor e escada.
---
--- @param from IsoGridSquare|nil de onde a coisa vem, para o teste de parede
--- @return boolean se pode ficar aqui
local function usable(from, square)
    if square == nil then return false end
    -- isFree(false) e o teste que o jogo base usa para "cabe algo nesta square"
    -- (ver ISWorldObjectContextMenu ao pendurar cortina e ISFarmingMenu ao arar).
    if not square:isFree(false) then return false end
    -- E o teste que faltava: isFree nao sabe de veiculo. isVehicleIntersecting
    -- pergunta se algum veiculo cobre esta square -- era como o carrinho acabava
    -- debaixo de um carro.
    if square:isVehicleIntersecting() then return false end
    -- Nada atravessa parede. Sem isto a carga derramada pulava para dentro do
    -- comodo vizinho.
    if from ~= nil and from ~= square and from:isBlockedTo(square) then
        return false
    end
    return true
end

--- @return IsoGridSquare|nil a primeira square com espaco para `weight`
local function squareWithRoom(origin, weight)
    local cell = getCell()
    if cell == nil then return nil end

    -- Primeira square utilizavel, guardada como reserva caso TODAS estejam acima
    -- do limite de peso. Melhor empilhar demais numa square valida do que devolver
    -- nil e deixar a carga cair onde o carrinho nao pousaria.
    local fallback = nil

    for _, offset in ipairs(OFFSETS) do
        local sq = cell:getGridSquare(
            origin:getX() + offset[1], origin:getY() + offset[2], origin:getZ())
        if usable(origin, sq) then
            if sq:getTotalWeightOfItemsOnFloor() + weight <= SQUARE_WEIGHT_BUDGET then
                return sq
            end
            if fallback == nil then fallback = sq end
        end
    end
    return fallback
end

--- Esvazia o carrinho no chao ao redor de `origin`.
---
--- @param cart InventoryItem o carrinho
--- @param origin IsoGridSquare square de onde a carga cai
--- @return number quantos itens foram derramados
function WB_Spill.dump(cart, origin)
    if cart == nil or origin == nil then return 0 end
    local inv = cart:getInventory()
    if inv == nil then return 0 end

    -- Copia a lista ANTES de mexer: remover de um container enquanto se itera
    -- sobre ele pula elementos, porque os indices deslizam a cada remocao.
    local pending = {}
    local items = inv:getItems()
    for i = 0, items:size() - 1 do
        pending[#pending + 1] = items:get(i)
    end

    -- Uma pergunta so, fora do laco: ela nao muda no meio de um derrame.
    local authority = WB_MP.isAuthority()

    WB_Trace.log("DERRAME", string.format("dump: %d itens, origem=%d,%d,%d",
        #pending, origin:getX(), origin:getY(), origin:getZ()))

    local dropped = 0
    for _, item in ipairs(pending) do
        local weight = item:getUnequippedWeight()
        local target = squareWithRoom(origin, weight) or origin
        inv:Remove(item)
        -- O par obrigatorio do Remove, e so faz algo no servidor. Sem ele o
        -- carrinho continua cheio na tela dos outros jogadores enquanto a carga
        -- ja esta no chao -- e no relog o servidor devolve tudo para dentro dele,
        -- porque e a contabilidade dele que persiste.
        --
        -- Sob autoridade porque a assimetria manda: sendRemoveItemFromContainer
        -- TAMBEM funciona a partir do cliente, e ali seria perda pura -- o
        -- servidor tiraria o item do carrinho e o AddWorldInventoryItem do
        -- cliente nao o poria em lugar nenhum que o servidor visse.
        --
        -- Ele pode nao chegar a ninguem, e ha rede embaixo: GameServer.sendRemove-
        -- ItemFromContainer endereca um container DE ITEM pelo objeto de mundo
        -- dele, entao um carrinho que esteja no inventario do jogador nao tem por
        -- onde ser enderecado e o pacote nao sai. Quem conserta e o
        -- WB_Spill.settle dos dois chamadores deste derrame: o AddItemToMap
        -- serializa o carrinho INTEIRO, conteudo incluido, e ja com o carrinho
        -- vazio.
        if authority then sendRemoveItemFromContainer(inv, item) end
        -- Deslocamento aleatorio dentro da square para a pilha nao virar uma
        -- coluna de itens exatamente sobrepostos.
        --
        -- Quatro argumentos, e nao cinco: nada e ajustado nestes itens depois da
        -- criacao, entao o transmitir automatico do engine serve. O carrinho e o
        -- caso oposto -- ver WB_Spill.settle.
        target:AddWorldInventoryItem(item, ZombRandFloat(0.1, 0.9),
            ZombRandFloat(0.1, 0.9), 0.0)
        dropped = dropped + 1
    end

    -- Registro so em debug. Existe porque "nao caiu nada" tem duas causas
    -- indistinguiveis em tela: a acao nao chegou a ser cancelada, ou foi
    -- cancelada e o carrinho estava vazio. O numero separa as duas.
    if dropped > 0 then
        -- O conteudo saiu do carrinho e foi para o chao: os dois paineis mudaram.
        WB_UI.refreshContainers()
    end

    if getDebug() then
        print(string.format("[Wheelbarrow][SPILL] %d itens derramados", dropped))
    end

    return dropped
end

--- Angulo do carrinho no chao, em graus, a partir de para onde o personagem olha.
---
--- worldZRotation e um float em GRAUS, e o engine o sorteia com Rand.Next(0,360)
--- quando ele chega negativo -- e por isso que item largado no chao aparece
--- torto. Definindo antes de por no mundo, o carrinho fica apontando para onde o
--- jogador estava virado, que e o que se espera de algo que acabou de ser
--- empurrado ate ali.
---
--- A conversao e a mesma que o jogo base usa em FishingRod e no forrageamento:
--- a direcao de frente vem em radianos com zero em outro eixo, dai o + pi/2.
---
--- GROUND_ROTATION_OFFSET alinha o eixo comprido da malha com a frente do
--- personagem. Comecou em zero e o carrinho saiu apontando para tras -- o eixo
--- comprido da malha aponta na direcao oposta a que eu supus. 180 inverte.
local GROUND_ROTATION_OFFSET = 180.0

local function facingDegrees(character)
    local forward = character and character:getForwardDirection()
    if forward == nil then return nil end
    local degrees = math.deg(forward:getDirection() + math.pi / 2)
        + GROUND_ROTATION_OFFSET
    return degrees % 360
end

--- Posicao DENTRO da square de destino, de 0 a 1 em cada eixo.
---
--- O centro (0.5, 0.5) deixava o carrinho longe: a square de destino e a da
--- FRENTE do personagem, entao o centro dela fica a uma tile inteira de
--- distancia. Encostar o carrinho na borda voltada para o personagem corta essa
--- distancia pela metade sem mudar de square -- e mudar de square nao serve,
--- porque na do proprio personagem o carrinho ficaria dentro dele.
---
--- Quando o destino E a square do personagem (a da frente estava bloqueada por
--- parede ou movel), o deslocamento inverte: ali o carrinho precisa ser
--- empurrado para LONGE do centro, senao nasce em cima de quem o largou.
local EDGE_PULL = 0.4

local function placementOffset(character, square)
    local forward = character and character:getForwardDirection()
    local here = character and character:getSquare()
    if forward == nil or here == nil then return 0.5, 0.5 end

    local sameSquare = (here:getX() == square:getX())
        and (here:getY() == square:getY())
    local pull = sameSquare and EDGE_PULL or -EDGE_PULL

    local ox = 0.5 + forward:getX() * pull
    local oy = 0.5 + forward:getY() * pull
    -- O engine espera a posicao dentro da square; sair de [0,1] a poria na
    -- vizinha, o que anularia a escolha de square feita por quem chamou.
    if ox < 0.05 then ox = 0.05 elseif ox > 0.95 then ox = 0.95 end
    if oy < 0.05 then oy = 0.05 elseif oy > 0.95 then oy = 0.95 end
    return ox, oy
end

--- Coloca o carrinho no chao: a UNICA funcao que faz isso.
---
--- POR QUE UMA SO: quando o tombamento ganhou caminho proprio, ele montou a
--- propria colocacao e ESQUECEU de definir a direcao. O carrinho tombado passou
--- a apontar para qualquer lado enquanto o de pe apontava certo -- exatamente o
--- tipo de divergencia que duas copias produzem. Agora as duas passam por aqui e
--- o que difere fica nos parametros.
---
--- Mora em shared/ porque as timed actions tambem precisam dela, e elas rodam no
--- servidor dedicado -- um require de shared/ para client/ seria codigo morto la.
---
--- @param height number deslocamento vertical na square. So pode ser dado na
---        CRIACAO do objeto de mundo; nao ha como ajustar depois.
--- @return boolean se o carrinho foi de fato para o chao
--[[ ESCOLHA DA SQUARE onde o carrinho para.

     O DEFEITO QUE ISTO CONSERTA: recusar a entrada num carro largava o carrinho na
     square do jogador, que ao lado de um veiculo esta DEBAIXO dele. O carrinho
     desaparecia sob a carroceria.

     A square pedida pelo chamador continua sendo a primeira escolha -- ela carrega
     intencao, como "na frente do personagem" ao largar de proposito. Ela so e
     trocada quando nao serve.

     Duas passadas, e a ordem importa: primeiro procuramos uma square livre E SEM
     itens, depois aceitamos qualquer uma livre. Assim o carrinho evita pousar em
     cima de coisa alheia quando ha escolha, e nunca deixa de ser colocado por nao
     achar o lugar ideal -- perder o carrinho seria muito pior que empilha-lo.
]]
local FALLBACK_RADIUS = 1

--- Versao publica de `usable`, para quem coloca carrinho sem ter um personagem --
--- hoje o spawner de mundo. Existe para nao nascer uma segunda ideia de "cabe aqui":
--- a primeira duplicacao desse teste ja deixou carga cair debaixo de carro.
---
--- @return boolean se o carrinho pode ficar nesta square
function WB_Spill.canRest(from, square)
    return usable(from, square)
end

--- @param cart InventoryItem o proprio carrinho, ignorado na conta
--- @return boolean se ja ha OUTRO item largado aqui
---
--- Ignorar o proprio carrinho nao e detalhe: pickSquare roda ANTES de o objeto de
--- mundo antigo ser removido, entao um carrinho que ja esta no chao aparece nesta
--- varredura. Sem a excecao ele se expulsaria da propria square a cada recolocacao
--- -- e recolocar sobre si mesmo e o caso normal ao tombar.
local function hasLooseItems(square, cart)
    local objects = square:getWorldObjects()
    for i = 0, objects:size() - 1 do
        local obj = objects:get(i)
        if instanceof(obj, "IsoWorldInventoryObject") and obj:getItem() ~= cart then
            return true
        end
    end
    return false
end

--- @return table lista de squares candidatas, em ordem de preferencia
local function candidates(character, preferred)
    local list = {}
    -- Nunca insere nil: um furo no meio faria ipairs parar antes do fim, defeito
    -- que este projeto ja teve e que o verificador de Lua vigia.
    if preferred ~= nil then list[#list + 1] = preferred end

    local from = character:getSquare()
    if from == nil then return list end
    if from ~= preferred then list[#list + 1] = from end

    local cell = getCell()
    if cell == nil then return list end

    local x, y, z = from:getX(), from:getY(), from:getZ()
    for dx = -FALLBACK_RADIUS, FALLBACK_RADIUS do
        for dy = -FALLBACK_RADIUS, FALLBACK_RADIUS do
            if dx ~= 0 or dy ~= 0 then
                local square = cell:getGridSquare(x + dx, y + dy, z)
                if square ~= nil and square ~= preferred then
                    list[#list + 1] = square
                end
            end
        end
    end
    return list
end

--- @return IsoGridSquare|nil onde o carrinho deve parar
local function pickSquare(character, cart, preferred)
    local list = candidates(character, preferred)
    local from = character:getSquare()

    for _, square in ipairs(list) do
        if usable(from, square) and not hasLooseItems(square, cart) then
            return square
        end
    end
    for _, square in ipairs(list) do
        if usable(from, square) then return square end
    end

    -- Nenhuma serve: fica onde foi pedido. Um carrinho mal posicionado se resolve
    -- com um E; um carrinho nao colocado some da mao do jogador.
    return preferred or character:getSquare()
end

function WB_Spill.placeOnGround(character, cart, square, height)
    if character == nil or cart == nil then return false end

    -- Uma pergunta so: e o interruptor de tudo o que sai daqui pela rede. Ver o
    -- cabecalho, e ver WB_Equip, que segue a mesma regra.
    local authority = WB_MP.isAuthority()

    -- A square pedida e uma PREFERENCIA. pickSquare a troca se ela estiver ocupada
    -- -- por veiculo, parede ou tralha -- e este e o unico lugar do mod que decide
    -- onde o carrinho para, entao a regra vale para largar, tombar e estacionar.
    WB_Trace.item("MUNDO", "placeOnGround entrada", cart, character)
    square = pickSquare(character, cart, square)
    if square == nil then
        WB_Trace.log("MUNDO", "placeOnGround: nenhuma square serve")
        return false
    end
    WB_Trace.log("MUNDO", string.format("placeOnGround alvo=%d,%d,%d altura=%.2f",
        square:getX(), square:getY(), square:getZ(), height or 0.0))

    -- Ja no chao: remover antes de recriar. Necessario para a altura, que so
    -- entra na criacao, e obrigatorio para nao deixar dois objetos do mesmo item.
    local worldItem = cart:getWorldItem()
    if worldItem ~= nil then
        -- Sob autoridade pelo motivo explicado em WB_Equip: RemoveItemFromSquare-
        -- Packet remove o que estiver no indice enviado, sem conferir tipo nem
        -- identidade, e o objeto de um carrinho estacionado pelo cliente nao existe
        -- na lista do servidor.
        local from = worldItem:getSquare()
        if from ~= nil and authority then
            from:transmitRemoveItemFromSquare(worldItem)
        end
        worldItem:removeFromWorld()
        worldItem:removeFromSquare()
        worldItem:setSquare(nil)
        cart:setWorldItem(nil)
    end

    if character:isPrimaryHandItem(cart) then character:setPrimaryHandItem(nil) end
    if character:isSecondaryHandItem(cart) then character:setSecondaryHandItem(nil) end

    --[[ O CARRINHO ENTRA NO MUNDO ANTES DE SAIR DO CONTAINER, e a ordem e o
         conserto de um defeito observado em jogo.

         A versao anterior tirava do container primeiro. Parecia mais limpo e
         estava errado: no cliente, as duas metades chegam como PACOTES SEPARADOS,
         e entre o RemoveInventoryItemFromContainer e o AddItemToMap existe uma
         janela em que o carrinho nao esta em container NENHUM e nao esta no mundo.

         Nessa janela ele e irresolvivel para a rede, e o engine nao trata isso com
         elegancia -- ele levanta. ContainerID.set, offsets 134-157: sem parent, sem
         worldItem e sem outermost container, o caminho termina em

             throw new IllegalStateException("Unable to resolve container location.")

         que foi exatamente a excecao que apareceu ao mover tronco para o carrinho,
         vinda de ISInventoryTransferAction:perform ao criar a transacao seguinte da
         leva. A transferencia morria ali e a carga ficava no chao.

         Na ordem certa a janela inverte: o carrinho aparece no mundo enquanto
         ainda esta no container. Esse estado E resolvivel -- ContainerID acha o
         outermost container e devolve o inventario do jogador -- entao nada
         levanta. E o mesmo motivo pelo qual ISDropWorldItemAction:complete() poe no
         mundo antes de remover do inventario; eu tinha visto e achado que a ordem
         nao importava.

         Antes de entrar no mundo, so a guinada: depois de AddWorldInventoryItem o
         engine ja resolveu o angulo, e mudar o valor nao reposiciona o que ja foi
         criado. ]]
    local degrees = facingDegrees(character)
    if degrees ~= nil then cart:setWorldZRotation(degrees) end

    --[[ O CONTAINER TEM DE SER LIDO AGORA, e esta linha custou uma noite.

         IsoWorldInventoryObject.<init>, offsets 51-53, faz `item.setContainer(null)`
         -- o construtor LIMPA o ponteiro de container do item. Mas ele nao tira o
         item da LISTA do container: depois de AddWorldInventoryItem o carrinho fica
         com getContainer() nil e o inventario do jogador ainda contendo ele.

         A versao anterior perguntava `cart:getContainer()` depois da colocacao, no
         settle. Vinha nil, o `if container ~= nil` pulava a remocao inteira, e o
         carrinho nunca saia do inventario -- nem localmente nem na rede. Cada
         largada criava mais um objeto de mundo e o carrinho voltava para a mao.
         Foi a duplicacao relatada, e o rastro do servidor mostrou os dois estados
         lado a lado:

             lower antes:         container=none    (o inventario do jogador)
             placeOnGround saida: container=nenhum  (nil, ja limpo)

         ISDropWorldItemAction:complete() escapa disso sem comentar: ele guarda
         `self.character:getInventory()` e remove daquele, em vez de perguntar ao
         item onde ele estava. ]]
    local previousContainer = cart:getContainer()

    local ox, oy = placementOffset(character, square)
    -- CINCO argumentos, e o `false` e carga util: ele desliga o transmitir
    -- automatico do engine para que quem chamou possa terminar de montar a pose
    -- antes de o pacote sair. Ver WB_Spill.settle, que e o par obrigatorio disto.
    square:AddWorldInventoryItem(cart, ox, oy, height or 0.0, false)

    --[[ O tipo tambem aqui, e nao so na varredura de WB_Weight.

         O relogio do servidor passa a cada trinta ticks -- meio segundo. A acao de
         cadaver do jogo base dura CINCO ciclos, cem milissegundos, e o
         estacionamento acontece imediatamente antes dela. Depender do relogio
         deixaria uma corrida que perde cadaver quando perde.

         Aqui e o instante em que o carrinho encosta no chao, que e onde todo
         deposito acontece. ]]
    local inventory = cart:getInventory()
    if inventory ~= nil and inventory:getType() ~= WB_Const.CORPSE_CONTAINER_TYPE then
        inventory:setType(WB_Const.CORPSE_CONTAINER_TYPE)
    end

    character:resetModelNextFrame()
    -- O aviso a interface fica em settle, que sempre vem depois desta funcao: e la
    -- que o carrinho de fato sai do container, e antes disso a barra de
    -- compartimentos ainda estaria certa.
    WB_Trace.item("MUNDO", "placeOnGround saida", cart, character)
    return true, previousContainer
end

--- TERMINA a colocacao: tira o carrinho do container e conta para a rede, nesta
--- ordem. Par obrigatorio de placeOnGround.
---
--- POR QUE NAO ESTA DENTRO DE placeOnGround, duas razoes que se somam:
---
--- 1. O PACOTE LEVA A POSE DO MOMENTO DO ENVIO, e a pose do carrinho tombado so
---    pode ser aplicada DEPOIS de o objeto existir -- o construtor de
---    IsoWorldInventoryObject zera worldXRotation e worldYRotation (ver
---    WB_Tipping). Transmitir dentro da colocacao mandaria um carrinho de pe, e a
---    inclinacao valeria so na maquina de quem tombou.
---
---    As tres rotacoes VIAJAM: IsoWorldInventoryObject.save serializa o
---    InventoryItem contido, e InventoryItem.save escreve as tres (offsets
---    1263-1328) quando alguma nao esta no padrao. O que NAO viaja e
---    setWorldStaticModel, que e estado de runtime -- entao um carrinho tombado
---    aparece para os outros com o modelo de pe, no angulo certo. O de pe e o
---    padrao do script (WorldStaticModel = MNWheelbarrow_Ground), logo o caso
---    normal fica certo.
---
--- 2. A ORDEM DOS PACOTES importa e e a metade que faltava. O AddItemToMap tem de
---    sair ANTES do RemoveInventoryItemFromContainer, senao o cliente passa por um
---    estado em que o carrinho nao esta em lugar nenhum -- e ali qualquer coisa que
---    tente enderecar o compartimento dele levanta IllegalStateException. Ver o
---    comentario longo em placeOnGround.
---
--- No cliente e em single player, transmitCompleteItemToClients nao faz nada: o
--- corpo dele inteiro e `if GameServer.server then ... end`.
---
--- @param cart InventoryItem o carrinho ja colocado no chao, com a pose pronta
--- @param container ItemContainer|nil de onde ele saiu, LIDO ANTES da colocacao.
---        Nao da para descobrir aqui: o construtor do objeto de mundo ja limpou o
---        ponteiro. Ver o comentario em placeOnGround.
function WB_Spill.settle(character, cart, container)
    if cart == nil then return end

    -- PRIMEIRO o mundo. Ver a razao 2 acima.
    local worldItem = cart:getWorldItem()
    if worldItem ~= nil then worldItem:transmitCompleteItemToClients() end
    WB_Trace.log("REDE", "settle: container="
        .. tostring(container ~= nil and (container:getType() or "?") or "nenhum")
        .. " autoridade=" .. tostring(WB_MP.isAuthority()))
    if container ~= nil then container:Remove(cart) end

    --[[ SO A AUTORIDADE AVISA A REDE, e aqui a regra tem dentes.

         sendRemoveItemFromContainer funciona DOS DOIS LADOS -- o corpo dele tem um
         ramo `if GameServer.server` e outro `if GameClient.client`. Chamado do
         cliente, ele diz ao servidor "tirei o carrinho do inventario" sem que
         ninguem o tenha posto no mundo do servidor: o carrinho e simplesmente
         apagado. Trocar duplicacao por PERDA e pior que a duplicacao.

         updateHandEquips vai junto e pelo mesmo motivo. Ele e ciente de lado (no
         servidor manda o Equip para os clientes por perto, no cliente manda ao
         servidor, em single player nao faz nada), mas do cliente ele anunciaria
         maos vazias sem o carrinho ter aparecido no chao para mais ninguem -- e
         entao o carrinho SUMIRIA da tela dos outros. Calado, eles continuam vendo
         o carrinho na mao: desatualizado, e nao inexistente.

         E ele e obrigatorio no servidor: setPrimaryHandItem NAO transmite nada
         sozinho, e nada chama updateHandEquips por quadro -- varri IsoGameCharacter
         inteira e o unico chamador interno e CanAttack. Sem condicao de "as maos
         mudaram": mandar o estado atual das maos e sempre verdade, e uma condicao a
         menos e um caminho a menos para esquecer. ]]
    if WB_MP.isAuthority() then
        if container ~= nil then sendRemoveItemFromContainer(container, cart) end
        if character ~= nil then character:updateHandEquips() end
    end

    -- O compartimento do carrinho tem de sumir da barra de containers agora, e
    -- nao no proximo clique do jogador.
    WB_UI.refreshContainers()
end

--- Ja esta no chao E de pe?
---
--- Pergunta pela ROTACAO do proprio item, e nao a WB_Tipping, de proposito:
--- WB_Tipping precisa deste arquivo para colocar o carrinho no chao, e um
--- require de volta fecharia um ciclo -- em Lua, ciclo de require devolve tabela
--- incompleta, e o sintoma seria um campo nil em runtime, longe da causa.
---
--- A rotacao responde a mesma pergunta de forma mais direta, porque e o estado
--- real e nao uma marca sobre ele.
local function uprightOnGround(cart)
    return cart:getWorldItem() ~= nil
        and math.abs(cart:getWorldXRotation()) < 0.5
        and math.abs(cart:getWorldYRotation()) < 0.5
end

--- Coloca o carrinho no chao DE PE. E o caminho normal.
---
--- Endireita o que estiver tombado: quem quer o carrinho tombado usa
--- WB_Tipping.dropTipped.
function WB_Spill.dropCart(character, cart, square)
    if cart == nil then return false end
    -- Ja no chao e de pe: nada a fazer. Sem esta saida, largar um carrinho que
    -- ja esta la o recriaria a toa.
    if uprightOnGround(cart) then return false end

    local placed, container = WB_Spill.placeOnGround(character, cart, square, 0.0)
    if not placed then return false end

    if cart:hasModData() then cart:getModData()["MNWB_tipped"] = nil end
    cart:setWorldStaticModel("MNWheelbarrow_Ground")
    cart:setWorldXRotation(0.0)
    cart:setWorldYRotation(0.0)
    -- POR ULTIMO, e ela nao e opcional: placeOnGround deixa o carrinho no mundo E
    -- ainda dentro do container de proposito, e e settle que fecha as duas pontas
    -- na ordem certa. Esquecer esta linha deixa o carrinho invisivel para os outros
    -- jogadores e ainda dentro do seu inventario para o servidor.
    WB_Spill.settle(character, cart, container)
    return true
end

return WB_Spill
