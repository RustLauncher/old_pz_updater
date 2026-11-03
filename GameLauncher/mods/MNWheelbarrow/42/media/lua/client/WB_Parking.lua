--[[
    Com o carrinho na mao, QUALQUER acao exige larga-lo primeiro -- e pega-lo de
    volta depois.

    ----------------------------------------------------------------------
    A REGRA, e ela e do Marcos

    Um carrinho de mao ocupa as duas maos. Realisticamente, nao ha acao que se
    faca segurando os cabos: para qualquer outra coisa a pessoa para, apoia o
    carrinho no chao, faz, e levanta de novo. E a logica do mod inteiro, e as duas
    acoes cronometradas ja sao ela em miniatura -- largar e pegar levam tempo, e
    interromper derruba a carga. Estender isso a toda acao nao e restricao nova, e
    a mesma regra aplicada onde ela sempre valeu.

    O custo e o ponto: no meio de zumbis, precisar largar o carrinho e esperar --
    sabendo que desistir derrama tudo -- e exatamente a decisao que o mod existe
    para criar.

    ----------------------------------------------------------------------
    O CAMINHO ATE AQUI, porque ele explica o desenho

    Com o carrinho equipado, mover um item para dentro dele fazia o carrinho
    desaparecer durante a animacao. A causa esta escrita no jogo:

        ISGrabItemAction:start()                  setOverrideHandModels(nil, nil)
        ISInventoryTransferAction:doActionAnim()  setOverrideHandModels(nil, nil)

    e mais 50 acoes vanilla. A acao MANDA o engine nao desenhar nada nas maos.

    A primeira correcao foi devolver o modelo do carrinho nessa chamada. Funcionou
    -- e ficou pior. A animacao "Loot" agacha e mexe as maos, e um carrinho
    grudado nelas acompanha o agachamento inteiro. Visivel e errado e pior que
    invisivel: parece defeito, nao parece carrinho.

    O certo era o obvio depois de visto: o personagem LARGA o carrinho, mexe nos
    itens com as maos livres, e pega de volta. E o que uma pessoa faz.

    ----------------------------------------------------------------------
    POR QUE O GANCHO DEIXOU DE SER setOverrideHandModels

    Ele era o sinal ideal -- a acao dizendo "quero as maos vazias", sem lista para
    manter, valendo para acoes de outros mods. Em single player funciona.

    Em multiplayer ele chega TARDE DEMAIS, e isso e medido.
    ISInventoryTransferAction:start(), linhas 305-317:

        if isClient() then
            self.action:setWaitForFinished(true)
            ...
            self.transactionId = createItemTransaction(...)   <- decide aqui
        end
        self:startActionAnim()   -> doActionAnim -> setOverrideHandModels(nil,nil)

    Quando o gancho dispara, a transacao ja foi criada e enviada. E ela e recusada,
    porque ItemContainer.hasRoomFor (offsets 43-145) exige que um item que entre num
    container EQUIPADO tambem caiba no inventario do jogador -- e quem esta com o
    carrinho na mao costuma estar carregando o que ia para dentro dele. A recusa e
    muda: createItemTransaction devolve 0 e isItemTransactionDone(0) devolve true,
    entao a fila trata como sucesso e nada se move.

    Em single player o mesmo codigo funciona porque createItemTransaction nem e
    chamado -- esta dentro do `if isClient()` -- e o movimento real so acontece no
    perform(), bem depois do estacionamento.

    Entao o estacionamento passou para a ENTRADA DA FILA, que e antes de tudo. O
    preco e a generalidade: em ISTimedActionQueue.add eu so sei o TIPO da acao, nao
    se ela quer as maos livres. A decisao foi cobrir TODAS -- ver a regra no topo --
    com duas excecoes, abaixo.

    ----------------------------------------------------------------------
    POR QUE ELE LARGA COM A ACAO CRONOMETRADA, E NAO NA MAO

    Porque em multiplayer so ela funciona. Colocar objeto no mundo a partir do
    cliente nao sincroniza (ver o cabecalho de WB_Spill), e ISWheelbarrowPutDown ja
    e replicada, ja executa no servidor e ja foi testada em jogo. Reusar a peca que
    passou no teste vale mais que uma rota de rede nova.

    De quebra, a volta deixou de ser instantanea -- e isso agora e proposital, nao
    concessao. A versao anterior devolvia o carrinho de graca com o argumento de
    que "o jogador nunca pediu para solta-lo". Ele tambem nunca pediu para carregar
    um carrinho no meio de zumbis; o tempo e o risco sao a mecanica.
]]

require "TimedActions/ISWheelbarrowPickUp"
require "TimedActions/ISWheelbarrowPutDown"

