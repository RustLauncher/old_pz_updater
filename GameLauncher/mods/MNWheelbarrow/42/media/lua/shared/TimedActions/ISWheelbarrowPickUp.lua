--[[
    Tomar o carrinho nas maos, com animacao -- derramando a carga se cancelar.

    Serve aos DOIS caminhos, e por isso o worldItem e opcional:

        do chao        worldItem preenchido, o objeto sai da square
        do inventario  worldItem nil, so as maos mudam

    Um caminho so, porque a regra e a mesma nos dois: erguer o carrinho leva
    tempo e desistir no meio derruba a carga. Duas classes quase iguais era o
    convite para uma delas esquecer o derrame.

    POR QUE UMA ACAO PROPRIA E NAO O "pegar" do jogo: o pegar padrao e
    instantaneo para item de inventario e nao tem como falhar no meio. O custo de
    interromper e o que da peso a decisao de parar a manobra, e ele so existe se
    a manobra levar tempo.

    A carga sai pelo WB_Spill quando o jogador cancela. Nao e punicao gratuita: o
    carrinho carrega muito mais do que uma pessoa aguenta, e desequilibrar uma
    carga dessas no meio do movimento derruba tudo.

    ANIMACAO: "Loot", a mesma de ISGrabItemAction. Nao e uma das constantes de
    CharacterActionAnims -- setActionAnim aceita o nome cru, e foi assim que o
    jogo base resolveu pegar coisa do chao. A primeira versao usava BuildLow, que
    e martelar agachado, e o Marcos descreveu como "pregar no chao".

    ----------------------------------------------------------------------
    QUAL METODO RODA EM QUE PROCESSO

    Uma acao de Lua e replicada para o servidor dedicado se, e somente se, a
    tabela da classe tiver `complete` -- medido em LuaTimedActionNew.<init>,
    offsets 323-341: `table.getMetatable().rawget("complete")`, e quando da nulo
    o construtor liga useCustomRemoteTimedActionSync, que e o interruptor que
    DESLIGA a replicacao. Declarar complete e o que liga.

    Com ela ligada (start(), offsets 60-101) o cliente chama
    createNetTimedAction e entra em setWaitForFinished(true) -- ou seja, a acao
    dele nao termina mais por conta propria, so quando o servidor responde.

      metodo        single player   cliente MP        servidor dedicado
      new           roda            roda              roda (reconstruido)
      isValid       roda            roda              nao roda
      start         roda            roda              nao roda
      update        roda            roda              nao roda
      perform       roda            roda              nao roda
      complete      roda            NAO RODA          roda
      serverStop    nao roda        nao roda          roda (ao cancelar)

    Quem HOSPEDA cai na coluna de single player: GameClient.client e falso nele,
    entao a acao dele nao e replicada e ele executa tudo localmente -- o que esta
    certo, porque ele tambem e o servidor.

    As duas linhas que decidem o desenho:

      - IsoGameCharacter.updateInternal, offsets 1333-1347: `perform()` sempre,
        e `complete()` so `if not GameClient.client`. Em single player os dois
        rodam, e perform vem PRIMEIRO.
      - NetTimedAction.perform() e o que chama o `complete` de Lua no servidor, e
        ele le o retorno com protectedCallBoolean. Retorno que nao seja booleano
        vira null, o null vira NullPointerException, a excecao e capturada e o
        resultado e FALSE -- ou seja, complete() SEM `return true` e uma acao
        sempre rejeitada.

    Dai a divisao: perform() so cosmetico, complete() com toda a mutacao.

    Fica em shared/ porque o servidor dedicado nao executa lua/client/ (medido em
    GameServer.doMinimumInit: LoadDirBase("client", true), e a flag pula o
    RunLua) -- e sem a classe carregada lah ele nao tem como reconstruir a acao.
]]

require "TimedActions/ISBaseTimedAction"

