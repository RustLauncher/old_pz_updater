--[[
    Capacidade do carrinho e alivio de peso so para carga pesada.

    ======================================================================
    O TETO DE 50 EXISTE, E E IMPOSTO NA LEITURA.
    ======================================================================

    Este cabecalho afirmava o contrario, e a afirmacao estava errada -- errada o
    bastante para ter derrubado a primeira tentativa de porte para multiplayer.
    O erro foi ler so o ESCRITOR:

        ItemContainer.setCapacity(int)   -- tres comparacoes (1000 peca de
                                        -- veiculo, 50 container de item, 100 o
                                        -- resto) que so escolhem QUAL aviso de
                                        -- debug imprimir; o putfield acontece
                                        -- sempre

    De onde saiu "o valor e sempre gravado", que e verdade. Mas quem corta e o
    LEITOR, e ninguem tinha olhado para ele:

        ItemContainer.getCapacity(), offsets 31-54:
            if containingItem instanceof InventoryItem -> return min(cap, 50)

    setCapacity(200) grava 200 e getCapacity() devolve 50. Nao ha tipo, tag ou
    campo que mude isso; o unico discriminante e o container pertencer a um item.

    Consequencia: a sandbox option Capacity nao faz nada acima de 50 -- e, com o
    orcamento de chao de applyCapacity, nada acima de 38 --, e o que permite carga
    pesada e o REACONDICIONAMENTO de peso (ver WB_Repack), nao a capacidade. E a
    guarda de "so escreve quando muda" tem de comparar contra o que o engine
    DEVOLVE, nunca contra o que queriamos escrever -- ver applyCapacity abaixo.

    ONDE A CARGA E FEITA, e por que nao e uma escolha nossa: em
    ItemContainer.hasRoomFor, um container EQUIPADO exige que o item tambem
    caiba no inventario do JOGADOR --

        inventarioDoJogador.getCapacityWeight() + item.getUnequippedWeight()
            <= inventarioDoJogador.getEffectiveCapacity(jogador)

    Uma geladeira nunca passa nesse teste. Com o carrinho no CHAO o engine usa
    outro ramo, que compara so contra a capacidade do proprio carrinho. Ou seja
    o jogo ja obriga o fluxo realista: pousar o carrinho para carregar. Nao ha
    nada a implementar para isso, so a nao atrapalhar.

    ----------------------------------------------------------------------
    ALIVIO DE PESO

    O engine oferece UMA alavanca: uma porcentagem unica sobre o peso total.

        pesoEfetivo = pesoTotal * (1 - weightReduction / 100)

    Como a regra do mod e "alivia so o que e pesado", resolvemos a cada mudanca
    a porcentagem equivalente:

        efetivo = leve + pesado * (1 - reducao)
        pct     = 100 * (1 - efetivo / total)

    So leve    -> pct 0        carrinho inutil, exatamente o desenho pedido
    So pesado  -> pct = reducao
    Misturado  -> proporcional, matematicamente exato

    E por isso que encher o carrinho de livros nao compensa: livro nao e
    reacondicionado nem aliviado, entao os 38 de capacidade sao 38 de livro que
    continuam pesando 38 nas costas -- e o teto de carga leve corta antes disso.

    ----------------------------------------------------------------------
    POR QUE shared/ E NAO server/: OnEquipPrimary e OnEquipSecondary sao eventos
    de cliente. Num servidor DEDICADO, server/ roda em outro processo e eles
    nunca disparam la -- o codigo seria morto. O calculo e deterministico a
    partir do conteudo, que o jogo ja sincroniza, entao cada lado deriva o
    proprio estado.
]]

local WB_Cart = require "WB_Cart"
local WB_Const = require "WB_Const"
local WB_Legacy = require "WB_Legacy"
local WB_MP = require "WB_MP"
local WB_Repack = require "WB_Repack"
local WB_Sandbox = require "WB_Sandbox"
local WB_Tipping = require "WB_Tipping"

local WB_Weight = {}

--- Raio da varredura de chao, em squares.
local GROUND_RADIUS = 2

--- Intervalo minimo entre varreduras de chao, em milissegundos.
---
--- A varredura olha (2*2+1)^2 = 25 squares e todo IsoObject de cada uma. Antes
--- disto ela rodava em OnContainerUpdate E em
--- OnRefreshInventoryWindowContainers, que disparam varias vezes por segundo
--- enquanto a janela de loot esta aberta -- exatamente quando o jogador esta
--- mexendo no carrinho. O estrangulamento nao muda o resultado, so evita repetir
--- a mesma varredura dezenas de vezes por segundo.
local GROUND_SCAN_INTERVAL_MS = 250