local WB_Cart = require "WB_Cart"
local WB_Const = require "WB_Const"
local WB_MP = require "WB_MP"
local WB_Trace = require "WB_Trace"

local WB_Parking = {}

--- Carrinhos estacionados por nos, por jogador.
---
--- Chaveado por valor e nao pelo objeto de personagem: a tabela e de vida longa e
--- uma chave por objeto vazaria memoria a cada morte ou troca de save.
---
--- A CHAVE NAO PODE SER getPlayerNum() EM MULTIPLAYER. Ele e o indice de TELA, e
--- vale 0 para TODO jogador remoto num cliente -- ou seja, dois jogadores colidem
--- na mesma entrada e um estaciona o carrinho do outro. WB_MP.playerKey usa o
--- nome de usuario em MP, que e o idioma de FishingHandler.lua:23.
---
--- Preenchida no momento em que o LARGAR E ENFILEIRADO, e nao quando ele termina.
--- E o que impede a segunda acao da mesma leva de enfileirar um segundo largar:
--- entre enfileirar e concluir, o carrinho continua na mao.
local parked = {}

--- O alcance vive em WB_Const: e o mesmo numero que a limpeza de objeto obsoleto
--- e a busca do carrinho vivo usam, e tres copias dele ja existiram.
---
--- Ele importa aqui porque o jogador PODE se afastar durante a acao. Se ele foi
--- embora, o carrinho fica onde foi deixado -- e o certo, e o contrario seria o
--- carrinho voando de volta atravessando a distancia.
local REACH = WB_Const.CART_REACH

--- Acoes que NAO fazem o carrinho descer.
---
--- Sao duas, e as duas sao a mesma ideia: nao sao "coisas que voce faz", sao como
--- voce CHEGA ate a coisa. Empurrar o carrinho ate o lugar e justamente o que o
--- mod quer que o jogador faca; largar antes de andar deixaria o carrinho para
--- tras e o jogador andaria de maos vazias ate o destino -- o oposto do desenho.
---
--- ISPathFindAction fica de fora da lista de proposito: ela e o caminho de
--- veiculo, e entrar em veiculo com o carrinho ja e recusado em WB_Interact.
local PASSTHROUGH = {
    ISWalkToTimedAction = true,
    ISWalkToTimedActionF = true,
    -- As nossas. Sem isto, enfileirar o largar dispararia outro largar.
    ISWheelbarrowPutDown = true,
    ISWheelbarrowPickUp = true,
}

--- @return boolean se ainda ha acao rodando ou na fila
---
--- As duas checagens importam. getCharacterActions e a acao EM EXECUCAO; a fila
--- do Lua guarda as que ainda vao comecar. Transferir dez itens sao dez acoes
--- enfileiradas, e olhar so a primeira faria o carrinho subir e descer dez vezes.
local function stillWorking(character)
    if not character:getCharacterActions():isEmpty() then return true end
    local queue = ISTimedActionQueue.queues[character]
    return queue ~= nil and queue.queue[1] ~= nil
end

--- Acha no chao, ao alcance, o objeto de mundo do carrinho de identificador `id`.
---
--- POR QUE POR ID E NAO PELA REFERENCIA GUARDADA: em multiplayer o carrinho que
--- volta do servidor pode ser outro OBJETO. O AddItemToMap traz o item
--- desserializado, e quem guardou a referencia antes fica com uma copia velha, cujo
--- getWorldItem() e nil para sempre. O identificador numerico sobrevive aos dois
--- lados; a referencia nao.
---
--- @return IsoWorldInventoryObject|nil
local function findOnGround(character, id)
    local found = nil
    WB_Cart.forEachOnGround(character, REACH, function(item, obj, _sq)
        if found == nil and item:getID() == id then found = obj end
    end)
    return found
end