local WB_Cart = require "WB_Cart"
local WB_Const = require "WB_Const"
local WB_Equip = require "WB_Equip"
local WB_MP = require "WB_MP"
local WB_Rebind = require "WB_Rebind"
local WB_Sandbox = require "WB_Sandbox"
local WB_Spill = require "WB_Spill"
local WB_Tipping = require "WB_Tipping"
local WB_Trace = require "WB_Trace"
local WB_UI = require "WB_UI"

ISWheelbarrowPickUp = ISBaseTimedAction:derive("ISWheelbarrowPickUp")

--- O carrinho da acao, venha ele do argumento ou do objeto de mundo.
---
--- POR QUE ISTO NAO E UM CAMPO: o servidor reconstroi a acao lendo os campos de
--- nome IGUAL aos parametros de new() -- medido em NetTimedAction.set, offsets
--- 58-141: ele pega o Prototype da funcao `new`, percorre locvars[1..numParams-1]
--- e faz rawget de cada nome na instancia. Um campo que seja o argumento
--- TRANSFORMADO viaja transformado e e transformado outra vez do outro lado; o
--- documento oficial da TIS traz exatamente esse defeito como exemplo (um
--- `damage/20` dividido duas vezes).
---
--- Entao `self.item` guarda o argumento cru, e a derivacao mora aqui.
---
--- @return InventoryItem|nil
function ISWheelbarrowPickUp:cart()
    if self.item ~= nil then return self.item end
    if self.worldItem == nil then return nil end
    --[[ O TESTE DE TIPO E OBRIGATORIO, e nao defensividade.

         Um IsoObject atravessa a rede como POSICAO NA LISTA da square -- medido em
         NetObject.setObject/getObject: ele grava (x, y, z, indexOf na
         square:getObjects()) e do outro lado faz getObjects():get(index). Se as
         duas listas divergirem, o servidor resolve OUTRO objeto -- um piso, uma
         parede -- e getItem() num objeto que nao seja IsoWorldInventoryObject
         levanta "No implementation found". ]]
    if not instanceof(self.worldItem, "IsoWorldInventoryObject") then return nil end
    return self.worldItem:getItem()
end

function ISWheelbarrowPickUp:isValid()
    local cart = self:cart()
    if cart == nil then return false end
    if self.worldItem == nil then
        --[[ Vindo do inventario: basta o item continuar sendo do jogador -- E A BUSCA
             PRECISA DESCER POR BOLSAS.

             `contains(item)` de um argumento e `items.contains(item)` numa ArrayList
             plana, conferido no bytecode. Sem o segundo argumento, um carrinho dentro
             de uma mochila fazia isValid() devolver false, e a fila descartava a acao
             EM SILENCIO -- o jogador clicava em "Equipar com as duas maos" e nada
             acontecia, o mesmo sintoma do defeito de 17/08/2026.

             E esse estado o mod produz sozinho: a R4 de WB_Placement poe no chao todo
             carrinho solto num inventario, mas ela nao roda no cliente MP, entao la o
             carrinho pode ficar guardado numa bolsa.

             Nao ha risco em aceitar: WB_Equip.toHands faz
             `if not inv:contains(cart) then inv:AddItem(cart) end`, e ItemContainer.AddItem
             (offsets 77-88) tira o item do container anterior. O carrinho e promovido
             para o topo do inventario antes de ir para a mao, que e o unico lugar de
             onde o pacote de Equip consegue resolve-lo.

             O `true` e recursao, e ele e idioma do jogo base -- ver
             ISInventoryPaneContextMenu.lua:2968. ]]
        return self.character:getInventory():contains(cart, true)
    end
    -- Vindo do chao: o objeto pode ter sumido no meio da acao -- outro jogador
    -- pegou, o chunk descarregou, um zumbi empurrou. getSquare vira nil.
    return self.worldItem:getSquare() ~= nil
end

