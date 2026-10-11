--[[
    Poe o carrinho NAS MAOS. O espelho de WB_Spill.placeOnGround.

    POR QUE E UMA FUNCAO SO: esta sequencia e delicada e ja provou custar caro
    quando escrita de novo. A versao original vivia dentro de
    ISWheelbarrowPickUp:perform, e quando o estacionamento durante acoes precisou
    do mesmo comportamento, copiar era o caminho obvio -- e teria repetido o
    defeito descrito abaixo, ou pior, divergido dele com o tempo.

    E o mesmo motivo pelo qual existe UMA funcao para colocar no chao: as duas
    primeiras copias daquela divergiram na direcao do carrinho.

    ----------------------------------------------------------------------
    MULTIPLAYER: ESTA FUNCAO SO FALA COM A REDE SOB AUTORIDADE.

    A mesma regra vale para a irma dela, WB_Spill.placeOnGround, e as duas juntas
    dao uma frase so para lembrar: em multiplayer estas funcoes sao do SERVIDOR --
    o lugar de chamar esta e ISWheelbarrowPickUp:complete(). Chamada de um cliente,
    ela muda so o mundo local, calada e por inteiro.

    "Calada por inteiro" e escolha, e nao limitacao. O passo que nao existe no
    sentido cliente->servidor e o do meio (sendAddItemToContainer, so-servidor, sem
    pacote equivalente em nenhuma das 104 classes de zombie/network/packets). Se os
    outros dois passos falassem, o resultado seria PERDA: o carrinho sairia do chao
    para todos e nao entraria no inventario de ninguem.

    Hoje o UNICO chamador e ISWheelbarrowPickUp:complete(). O estacionamento, que
    era o outro, passou a devolver o carrinho pela mesma acao cronometrada -- ver o
    cabecalho de WB_Parking. Ou seja, esta funcao nao roda mais no cliente MP em
    nenhum caminho, e a guarda de autoridade abaixo virou cinto e suspensorio.
    Fica, porque o dia em que alguem chamar isto de um handler de cliente ela e a
    diferenca entre um carrinho fora de sincronia e um carrinho perdido.
]]

local WB_MP = require "WB_MP"
local WB_Tipping = require "WB_Tipping"
local WB_Trace = require "WB_Trace"
local WB_Transfer = require "WB_Transfer"
local WB_UI = require "WB_UI"

local WB_Equip = {}