--[[ Instante da ultima varredura, POR JOGADOR.

     TABELA E NAO NUMERO, e a diferenca e um defeito de tela dividida:
     refreshLocalPlayers percorre todos os jogadores locais no MESMO quadro. Com um
     relogio unico, o primeiro da volta marcava o instante e o segundo saia
     estrangulado -- toda vez, porque os dois sempre caem no mesmo quadro. Os carrinhos
     perto do jogador 2 nunca eram reacondicionados nem tinham o tombo restaurado.

     Chave igual a de WB_Parking e WB_Player: nome de usuario em multiplayer, indice do
     jogador fora dele. ]]
local lastGroundScan = {}

--- Recalcula reducao de peso e capacidade de UM carrinho.
--- @return boolean se algum valor mudou de fato
function WB_Weight.refresh(item)
    if not WB_Cart.is(item) then return false end

    local inv = item:getInventory()
    if inv == nil then return false end

    local threshold = WB_Sandbox.get("HeavyThreshold")
    local reduction = WB_Sandbox.get("HeavyReduction") / 100.0

    --[[ PESO REAL, e nao o que o item pesa agora.

         O carrinho reacondiciona a carga: um tronco de 9 pesa 1.8 dentro dele, para
         caber no teto de 50 que o engine impoe (ver WB_Repack). Classificar por
         getActualWeight faria esse tronco cair como carga LEVE, abaixo do limite de
         8, e perder a reducao -- ou seja, o mecanismo que faz caber destruiria o
         mecanismo que faz ficar leve.

         A conta de reducao tambem usa o peso real, senao ela aliviaria 95% de um
         numero que ja veio comprimido e o resultado nao seria o prometido. ]]
    local heavy, light = 0.0, 0.0
    local contents = inv:getItems()
    for i = 0, contents:size() - 1 do
        local w = WB_Repack.realWeight(contents:get(i))
        if w >= threshold then
            heavy = heavy + w
        else
            light = light + w
        end
    end

    local total = heavy + light
    local pct = 0
    if total > 0 then
        local effective = light + heavy * (1.0 - reduction)
        pct = math.floor(100.0 * (1.0 - effective / total) + 0.5)
        if pct < 0 then pct = 0 elseif pct > 100 then pct = 100 end
    end

    -- Escrever so quando muda importa: cada setCapacity acima de 50 imprime um
    -- aviso de debug no console, e escrever a cada evento inundaria o log.
    local changed = false
    if item:getWeightReduction() ~= pct then
        item:setWeightReduction(pct)
        inv:setWeightReduction(pct)
        changed = true
    end

    if WB_Weight.applyCapacity(item, inv) then changed = true end

    --[[ O TIPO DO COMPARTIMENTO, e ele mora nesta varredura por um motivo.

         Ver WB_Const.CORPSE_CONTAINER_TYPE para o que ele faz. O que importa aqui e
         ONDE: refresh e a unica funcao do mod chamada para todo carrinho nos DOIS
         processos -- por eventos no cliente, pelo relogio no servidor. Escrever o
         tipo so no cliente foi exatamente o defeito do cadaver.

         Fora da contagem de `changed`: o tipo nao e peso nem capacidade, e marcar
         mudanca por causa dele faria a guarda de "so escreve quando muda" perder o
         sentido. setType e barato e idempotente. ]]
    if inv:getType() ~= WB_Const.CORPSE_CONTAINER_TYPE then
        inv:setType(WB_Const.CORPSE_CONTAINER_TYPE)
    end

    return changed
end

--- O que getCapacity() DEVOLVE depois de escrever cada valor desejado.
---
--- Chaveado pelo valor desejado para a memoria continuar valida se a sandbox
--- mudar no meio da sessao.
local capacityReadBack = {}