--- Devolve o carrinho as maos se a fila de acoes terminou.
---
--- Chamado do handler por quadro de WB_Player, e nao de um OnPlayerUpdate proprio:
--- o mod tem UM trabalho por quadro de proposito, e a ordem entre as regras
--- deixaria de ser legivel se cada arquivo registrasse o seu.
function WB_Parking.restoreIfIdle(character)
    local key = WB_MP.playerKey(character)
    local cart = parked[key]
    if cart == nil then return end
    if stillWorking(character) then return end

    -- Zerado ANTES de enfileirar: a acao de pegar entra na fila e o proximo quadro
    -- ja veria stillWorking falso por um instante. Sem zerar aqui, enfileirariamos
    -- duas.
    parked[key] = nil

    if character:isDead() then return end

    -- Maos ocupadas: o jogador equipou outra coisa durante a acao. A escolha dele
    -- vale mais do que a nossa devolucao -- arrancar uma arma da mao de alguem
    -- porque o mod tinha um carrinho guardado seria indefensavel.
    if character:getPrimaryHandItem() ~= nil
        or character:getSecondaryHandItem() ~= nil then
        return
    end

    -- Se ele nao esta mais ao alcance, fica onde foi deixado. O jogador se afastou
    -- durante a acao, e o contrario seria o carrinho voando de volta.
    WB_Trace.survey("ESTACIONA", "voltando", character, REACH)
    local worldItem = findOnGround(character, cart:getID())
    if worldItem == nil then
        WB_Trace.log("ESTACIONA", "carrinho #" .. cart:getID()
            .. " nao esta mais ao alcance -- fica onde foi deixado")
        return
    end

    -- Pela acao cronometrada, e nao por WB_Equip direto: e ela que roda no
    -- servidor. O objeto de mundo vai como argumento porque um carrinho largado
    -- nao tem container, e um InventoryItem sem container chega nil do outro lado
    -- -- ver o comentario de new() em ISWheelbarrowPickUp.
    ISTimedActionQueue.add(ISWheelbarrowPickUp:new(character, worldItem))

    if getDebug() then
        print("[Wheelbarrow][ESTACIONA] pegar de volta enfileirado")
    end
end