--- @param worldItem IsoWorldInventoryObject|nil o objeto de mundo, quando o
---        chamador ja o tem em mao. Omitido, sai do proprio carrinho.
--- @return boolean se o carrinho foi para as maos
function WB_Equip.toHands(character, cart, worldItem)
    if character == nil or cart == nil then return false end

    -- Uma pergunta so, e ela nao muda no meio da operacao. Ver o cabecalho: e o
    -- interruptor de tudo o que sai daqui pela rede.
    local authority = WB_MP.isAuthority()
    WB_Trace.item("MAO", "toHands entrada", cart, character)

    -- Levanta ANTES de tudo. Um carrinho tombado que vai para a mao assim leva a
    -- inclinacao gravada no ModData, e reaparece torto na proxima vez que for
    -- largado -- um tombo que o jogador nunca causou.
    WB_Tipping.reset(cart)

    -- A rede de WB_Placement poe no chao todo carrinho desequipado que encontre
    -- num inventario, e equipar passa obrigatoriamente por esse estado: AddItem
    -- vem antes de setPrimaryHandItem. Sem suspender, a rede teleporta o carrinho
    -- para os pes do jogador no meio da operacao -- que foi o sintoma observado,
    -- "traz o carrinho ate onde estou mas nao equipa".
    WB_Transfer.begin()

    worldItem = worldItem or cart:getWorldItem()
    if worldItem ~= nil then
        --[[ A SEQUENCIA E COPIADA DE ISGrabItemAction:transferItem, e nao
             inventada -- a minha tinha tres passos a menos e o que faltava era
             justamente o ultimo:

                 setWorldItem(nil)

             Sem ele o item continua APONTANDO para o objeto de mundo que acabou
             de sair da square. getWorldItem() segue devolvendo algo, e tres
             lugares leem isso como "ja esta no chao": WB_Player desequipa por
             quadro, WB_Hands desequipa ao equipar, e WB_Spill.dropCart nao faz
             nada. O sintoma foi o carrinho cair no inventario desequipado e
             recusar qualquer tentativa de equipar. Uma referencia pendurada,
             tres defeitos. ]]
        --[[ SOB AUTORIDADE, e isto nao e simetria decorativa.

             RemoveItemFromSquarePacket endereca o objeto por (x, y, z, indice na
             lista da square), e removeItemFromMap remove O QUE ESTIVER naquele
             indice: as unicas conferencias sao `indice >= 0` e
             `indice < objects:size()` (offsets 19-34). Nao ha teste de tipo nem de
             identidade -- ele tem ramo proprio para quando o objeto NAO e um
             IsoWorldInventoryObject, e ali o que ele apaga e mobilia ou parede.

             Nenhum caminho do cliente MP chega aqui hoje. Se algum voltar a
             chegar, o objeto de mundo dele sera LOCAL -- o servidor nao o tem,
             entao o indice aponta para outra coisa na lista dele. Normalmente para
             uma posicao que nao existe, e o pacote nao faz nada; mas se outro
             jogador tiver largado algo naquela square, aponta para o item dele.
             Risco sem ganho. ]]
        local square = worldItem:getSquare()
        if square ~= nil and authority then
            square:transmitRemoveItemFromSquare(worldItem)
        end
        worldItem:removeFromWorld()
        worldItem:removeFromSquare()
        worldItem:setSquare(nil)
        cart:setWorldItem(nil)
    end

    -- AddItem em vez do fluxo normal de transferencia de proposito: o carrinho
    -- cheio nao passaria no teste de capacidade do inventario do jogador, e e
    -- justamente isso que o carrinho existe para contornar. O peso continua
    -- contando -- o alivio vem da reducao calculada em WB_Weight, nao daqui.
    local inv = character:getInventory()
    if not inv:contains(cart) then
        inv:AddItem(cart)
        --[[ O par obrigatorio do AddItem, e ele SO faz algo no servidor: o corpo
             de sendAddItemToContainer inteiro e
             `if GameServer.server then GameServer.sendAddItemToContainer(...) end`.

             Nao ha remendo do outro lado: varri as 104 classes de
             zombie/network/packets e nao existe pacote cliente->servidor que
             adicione item a container -- AddInventoryItemToContainerPacket so tem
             processClient. E por isso que esta funcao so sincroniza de verdade
             quando roda dentro de complete(), no servidor.

             No servidor o destino aqui e o inventario de um IsoPlayer, e
             GameServer.sendAddItemToContainer tem ramo dedicado para isso: manda o
             pacote para aquele jogador.

             Sob a mesma guarda dos outros dois por uniformidade, e nao por
             necessidade: o `if GameServer.server` interno ja bastaria. Uma regra
             sem excecao e mais facil de manter do que tres guardas diferentes. ]]
        if authority then sendAddItemToContainer(inv, cart) end
    end

    -- A square do container so e verdade enquanto o carrinho esta no chao. Quem a
    -- escreve e WB_Corpse, para que throwGrappledIntoInventory ache a posicao; se
    -- ela sobrevivesse a subida para as maos, ItemContainer.getSquare passaria a
    -- mentir sobre onde o compartimento esta.
    local inventory = cart:getInventory()
    if inventory ~= nil then inventory:setSourceGrid(nil) end

    character:setPrimaryHandItem(cart)
    character:setSecondaryHandItem(cart)

    --[[ O QUE FAZ AS MAOS CHEGAREM AOS OUTROS, e tem de vir DEPOIS do AddItem.

         setPrimaryHandItem nao transmite nada sozinho -- ele so marca
         handItemShouldSendToClients e dispara OnEquipPrimary. E nada le essa marca
         por quadro: varri IsoGameCharacter inteira e o unico chamador interno de
         updateHandEquips e CanAttack. Sem esta linha, no servidor as maos mudam e
         ninguem fica sabendo.

         updateHandEquips e ciente de lado -- no servidor manda o Equip aos
         clientes por perto, no cliente manda ao servidor, e em single player nao
         faz nada, porque INetworkPacket.send sai cedo quando GameClient.client e
         falso. Ainda assim vai sob autoridade: do cliente ele anunciaria maos
         cheias sem o carrinho ter saido do chao para mais ninguem, e o servidor
         passaria a ter o carrinho em dois lugares.

         DEPOIS DO AddItem, e nao antes: EquipPacket.parse resolve o item da mao do
         jogador local por getInventory():getItemWithID(id) e, quando nao acha,
         deixa a mao VAZIA -- ja tendo chamado setPrimaryHandItem(null). Se o Equip
         chegasse antes do AddInventoryItemToContainer, o proprio pacote que devia
         equipar o carrinho o desequiparia. Os dois saem pela mesma conexao, na
         ordem em que forem enviados. ]]
    if authority then character:updateHandEquips() end

    character:resetModelNextFrame()
    -- Sem isto o compartimento do carrinho so aparecia na barra de containers
    -- depois de o jogador clicar em alguma coisa.
    WB_UI.refreshContainers()

    WB_Transfer.finish()
    WB_Trace.item("MAO", "toHands saida", cart, character)
    return true
end

return WB_Equip