--[[ O TETO QUE MANDA NAO E O DO COMPARTIMENTO, E O DO CHAO.

     Medido em jogo, com o carrinho no chao -- que e onde todo carregamento
     acontece, porque o estacionamento poe ele la:

         itens  conteudo  chao   + tronco   veredito
            21      37.8  40.8      49.8    aceita
            22      39.6  42.6      51.6    RECUSA

     A regra esta em ItemContainer.hasRoomFor(IsoGameCharacter,F,F), offsets
     127-145: quando o container tem objeto de mundo, o engine soma
     getTotalWeightOfItemsOnFloor() da square e recusa acima de 50.0. E
     getTotalWeightOfItemsOnFloor le getUnequippedWeight, que para um container e
     `peso proprio + conteudo INTEIRO` -- a reducao de peso nao entra ali.

     Ou seja: com o carrinho no chao, o limite real e

         peso do carrinho vazio + conteudo + item que entra  <=  50

     O compartimento tem 50 de capacidade e NUNCA chegava a morder: o chao mordia
     antes, sempre. O jogador via 32.4 de 50 e o jogo recusava -- numero mentindo
     para ele, que foi exatamente a queixa.

     E NAO HA CASO ALTERNATIVO A PONDERAR. Como TODA acao estaciona o carrinho --
     ver WB_Parking --, ele esta sempre no chao na hora da transferencia. O caminho
     "carrinho na mao", onde valeria a regra do inventario em vez desta, nao existe
     mais na pratica. Existe um muro so, e cortar a capacidade nele nao e
     meio-termo: e a unica regra.

     O item de referencia e o TRONCO, 9.0 -- o mais pesado que se carrega em
     quantidade. Carga mais pesada que isso ainda encontra o chao antes da
     capacidade, e nao ha numero unico que cubra os dois; o caso comum e o que
     serve. ]]
local FLOOR_BUDGET = 50.0
local REFERENCE_ITEM_WEIGHT = 9.0

--- Peso do carrinho vazio quando o script nao pode ser consultado.
---
--- Espelha `Weight = 3.0` de items_wheelbarrow.txt, e existir como numero aqui ja
--- foi a fonte de verdade dupla que este projeto passa a vida perseguindo: mudar o
--- peso do item no script deixaria este teto errado sem nada reclamar. Hoje o
--- valor vem do PROPRIO item; a constante e so o ultimo recurso.
local CART_OWN_WEIGHT = 3.0

--- @return number capacidade que cabe no orcamento de chao
local function floorCeiling(item)
    local own = CART_OWN_WEIGHT
    local script = item ~= nil and item:getScriptItem() or nil
    if script ~= nil then
        local weight = script:getActualWeight()
        if weight ~= nil and weight > 0 then own = weight end
    end
    return math.floor(FLOOR_BUDGET - own - REFERENCE_ITEM_WEIGHT)
end

--- Escreve a capacidade, e so quando ela nao esta valendo.
---
--- A GUARDA COMPARA CONTRA A LEITURA, E ISSO E O PONTO DESTA FUNCAO.
---
--- A versao anterior fazia `if inv:getCapacity() ~= capacity then set(capacity)`,
--- comparando a leitura CORTADA (50) com a escrita DESEJADA (200). Os dois nunca
--- sao iguais, entao ela reescrevia em toda varredura -- medido: duas vezes por
--- segundo por jogador, tres avisos de debug cada, centenas de linhas de log em
--- segundos.
---
--- Aqui o teto e MEDIDO e nao assumido: escrevemos uma vez, lemos de volta, e
--- guardamos o que voltou. A partir dai a comparacao e contra a verdade do
--- engine. Se um dia o corte mudar de 50 para outro numero, isto continua certo
--- sozinho.
---
--- @return boolean se algo foi escrito
function WB_Weight.applyCapacity(item, inv)
    local desired = math.floor(WB_Sandbox.get("Capacity"))
    if desired <= 0 then return false end

    -- A sandbox option continua mandando para BAIXO: quem quiser um carrinho menor
    -- tem o ajuste. Para cima ela nao pode ir alem do que o chao aceita, senao a
    -- barra volta a mentir.
    local ceiling = floorCeiling(item)
    if desired > ceiling then desired = ceiling end

    local expected = capacityReadBack[desired]
    if expected ~= nil and inv:getCapacity() == expected then return false end

    item:setCapacity(desired)
    inv:setCapacity(desired)
    capacityReadBack[desired] = inv:getCapacity()
    return true
end

--- Carrinhos no inventario do jogador.
---
--- NAO pede reconstrucao do modelo aqui, e a ausencia e deliberada. Uma versao
--- anterior chamava resetModelNextFrame sempre que o peso mudava com o carrinho
--- na mao, como tentativa de conserto para o personagem sumir. Aquele sintoma
--- tinha outra causa -- ver WB_Player, que trata o problema onde ele de fato
--- esta -- e reconstruir o modelo a cada mudanca de conteudo era custo por
--- evento sem beneficio comprovado.
function WB_Weight.refreshPlayer(player)
    if player == nil then return end
    WB_Cart.forEachIn(player:getInventory(), WB_Weight.refresh)