function ISWheelbarrowPickUp:update()
    if self.worldItem ~= nil then
        self.character:faceThisObject(self.worldItem)
    end
    local cart = self:cart()
    if cart ~= nil then cart:setJobDelta(self:getJobDelta()) end
end

--- Duracao em ciclos de 20 ms.
---
--- POR QUE E UM METODO E NAO O CAMPO maxTime: o servidor chama
--- NetTimedAction.getDuration(), que chama ESTE metodo e depois aplica
--- adjustMaxTime por cima (offsets 48-77, e o resultado vira milissegundos por
--- um `* 20`). O cliente, em ISBaseTimedAction:create(), tambem aplica
--- adjustMaxTime -- sobre maxTime. Se getDuration devolvesse self.maxTime, o
--- valor chegaria ao servidor JA ajustado e seria ajustado duas vezes, e as duas
--- pontas discordariam sobre quando a acao acaba.
---
--- Devolver o valor cru da sandbox faz cada lado ajustar exatamente uma vez.
---
--- O tempo tambem nao pode vir como argumento de new(): o documento oficial
--- chama isso de vetor de trapaca, porque o argumento e escolhido pelo cliente.
function ISWheelbarrowPickUp:getDuration()
    -- O atalho de depuracao do jogo base; 1 e "um ciclo", nao "zero".
    if self.character:isTimedActionInstant() then return 1 end
    return WB_Sandbox.get("ActionDuration")
end

function ISWheelbarrowPickUp:start()
    local cart = self:cart()
    if cart ~= nil then
        cart:setJobType(getText("IGUI_MNWB_PickingUp"))
        cart:setJobDelta(0.0)
    end
    -- "Loot" e a mesma animacao que ISGrabItemAction usa para pegar coisa do
    -- chao. A primeira versao usava BuildLow, que e martelar agachado -- nao ha
    -- prego nenhum em erguer um carrinho.
    self:setActionAnim("Loot")
    self:setOverrideHandModels(nil, nil)
end

function ISWheelbarrowPickUp:stop()
    if getDebug() then
        print("[Wheelbarrow][ACAO] pegar cancelado, do "
            .. (self.worldItem ~= nil and "chao" or "inventario"))
    end
    local cart = self:cart()
    if cart ~= nil then cart:setJobDelta(0.0) end

    --[[ EM MULTIPLAYER O DERRAME E DO SERVIDOR, e sai por serverStop.

         Aqui, no cliente, ele nao pode acontecer: WB_Spill tira os itens do
         carrinho e os poe no chao, e AddWorldInventoryItem so transmite no
         servidor. O resultado seria um carrinho vazio e uma pilha de fantasmas na
         tela de quem cancelou, com o servidor achando que o carrinho continua
         cheio -- e no relog e a contabilidade dele que sobrevive.

         stop() nunca roda no servidor dedicado, entao WB_MP.isAuthority()
         (`not isClient()`) quer dizer aqui "single player, ou o processo que
         hospeda" -- os dois casos em que este processo E o dono do mundo e a acao
         nem chegou a ser replicada. ]]
    if WB_MP.isAuthority() then self:spill() end

    ISBaseTimedAction.stop(self)
end

--- O cancelamento visto pelo SERVIDOR.
---
--- Medido em NetTimedAction.stop, offsets 0-15: o servidor faz rawget
--- "serverStop" na acao reconstruida e chama, se existir. O caminho ate ali e
--- inteiro: o stop() do cliente chama ActionManager.remove(id, true), que envia
--- um GeneralActionPacket com estado Reject; processServer chama
--- ActionManager.stop, que chama ActionManager.remove(id, ...), que no ramo de
--- servidor chama Action.stop() em cada acao daquele id (offset 237-239).
---
--- Isto e o que dispensa um comando cliente->servidor proprio para o derrame: o
--- gancho oficial existe.
---
--- NAO dispara quando o proprio servidor recusa a acao: ali complete() devolveu
--- false, o estado vira Reject e a acao sai da fila pelo filtro de
--- ActionManager.update, que nao chama stop(). Um veto do servidor nao derrama --
--- e correto, porque nada foi mudado para derramar.
function ISWheelbarrowPickUp:serverStop()
    WB_Trace.log("PEGAR", "serverStop -- cancelado pelo cliente")
    self:spill()
