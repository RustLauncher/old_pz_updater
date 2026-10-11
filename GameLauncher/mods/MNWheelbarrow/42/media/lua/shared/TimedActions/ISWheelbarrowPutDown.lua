--[[
    Largar o carrinho no chao, com animacao.

    O CARRINHO DESCE NO INICIO DA ACAO, NAO NO FIM. Essa e a diferenca em relacao
    a primeira versao, e ela conserta um artefato que o Marcos apontou: o
    carrinho SUMIA durante a animacao e reaparecia no chao no final.

    A causa e a mascara: o carrinho na mao e desenhado pela mascara de animacao
    mnwb_holdingcart, e uma acao cronometrada substitui a animacao do personagem
    enquanto roda. Sem a mascara, o modelo nao e desenhado -- o carrinho nao
    "some", ele nunca esteve na mao como objeto do mundo.

    Nao ha como manter o modelo de mao visivel durante a acao. Mas ha como o
    carrinho ficar visivel: pondo ele no CHAO logo no inicio. O personagem se
    abaixa ao lado de um carrinho que ja esta la, que e o que acontece na vida
    real e o que casa com a regra de o carrinho nunca ir para o inventario.

    Consequencia boa: cancelar deixa de ser caso especial. O carrinho ja esta no
    chao de qualquer jeito; cancelar so acrescenta o derrame da carga.

    ANIMACAO: "Loot", a mesma que ISGrabItemAction usa para pegar coisa do chao.
    A primeira versao usava BuildLow, que e martelar agachado -- o Marcos
    descreveu como "pregar no chao", e ele estava certo: nao ha prego nenhum
    nisto.

    ----------------------------------------------------------------------
    O "DESCE NO INICIO" TEM TRES DONOS, UM POR PROCESSO

    A divisao geral esta no cabecalho de ISWheelbarrowPickUp; o que e proprio
    desta acao e QUEM baixa o carrinho, porque isso nao acontece no fim:

      single player      start(), sob a guarda de autoridade
      quem hospeda       start(), pelo mesmo caminho -- a acao dele nao e
                         replicada, porque LuaTimedActionNew.start so cria a
                         transacao quando GameClient.client e verdadeiro
      servidor dedicado  serverStart(), o gancho oficial de inicio do servidor
      cliente MP         ninguem -- o carrinho desce quando os pacotes do
                         servidor chegam, que e o que se quer ver na tela

    serverStart existe justamente para isto. Medido em NetTimedAction.start,
    offsets 4-15: o servidor faz rawget "serverStart" na acao reconstruida e
    chama, se existir, antes de a acao entrar na fila dele. O `start` de Lua NAO
    roda no servidor dedicado -- lah nao existe LuaTimedActionNew.

    Sobra para complete() o papel de VETO e de rede de seguranca: ele confere que
    o carrinho realmente chegou ao chao, e tenta de novo se nao chegou.
]]

require "TimedActions/ISBaseTimedAction"

local WB_Cart = require "WB_Cart"
local WB_Rebind = require "WB_Rebind"
local WB_MP = require "WB_MP"
local WB_Sandbox = require "WB_Sandbox"
local WB_Spill = require "WB_Spill"
local WB_Tipping = require "WB_Tipping"
local WB_Trace = require "WB_Trace"
local WB_Transfer = require "WB_Transfer"
local WB_UI = require "WB_UI"

ISWheelbarrowPutDown = ISBaseTimedAction:derive("ISWheelbarrowPutDown")

--- Square a frente do personagem, se der para pousar algo la.
---
--- getAdjacentSquare(dir) e o caminho do jogo -- e o que CFarming_Interact usa
--- com player:getDir(). A alternativa, somar dir:dx() e dir:dy() na mao, aparece
--- num unico arquivo do jogo inteiro; nao vale depender dela.
local function squareInFront(character)
    local here = character:getSquare()
    if here == nil then return nil end

    local dir = character:getDir()
    if dir == nil then return here end

    local target = here:getAdjacentSquare(dir)

    -- isBlockedTo cobre parede, janela fechada e movel no caminho. Sem ele o
    -- carrinho atravessaria a parede para a sala vizinha.
    if target == nil or target:isSolid() or target:isSolidTrans()
        or target:isBlockedTo(here) then
        return here
    end
    return target
end

function ISWheelbarrowPutDown:isValid()
    -- Vale enquanto o item existir. NAO da para exigir que ele esteja no
    -- inventario: a acao comeca justamente tirando ele de la.
    return self.item ~= nil