--[[ @return boolean se esta acao age SOBRE o carrinho, e nao com ele

     NAO SE ESTACIONA O CARRINHO PARA FAZER ALGO AO CARRINHO. Relatado em
     17/08/2026: clicar no carrinho no inventario e escolher "colocar no chao" -- a
     opcao do JOGO BASE -- largava o carrinho e o pegava de volta sozinho.

     O caminho, medido em ISInventoryPaneContextMenu.dropItem:

         if playerObj:isHandItem(item) then
             ISTimedActionQueue.add(ISUnequipAction:new(playerObj, item, 1, "drop"))

     ISUnequipAction nao esta em PASSTHROUGH, entao o estacionamento a tratava como
     qualquer outra: largava o carrinho antes, o vanilla desequipava e dropava, a fila
     esvaziava e restoreIfIdle cumpria o combinado e devolvia o carrinho a mao. Duas
     acoes brigando, cada uma correta pelas proprias regras.

     A regra por TIPO nao resolveria: qualquer acao do jogo base ou de outro mod que
     receba o carrinho como alvo tem o mesmo problema, e enumera-las e a lista que
     envelhece. A pergunta certa nao e "que acao e esta" e sim "ela e sobre o
     carrinho". ]]
local function actsOnCart(action, cart)
    if action == nil or cart == nil then return false end

    -- instanceof antes de qualquer metodo: esta funcao le campo de acao de terceiro,
    -- e `item` e o nome mais disputado que existe numa timed action. Ver WB_Rebind.
    local item = action.item
    if item ~= nil and instanceof(item, "InventoryItem") and item == cart then
        return true
    end

    -- Levas: ISInventoryPaneContextMenu passa listas, e o carrinho pode ser um dos
    -- itens de uma selecao multipla.
    if type(action.items) == "table" then
        for i = 1, #action.items do
            local entry = action.items[i]
            if entry ~= nil and instanceof(entry, "InventoryItem") and entry == cart then
                return true
            end
        end
    end

    return false
end

--- @return InventoryItem|nil o carrinho a largar antes desta acao, se houver
local function cartToPark(action)
    if action == nil or action.ignoreAction then return nil end
    if PASSTHROUGH[action.Type] then return nil end

    local character = action.character
    -- isLocalPlayer e nao so instanceof: a fila de um jogador remoto tambem passa
    -- por aqui, e estacionar o carrinho dele largaria um fantasma local que nao
    -- existe para mais ninguem.
    if not WB_MP.isLocalPlayer(character) then return nil end

    local key = WB_MP.playerKey(character)
    -- Ja ha um largar enfileirado por nos: a leva inteira usa o mesmo.
    if parked[key] ~= nil then return nil end

    local cart = WB_Cart.equipped(character)
    if cart == nil then return nil end

    if actsOnCart(action, cart) then
        WB_Trace.log("ESTACIONA", "nao estaciona: " .. tostring(action.Type)
            .. " age sobre o proprio carrinho")
        return nil
    end

    WB_Trace.log("ESTACIONA", "vai largar antes de " .. tostring(action.Type))
    parked[key] = cart
    return cart
end

--[[ ANDAR CANCELA QUALQUER ACAO FEITA COM O CARRINHO ESTACIONADO.

     A REGRA, e ela vem do mesmo lugar que o resto: o carrinho esta no chao ao seu
     lado, e voce esta abaixado mexendo nele. Sair andando interrompe -- e
     interromper derruba a carga, que e a mecanica.

     O QUE ISTO CONSERTA: o vanilla trata as duas transferencias de forma
     diferente, e a diferenca vazava para o jogador.

       do CHAO para o carrinho    ja parava ao andar, porque a proximidade da
                                  origem invalida a acao
       do INVENTARIO para o       nao parava: transferir entre coisas que voce
       carrinho                   carrega e feito andando de proposito pelo jogo,
                                  que ate troca para a animacao DropWhileMoving

     Resultado: com o carrinho estacionado e os troncos no inventario, dava para se
     afastar a distancia que quisesse e os itens entravam no carrinho mesmo assim.
     O carrinho ficava para tras e a carga aparecia dentro dele.

     A marca vale para TODA acao enfileirada enquanto ha carrinho estacionado, e nao
     so para a primeira da leva -- arrastar tres troncos sao tres acoes, e marcar so
     uma deixaria as outras duas com o defeito.

     Fora as de PASSTHROUGH, e ai a exclusao e obrigatoria e nao estetica: marcar
     stopOnWalk numa acao de ANDAR faria andar cancelar andar.

     O campo e lido pelo engine na construcao da acao -- LuaTimedActionNew.<init>,
     offsets 43-51, faz rawget "stopOnWalk" na tabela -- e a construcao acontece
     quando a acao COMECA. Escrever aqui, na entrada da fila, chega a tempo mesmo
     que o new() do jogo base tenha posto false. ]]
local function stopWhenWalkingAway(action)
    if action == nil or PASSTHROUGH[action.Type] then return end
    if not WB_MP.isLocalPlayer(action.character) then return end
    if parked[WB_MP.playerKey(action.character)] == nil then return end

    action.stopOnWalk = true
    action.stopOnRun = true
end

Events.OnGameStart.Add(function()
    local original = ISTimedActionQueue.add

    ISTimedActionQueue.add = function(action)
        --[[ UM LARGAR PEDIDO PELO JOGADOR CANCELA A DEVOLUCAO PENDENTE.

             Se o jogador manda largar o carrinho -- pelo menu de contexto ou pela
             tecla E -- ele decidiu onde o carrinho vai ficar. Devolve-lo a mao depois
             seria o mod discutindo com uma ordem direta, e foi o que o relato de
             17/08/2026 descreveu: "solta o carrinho e depois pega de novo".

             O GANCHO E ESTE ENVELOPE, e a razao e sutil: o largar que o proprio
             estacionamento enfileira chama `original` diretamente, algumas linhas
             abaixo, e portanto NAO passa por aqui. Entao um ISWheelbarrowPutDown
             chegando neste ponto so pode ter vindo do jogador -- a distincao sai de
             graca, sem campo novo e sem consultar quem chamou.

             Fica antes de cartToPark porque um PutDown e PASSTHROUGH: cartToPark
             devolveria nil e nunca chegaria a limpar a marca. ]]
        if action ~= nil and action.Type == "ISWheelbarrowPutDown"
            and WB_MP.isLocalPlayer(action.character) then
            local key = WB_MP.playerKey(action.character)
            if parked[key] ~= nil then
                parked[key] = nil
                WB_Trace.log("ESTACIONA",
                    "o jogador mandou largar -- devolucao cancelada")
            end
        end

        local cart = cartToPark(action)
        if cart ~= nil then
            -- Pelo `original`, e nao pela funcao envolvida: passar por aqui de novo
            -- entraria em recursao. A excecao de PASSTHROUGH ja cobriria, mas
            -- depender dela para nao travar o jogo seria fragil.
            --[[ SO CONTA COMO ESTACIONADO SE A FILA ACEITOU.

                 ISTimedActionQueue.add tem varias saidas silenciosas -- personagem
                 dormindo, acao com ignoreAction, e a de arrastar cadaver que ja
                 custou um defeito aqui. Em todas elas ela devolve nil sem
                 enfileirar nada.

                 Marcar o carrinho como estacionado sem ele ter descido deixa o mod
                 com um estado que nao existe: a devolucao procura no chao um
                 carrinho que nunca saiu da mao. ]]
            local queued = original(ISWheelbarrowPutDown:new(action.character, cart))
            if queued == nil then
                parked[WB_MP.playerKey(action.character)] = nil
                WB_Trace.log("ESTACIONA",
                    "a fila recusou o largar -- carrinho segue na mao")
                cart = nil
            elseif getDebug() then
                print("[Wheelbarrow][ESTACIONA] largar enfileirado antes de "
                    .. tostring(action.Type))
            end
        end

        -- Depois do estacionamento, e nao antes: cartToPark e quem marca o carrinho
        -- como estacionado, e e essa marca que stopWhenWalkingAway consulta. Assim a
        -- primeira acao da leva e tratada igual as seguintes.
        stopWhenWalkingAway(action)

        return original(action)
    end
end)

return WB_Parking