end

--- Cancelar derruba TUDO: a carga e o proprio carrinho.
---
--- O carrinho ir junto nao e detalhe. Sem isso, cancelar deixava a carga no chao
--- e o carrinho na mao do jogador -- que e a metade estranha do resultado, e foi
--- o que apareceu no teste. Interromper uma manobra dessas derruba o conjunto.
---
--- E tambem o que sustenta a invariante das duas posicoes: no meio de equipar o
--- carrinho esta no inventario, e abandonar ali seria criar exatamente o estado
--- que WB_Placement existe para impedir.
function ISWheelbarrowPickUp:spill()
    if not WB_Sandbox.get("SpillOnCancel") then return end
    local cart = self:cart()
    if cart == nil then return end

    local square = self.worldItem and self.worldItem:getSquare()
    if square == nil then square = self.character:getSquare() end
    if square == nil then return end

    WB_Spill.dump(cart, square)
    -- dropTipped faz a colocacao inteira, e nao so a inclinacao: a altura do
    -- carrinho tombado so pode ser dada na criacao do objeto de mundo.
    WB_Tipping.dropTipped(self.character, cart, square)
end

--- Raio da limpeza de objetos de mundo obsoletos. Mesmo alcance de todo o resto --
--- ver WB_Const.CART_REACH.
local STRAY_RADIUS = WB_Const.CART_REACH

--[[ APAGA, SO NO CLIENTE MP, OBJETOS DE MUNDO OBSOLETOS DESTE CARRINHO.

     O DEFEITO QUE ISTO CONSERTA, observado em jogo: depois de pegar o carrinho o
     jogador ficava com dois -- um na mao e um no chao, os dois vazios -- e o da
     mao se comportava como fantasma (largar movia o do chao).

     A cascata, medida:

       1. o servidor tira o objeto de mundo da square e manda RemoveItemFromSquare,
          enderecado por (x, y, z, indexOf na square:getObjects()) -- ver
          IsoObject.getObjectIndex. Quando as duas listas nao estao na mesma ordem,
          o cliente apaga outra coisa, ou nada, e o objeto FICA;
       2. em seguida chega o AddInventoryItemToContainer, e ele NAO reaproveita o
          item que ja existe: cria um InventoryItem novo a partir do pacote e o poe
          no inventario (processClient, offsets 156-162);
       3. o cliente passa a ter DOIS objetos com o mesmo id -- o velho, preso ao
          objeto de mundo, e o novo, no inventario -- e as maos apontam para um
          enquanto o inventario guarda o outro.

     POR QUE AQUI E NAO NUM HANDLER POR QUADRO: por quadro nao da para distinguir
     "o servidor acabou de me entregar o carrinho" de "o servidor acabou de tira-lo
     de mim". Os dois passam pelo estado carrinho-na-mao-e-no-mundo, e agir no
     momento errado apagaria o carrinho recem-largado. Aqui nao ha ambiguidade:
     perform() so roda depois de o servidor responder Done, entao a essa altura
     QUALQUER objeto de mundo com este id e resto.

     SO NO CLIENTE MP, e a guarda nao e precaucao: em single player perform() roda
     ANTES de complete(), quando o carrinho legitimamente ainda esta no chao. Sem a
     guarda, esta funcao apagaria o carrinho que a acao ia pegar.

     Nenhuma chamada de rede, de proposito: o servidor ja fez a parte dele. Isto e
     o cliente se corrigindo, e um transmitRemoveItemFromSquare daqui apagaria, no
     servidor, o que estivesse no indice divergente -- que e a causa do defeito, nao
     o conserto. ]]