end

function ISWheelbarrowPutDown:update()
    self.item:setJobDelta(self:getJobDelta())
end

--- Duracao em ciclos de 20 ms. Ver a explicacao longa em
--- ISWheelbarrowPickUp:getDuration -- em resumo, devolver self.maxTime faria o
--- ajuste de moodles e dor ser aplicado duas vezes no servidor.
function ISWheelbarrowPutDown:getDuration()
    if self.character:isTimedActionInstant() then return 1 end
    return WB_Sandbox.get("ActionDuration")
end

--- Poe o carrinho no chao. A UNICA mutacao desta acao.
---
--- WB_Transfer suspende a rede de WB_Placement e a checagem de fantasma de
--- WB_Player enquanto o carrinho legitimamente aparece em dois lugares. As duas
--- so existem no cliente e em single player, mas a marcacao vive aqui porque este
--- e o unico lugar que sabe quando a transicao comeca e acaba.
---
--- @return boolean se o carrinho terminou no chao -- a pos-condicao, e nao "eu
---         tentei". E o que complete() usa como veto, e o que faz esta funcao
---         poder ser chamada duas vezes sem estragar nada: WB_Spill.dropCart sai
---         cedo quando o carrinho ja esta la e de pe.
function ISWheelbarrowPutDown:lower()
    -- No servidor o carrinho vem resolvido por (inventario do jogador, id do item),
    -- e resolucao pode falhar -- loadInventoryItem devolve nulo quando o inventario
    -- daquele lado nao tem aquele id. Sem esta saida a falha viraria um erro de Lua
    -- dentro do protectedCall de serverStart, que so escreve um aviso e segue; com
    -- ela, complete() rejeita a acao e o cliente desfaz.
    if self.item == nil then return false end

    WB_Trace.item("LARGAR", "lower antes", self.item, self.character)
    WB_Trace.survey("LARGAR", "lower antes", self.character, 2)

    --[[ A SQUARE ESCOLHIDA GANHA DA SQUARE DA FRENTE, quando existe uma.

         O cursor de posicionamento do jogo base -- "colocar item no chao", que deixa
         o jogador escolher o lugar -- enfileira ISDropWorldItemAction com a square
         alvo. WB_Placement desvia essa acao para esta, e a square vem junto: sem
         isso, desviar custaria ao jogador a unica maneira de escolher ONDE o carrinho
         fica, so para ganhar a mecanica de derramar.

         DEGRADA SOZINHO, e e o que torna isto seguro em multiplayer: a square e um
         argumento de rede como qualquer outro, e se a reconstrucao do servidor nao a
         resolver, self.square chega nil e o carrinho desce na frente do personagem --
         o comportamento de sempre. O pior caso e perder a precisao, nunca a acao. ]]
    local target = self.square
    if target ~= nil and not instanceof(target, "IsoGridSquare") then target = nil end

    WB_Transfer.begin()
    -- WB_Spill cuida de tirar das maos, remover do inventario, avisar a rede e
    -- apontar o carrinho para onde o personagem esta virado.
    WB_Spill.dropCart(self.character, self.item,
        target or squareInFront(self.character))
    WB_Transfer.finish()

    WB_Trace.item("LARGAR", "lower depois", self.item, self.character)
    WB_Trace.survey("LARGAR", "lower depois", self.character, 2)

    WB_UI.refreshContainers()
    return self.item:getWorldItem() ~= nil
end

function ISWheelbarrowPutDown:start()
    self.item:setJobType(getText("IGUI_MNWB_PuttingDown"))
    self.item:setJobDelta(0.0)
    self:setActionAnim("Loot")

    --[[ QUANDO ESTE PROCESSO E O DONO DO MUNDO, O CARRINHO DESCE AQUI.

         start() roda no cliente e em single player, nunca no servidor dedicado --
         lah o gancho e serverStart. Entao WB_MP.isAuthority() (`not isClient()`)
         quer dizer, neste ponto exato, "single player ou o processo que hospeda":
         nos dois a acao nao foi replicada, e nos dois este processo pode mudar o
         mundo de verdade.

         No cliente MP a descida nao pode acontecer: ela mexe em container e poe
         objeto no mundo, e nenhuma das duas coisas sobe do cliente. O carrinho
         aparece no chao pelos pacotes que o serverStart do servidor gera.

         O custo disso e uma ida-e-volta de rede: entre o inicio da animacao e a
         chegada dos pacotes o carrinho nao esta desenhado em lugar nenhum, porque
         a animacao ja substituiu a mascara que o desenhava na mao. E o mesmo
         artefato que este desenho existe para evitar, reduzido de "a acao inteira"
         para "um ping". Nao ha como encurtar mais sem o cliente poder por objeto
         no mundo, o que a B42 nao permite. ]]
    if WB_MP.isAuthority() then self:lower() end