end

--- Carrinhos largados no chao ao redor do jogador, no maximo a cada
--- GROUND_SCAN_INTERVAL_MS.
--- @param force boolean ignora o estrangulamento (uso: carregar o save)
function WB_Weight.refreshNearbyGround(player, force)
    local now = getTimestampMs()
    local key = WB_MP.playerKey(player)
    local last = lastGroundScan[key]
    if not force and last ~= nil and now - last < GROUND_SCAN_INTERVAL_MS then return end
    lastGroundScan[key] = now

    -- Dentro do trecho estrangulado de proposito: reacondicionar carrinho no chao
    -- exige varrer squares, e isso nao pode acontecer a cada mudanca de container.
    WB_Repack.sweepGround(player, GROUND_RADIUS)

    WB_Cart.forEachOnGround(player, GROUND_RADIUS, function(cart)
        WB_Weight.refresh(cart)
        -- Recarregar o save recria o objeto de mundo, e o construtor zera as
        -- rotacoes de inclinacao -- sem isto um carrinho tombado se levantaria
        -- sozinho ao voltar ao jogo. A marca de tombado vive no ModData, que
        -- persiste; aqui ela vira rotacao de novo.
        WB_Tipping.restore(cart)
    end)
end

local function refreshLocalPlayers(force)
    for i = 0, getNumActivePlayers() - 1 do
        local player = getSpecificPlayer(i)
        if player ~= nil then
            --[[ A reconciliacao vem ANTES do calculo de peso, e a ordem importa.

                 WB_Repack.sweep decide quem esta reacondicionado; WB_Weight.refresh
                 le esses pesos para calcular a reducao. Na ordem inversa, a reducao
                 seria calculada sobre um estado que a varredura ainda ia mudar, e o
                 painel mostraria o valor de um quadro atras a cada transferencia. ]]
            WB_Repack.sweepCarried(player)

            WB_Weight.refreshPlayer(player)
            WB_Weight.refreshNearbyGround(player, force)
        end
    end
end

--- Uma vez por carregamento: restaura itens que a tecnica abandonada de
--- encolher peso deixou alterados. Ver WB_Legacy.lua.
---
--- So no load, e nao em toda atualizacao de container como antes: era uma
--- varredura recursiva da arvore inteira do inventario, para sempre, por causa
--- de uma migracao de um mod que nunca chegou a ser publicado.
local function migrateOnce(player)
    if player == nil then return end
    WB_Legacy.sweep(player:getInventory())
end

Events.OnEquipPrimary.Add(function(player, _item) WB_Weight.refreshPlayer(player) end)
Events.OnEquipSecondary.Add(function(player, _item) WB_Weight.refreshPlayer(player) end)

-- Conteudo mudou. Os argumentos sao ignorados de proposito: a varredura do
-- inventario e barata e nao depende da assinatura exata do evento.
Events.OnContainerUpdate.Add(function() refreshLocalPlayers(false) end)

-- OnContainerUpdate nem sempre dispara para container que esta no chao. A
-- janela de loot reconstruindo e o sinal mais confiavel de que o jogador esta
-- mexendo num carrinho largado.
Events.OnRefreshInventoryWindowContainers.Add(function() refreshLocalPlayers(false) end)

-- setWeightReduction e setCapacity sao estado de RUNTIME: ao recarregar um save
-- os valores do script voltam. Sem estes dois, um carrinho salvo cheio
-- reapareceria com a capacidade do script e o conteudo nao caberia.
--
-- OnCreatePlayer entrega o INDICE do jogador, nao o objeto -- confirmado em
-- ISSearchManager.createUI, que faz getSpecificPlayer(_player). O segundo
-- parametro e aceito caso a assinatura mude.
Events.OnCreatePlayer.Add(function(playerIndex, player)
    local obj = player or getSpecificPlayer(playerIndex)
    migrateOnce(obj)
    WB_Weight.refreshPlayer(obj)
    WB_Weight.refreshNearbyGround(obj, true)
end)

Events.OnGameStart.Add(function()
    migrateOnce(getSpecificPlayer(0))
    refreshLocalPlayers(true)
end)

return WB_Weight