function ISWheelbarrowPickUp:forgetStrayWorldObjects()
    if WB_MP.isAuthority() then return end
    WB_Trace.survey("PEGAR", "limpeza antes", self.character, STRAY_RADIUS)

    local cart = self:cart()
    if cart == nil then return end
    local id = cart:getID()

    local stray = {}
    WB_Cart.forEachOnGround(self.character, STRAY_RADIUS, function(item, obj, _sq)
        if item:getID() == id then stray[#stray + 1] = obj end
    end)

    for _, obj in ipairs(stray) do
        local square = obj:getSquare()
        if square ~= nil then square:RemoveTileObject(obj) end
        obj:removeFromWorld()
        obj:removeFromSquare()
        obj:setSquare(nil)
        local item = obj:getItem()
        if item ~= nil then item:setWorldItem(nil) end
        if getDebug() then
            print("[Wheelbarrow][ACAO] objeto de mundo obsoleto apagado")
        end
    end
end

--- So cosmetico. Roda no cliente e em single player, e em single player roda
--- ANTES de complete() -- entao nada aqui pode depender da mutacao.
function ISWheelbarrowPickUp:perform()
    local cart = self:cart()
    if cart ~= nil then cart:setJobDelta(0.0) end

    self:forgetStrayWorldObjects()
    -- O espelho do que o largar faz: voltar para as maos tambem troca o objeto,
    -- e o que a fila guardava do carrinho no chao envelheceu agora.
    local cartId = cart ~= nil and cart:getID() or nil
    WB_Rebind.queuedActions(self.character, cartId)

    -- Em multiplayer complete() nao roda aqui, e e ele que costuma pedir o
    -- redesenho da barra de containers. Este e o unico ponto do cliente que sabe
    -- que a acao acabou, e o idioma e o do jogo base -- ISDropWorldItemAction
    -- marca ISInventoryPage.renderDirty no perform pelo mesmo motivo.
    WB_UI.refreshContainers()
    self.character:resetModelNextFrame()

    ISBaseTimedAction.perform(self)
end

--- Toda a mutacao. Roda no SERVIDOR e em single player, nunca no cliente MP.
---
--- O retorno e o VETO: false faz a transacao virar Reject e o cliente desfazer a
--- acao. E ele tem de ser booleano de verdade -- ver o cabecalho.
---
--- POR QUE ISTO MATA A "REFERENCIA ORFA" da primeira passagem: o servidor roda
--- isto sobre os objetos DELE, resolvidos a partir do que veio no argumento. O
--- cliente nunca segura uma referencia atravessando a rede, e dentro daqui
--- AddWorldInventoryItem, sendAddItemToContainer e updateHandEquips funcionam,
--- porque ali GameServer.server e verdadeiro.
function ISWheelbarrowPickUp:complete()
    local cart = self:cart()
    WB_Trace.item("PEGAR", "complete", cart, self.character)
    WB_Trace.survey("PEGAR", "complete", self.character, 2)
    -- WB_Cart.is e nao "diferente de nil": e a checagem que pega o objeto errado
    -- resolvido por indice divergente -- ver o comentario de cart().
    if not WB_Cart.is(cart) then return false end

    if self.worldItem ~= nil then
        -- Outro jogador pode ter pegado o carrinho durante a animacao. Sem estes
        -- dois testes o servidor o adicionaria ao inventario dos DOIS -- que e
        -- duplicacao real de item, e nao a duplicacao visual do porte anterior.
        if self.worldItem:getSquare() == nil then return false end

        --[[ "AINDA SOLTO NO CHAO" SE MEDE PELO OBJETO DE MUNDO, NAO PELO CONTAINER.

             A versao anterior era `if cart:getContainer() ~= nil then return false`,
             e ela recusava o caso NORMAL. Relatado por tres jogadores em 17/08/2026
             como "aperto E, a animacao roda e nada acontece" -- e a recusa e muda,
             porque devolver false aqui e so o veto do servidor.

             MEDIDO, a cadeia inteira:

               1. ISInventoryPage.lua:1697 faz floorContainer:AddItem(o:getItem())
                  para TODO item de mundo perto do jogador -- o container "floor" da
                  interface, criado na linha 1531;
               2. ItemContainer.AddItem, offset 93, faz
                  `putfield InventoryItem.container`.

             Ou seja: um carrinho largado no chao que a interface ja enumerou TEM
             container. O teste antigo lia isso como "alguem guardou o carrinho".

             E POR QUE OS TESTES NAO PEGARAM, que e a parte que importa: complete()
             roda no SERVIDOR DEDICADO, e lah nao existe ISInventoryPage -- client/
             nunca executa no servidor (secao 2 do HANDOFF). Do lado dedicado
             getContainer() e nil e o teste passa sempre. Ele so falha onde quem
             executa complete() TEM interface: single player e servidor hospedado.
             Todo o porte foi validado contra servidor dedicado.

             O objeto de mundo e o sinal certo e nao depende de interface: o container
             "floor" nao o limpa -- o proprio jogo base conta com isso em
             ISInventoryPage.lua:2059, `container:getType() == "floor" and
             item:getWorldItem()`.

             A intencao original -- impedir que dois jogadores peguem o mesmo
             carrinho, que seria duplicacao real -- continua coberta, e pelo teste da
             linha acima: quem pegou primeiro tira o objeto de mundo da square, e o
             getSquare() do segundo vira nil. ]]
        if cart:getWorldItem() == nil then return false end
    elseif not self.character:getInventory():contains(cart, true) then
        -- Veio do inventario e saiu de lah no meio do caminho. O `true` e recursao,
        -- pelo mesmo motivo detalhado em isValid(): sem ele um carrinho dentro de uma
        -- bolsa e lido como "saiu do inventario" e a acao e vetada em silencio.
        return false
    end

    -- Toda a sequencia de equipar vive em WB_Equip, porque o estacionamento
    -- durante acoes precisa exatamente dela. Duas copias de um trecho que
    -- depende de ordem -- e este depende, ver o comentario de setWorldItem la --
    -- e o convite para uma delas perder um passo.
    local ok = WB_Equip.toHands(self.character, cart, self.worldItem)
    WB_Trace.item("PEGAR", "complete depois", cart, self.character)
    WB_Trace.survey("PEGAR", "complete depois", self.character, 2)
    return ok
end

--- @param worldItem IsoWorldInventoryObject|nil nil quando vem do inventario
--- @param item InventoryItem|nil nil quando vem do chao
---
--- CADA ARGUMENTO VIRA UM CAMPO DE MESMO NOME E VALOR CRU. E o contrato de
--- reconstrucao do servidor (ver ISWheelbarrowPickUp:cart), e mexer nos nomes
--- daqui muda o formato de rede da acao.
---
--- Os dois ultimos sao exclusivos por construcao, e cada um atravessa por um
--- mecanismo diferente:
---
---   worldItem  IsoObject, enderecado por square + indice na lista de objetos;
---   item       InventoryItem, enderecado por container + id.
---
--- E por isso que o caminho do CHAO tem de mandar o worldItem: um carrinho
--- largado nao tem container, e ContainerID.set(nil) grava o tipo Undefined --
--- do outro lado loadInventoryItem devolve nulo. Um carrinho no INVENTARIO, ao
--- contrario, vira (PlayerInventory, playerId, itemId) e resolve certo.
function ISWheelbarrowPickUp:new(character, worldItem, item)
    local o = ISBaseTimedAction.new(self, character)
    o.worldItem = worldItem
    o.item = item
    o.stopOnWalk = true
    o.stopOnRun = true
    o.maxTime = o:getDuration()
    return o
end

return ISWheelbarrowPickUp