end

--- O gancho de inicio do SERVIDOR. Ver o cabecalho.
function ISWheelbarrowPutDown:serverStart()
    WB_Trace.log("LARGAR", "serverStart")
    self:lower()
end

--- Square onde o carrinho esta agora, para o derrame cair ao redor dele.
local function cartSquare(item, character)
    local worldItem = item:getWorldItem()
    local square = worldItem and worldItem:getSquare()
    return square or character:getSquare()
end

function ISWheelbarrowPutDown:stop()
    if getDebug() then
        print("[Wheelbarrow][ACAO] largar cancelado")
    end
    self.item:setJobDelta(0.0)

    -- Em multiplayer o derrame e do servidor, e sai por serverStop. Ver a
    -- explicacao em ISWheelbarrowPickUp:stop -- derramar aqui esvaziaria o
    -- carrinho so na tela de quem cancelou.
    if WB_MP.isAuthority() then self:spill() end

    ISBaseTimedAction.stop(self)
end

--- O cancelamento visto pelo servidor. Ver ISWheelbarrowPickUp:serverStop para o
--- caminho medido do pacote de cancelamento ate aqui.
function ISWheelbarrowPutDown:serverStop()
    WB_Trace.log("LARGAR", "serverStop -- cancelado pelo cliente")
    self:spill()
end

--- O carrinho ja esta no chao desde o inicio; cancelar so derruba a carga.
function ISWheelbarrowPutDown:spill()
    if not WB_Sandbox.get("SpillOnCancel") then return end
    if self.item == nil then return end

    local square = cartSquare(self.item, self.character)
    if square == nil then return end

    WB_Spill.dump(self.item, square)
    -- O carrinho ja esta no chao desde o inicio, mas dropTipped o recria: a
    -- altura do tombo so entra na criacao do objeto de mundo.
    WB_Tipping.dropTipped(self.character, self.item, square)
end

--[[ TIRA DA MAO, SO NO CLIENTE MP, UM CARRINHO QUE NAO E MAIS DE NINGUEM.

     O espelho de ISWheelbarrowPickUp:forgetStrayWorldObjects, e o outro lado da
     mesma cascata. O jogador relatou assim: "completo a animacao de largar, o
     carrinho e largado na minha frente e outro continua na minha mao -- o da mao
     parece um fantasma". E era.

     Quando o cliente acumula dois InventoryItem com o mesmo id -- porque o
     AddInventoryItemToContainer cria um novo em vez de reaproveitar --, o
     RemoveInventoryItemFromContainer tira UM deles do inventario e as maos podem
     estar apontando para o OUTRO. Sobra um item que nao esta em container nenhum,
     desenhado na mao.

     Aqui a verdade e conhecida: perform() so roda depois de o servidor confirmar o
     largar, entao a essa altura nao ha carrinho nenhum que devesse estar na mao.

     SO NO CLIENTE MP pelo mesmo motivo do gemeo: em single player perform() roda
     ANTES de complete(), e desequipar ali atrapalharia a acao que ainda vai
     acontecer. ]]
function ISWheelbarrowPutDown:releasePhantom()
    if WB_MP.isAuthority() then return end
    WB_Trace.survey("LARGAR", "releasePhantom antes", self.character, 2)

    local character = self.character
    local primary = character:getPrimaryHandItem()
    local secondary = character:getSecondaryHandItem()
    local inv = character:getInventory()

    -- Um carrinho na mao que o inventario nao contem mais e orfao por definicao:
    -- no PZ a mao e um slot que APONTA para um item do inventario.
    local function orphan(item)
        return WB_Cart.is(item) and not inv:contains(item)
    end

    if orphan(primary) then character:setPrimaryHandItem(nil) end
    if orphan(secondary) then character:setSecondaryHandItem(nil) end
end

--- So cosmetico: o carrinho desceu no inicio. Terminar aqui e soltar o
--- personagem da animacao.
function ISWheelbarrowPutDown:perform()
    -- Guarda no MESMO nivel do resto do arquivo. lower() e complete() checam
    -- `self.item == nil` porque a reconstrucao de rede pode nao resolver o item, e
    -- tres linhas abaixo esta funcao faz `self.item and self.item:getID()`. Confiar
    -- no campo aqui e desconfiar dele lah e uma incoerencia que so nao estourou
    -- porque perform() nao roda no servidor dedicado, que e onde a resolucao falha.
    if self.item ~= nil then self.item:setJobDelta(0.0) end

    self:releasePhantom()
    -- O carrinho acabou de ir para o chao pelas maos do servidor, entao tudo o
    -- que a fila guardava dele envelheceu neste instante. Ver WB_Rebind.
    WB_Rebind.queuedActions(self.character, self.item and self.item:getID())

    -- Em multiplayer complete() nao roda no cliente, e este e o unico ponto que
    -- sabe que a acao acabou. Mesmo motivo pelo qual ISDropWorldItemAction marca
    -- ISInventoryPage.renderDirty no perform.
    WB_UI.refreshContainers()
    self.character:resetModelNextFrame()

    ISBaseTimedAction.perform(self)
end

--- O veto do servidor, e a rede de seguranca do "desce no inicio".
---
--- Nao e formalidade: complete() precisa devolver um booleano de verdade -- o
--- servidor le o retorno com protectedCallBoolean e transforma qualquer coisa
--- que nao seja booleano em rejeicao -- e a unica coisa que ainda pode ter dado
--- errado e o carrinho nao ter achado chao no inicio.
function ISWheelbarrowPutDown:complete()
    WB_Trace.item("LARGAR", "complete", self.item, self.character)
    if self.item == nil then return false end
    -- Ja desceu, no serverStart ou no start: nada a fazer.
    if self.item:getWorldItem() ~= nil then return true end
    -- Nao desceu. Este e o ultimo momento possivel, e lower() e idempotente.
    return self:lower()
end

--- CADA ARGUMENTO VIRA UM CAMPO DE MESMO NOME E VALOR CRU -- e o contrato de
--- reconstrucao do servidor, explicado em ISWheelbarrowPickUp:cart.
---
--- O carrinho chega aqui equipado, logo dentro do inventario do jogador, logo
--- enderecavel por (PlayerInventory, playerId, itemId). E por isso que esta acao
--- nao precisa do objeto de mundo que a de pegar precisa.
--- @param square IsoGridSquare|nil onde pousar; nil pousa na frente do personagem
---
--- O TERCEIRO ARGUMENTO E OPCIONAL E O NOME DELE E CONTRATO DE REDE. NetTimedAction.set
--- le os NOMES DOS PARAMETROS desta funcao e serializa os campos de mesmo nome, entao
--- `square` tem de continuar sendo `square` e guardar o valor cru. IsoGridSquare esta
--- entre os tipos que atravessam; se ainda assim nao resolver do outro lado, lower()
--- cai na square da frente sozinho.
function ISWheelbarrowPutDown:new(character, item, square)
    local o = ISBaseTimedAction.new(self, character)
    o.item = item
    o.square = square
    o.stopOnWalk = true
    o.stopOnRun = true

    --[[ LARGAR O CARRINHO VALE MESMO ARRASTANDO UM CADAVER.

         ISTimedActionQueue.add recusa em SILENCIO qualquer acao sem esta marca
         enquanto o jogador arrasta um corpo -- so um texto acima do personagem, e a
         acao nem entra na fila.

         Sem ela o estacionamento simplesmente nao acontecia no caminho do cadaver:
         o jogador arrastava o corpo ate o carrinho, o largar era recusado, e o
         deposito rodava com o carrinho ainda na mao. Ou seja, justamente o caso em
         que a regra do mod mais faz sentido fisicamente -- pousar o carrinho para
         ter as maos livres e erguer o corpo -- era o unico em que ela nao valia.

         A acao de PEGAR nao recebe a marca, e a assimetria e proposital: pousar o
         carrinho arrastando um corpo se faz; erguer um carrinho com um corpo na
         outra mao, nao. Depois de o corpo entrar o jogador deixa de arrastar, e o
         retorno acontece normalmente. ]]
    o.allowedWhileDraggingCorpses = true
    o.maxTime = o:getDuration()
    return o
end

return ISWheelbarrowPutDown
