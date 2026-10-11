--[[
    Rastreamento do mod, ligavel em jogo e valendo nos DOIS processos.

    ----------------------------------------------------------------------
    POR QUE ISTO EXISTE

    Depurar multiplayer por sintoma nao funciona, e este projeto pagou por isso:
    "o carrinho duplicou" tem pelo menos cinco causas possiveis, e cada rodada de
    palpite custa um teste em jogo do Marcos. O que resolve e ver, de cada lado,
    o que cada funcao recebeu e o que ela deixou para tras.

    O que se quer saber, sempre, e a mesma coisa: ONDE o carrinho esta. As
    respostas possiveis nao sao duas, sao cinco, e elas se sobrepoem -- e a
    sobreposicao que produz os defeitos:

        na mao (primaria, secundaria, ou as duas)
        num container (qual)
        no mundo (em que square)
        em mais de um desses ao mesmo tempo   <- o defeito
        em nenhum                             <- o outro defeito

    Por isso `describe` imprime os cinco de uma vez, e nao o que o chamador
    achou relevante. Um rastro que so mostra o que o autor suspeitava confirma a
    suspeita dele.

    ----------------------------------------------------------------------
    POR QUE NAO getDebug()

    No processo do SERVIDOR getDebug() e falso mesmo com -debug na linha de
    comando -- so -Ddebug, propriedade da JVM, liga. Um rastro guardado por
    getDebug() nao sairia justamente do lado que decide a verdade.

    E `-debug` no cliente liga o console inteiro do jogo, que enterra o nosso
    rastro em milhares de linhas vanilla.

    Entao o interruptor e nosso: uma caixa em Opcoes -> Mods. Ver WB_Options.

    ----------------------------------------------------------------------
    COMO O SERVIDOR FICA SABENDO

    A caixa de opcoes e do CLIENTE -- PZAPI.ModOptions vive em lua/client/, que o
    servidor dedicado nem executa. Entao ligar a caixa manda um comando ao
    servidor, e ele liga o proprio interruptor.

    E o primeiro uso da rota cliente->servidor neste mod, e ela e de graca aqui:
    um comando que so liga um booleano de depuracao nao pode corromper mundo
    nenhum se der errado.
]]

local WB_Const = require "WB_Const"

local WB_Trace = {}

--[[ Ligado?

     O RASTREAMENTO E PERMANENTE. Ele nao sai antes de publicar, e uma versao
     anterior deste comentario dizia que sim -- estava errado. Instrumentacao com
     custo zero quando desligada e a ferramenta que resolveu a maior parte dos
     defeitos deste porte; apaga-la seria jogar fora justamente o que funcionou. A
     CAIXA e que existe para ligar e desligar.

     COMECA DESLIGADO NOS DOIS LADOS. Houve um periodo em que o servidor comecava
     ligado, por muleta: o comando que liga vinha se perdendo, porque o cliente o
     mandava antes de o servidor ter jogador naquela conexao
     (GameServer.receiveClientCommand, offsets 82-93, volta em silencio). O envio
     passou a insistir -- ver WB_Options -- e ficou PROVADO em jogo que ele chega:
     "[WB][SRV] rastreamento LIGADO" aparece no log do servidor. A muleta saiu.

     Ou seja, hoje a caixa manda nos dois processos, que era o desenho desde o
     inicio. ]]
local enabled = false

--- @return string "SRV", "CLI" ou "SP" -- de que lado esta linha saiu
---
--- Vale mais do que parece: metade dos defeitos deste porte foi o mesmo codigo
--- rodando do lado errado, e sem o prefixo duas linhas iguais no log parecem uma
--- repeticao em vez de uma divergencia.
local function side()
    if isServer() then return "SRV" end
    if isClient() then return "CLI" end
    return "SP"
end

--- Imprime uma linha de rastro.
---
--- print e nao DebugLog: as razoes de recusa do engine saem por
--- DebugType.Objects.noise, abaixo do nivel Warning padrao, e nao aparecem. print
--- sai sempre, dos dois lados.
---
--- @param category string rotulo curto -- ACAO, MUNDO, MAO, REDE
function WB_Trace.log(category, message)
    if not enabled then return end
    print(string.format("[WB][%s][%s] %s", side(), category, message))
end

--- Onde este item esta, por inteiro e sem escolher.
---
--- @param item InventoryItem|nil
--- @param character IsoGameCharacter|nil dono suposto, para o teste de mao
--- @return string
function WB_Trace.describe(item, character)
    if item == nil then return "item=nil" end

    local parts = { string.format("id=%d tipo=%s", item:getID(), item:getFullType()) }

    local container = item:getContainer()
    parts[#parts + 1] = "container=" .. (container ~= nil
        and (container:getType() or "?") or "nenhum")

    local worldItem = item:getWorldItem()
    if worldItem ~= nil then
        local square = worldItem:getSquare()
        parts[#parts + 1] = square ~= nil
            and string.format("mundo=%d,%d,%d", square:getX(), square:getY(), square:getZ())
            or "mundo=SEM_SQUARE"
    else
        parts[#parts + 1] = "mundo=nao"
    end

    if character ~= nil then
        local hands = {}
        if character:isPrimaryHandItem(item) then hands[#hands + 1] = "primaria" end
        if character:isSecondaryHandItem(item) then hands[#hands + 1] = "secundaria" end
        parts[#parts + 1] = "mao=" .. (#hands > 0 and table.concat(hands, "+") or "nao")

        local inv = character:getInventory()
        parts[#parts + 1] = "noInv=" .. tostring(inv ~= nil and inv:contains(item) or false)
    end

    --[[ O conteudo importa por dois motivos.

         O primeiro apareceu cedo: metade dos relatos foi "os dois carrinhos
         vazios", e saber se o servidor concorda com isso separa perda de item de
         erro de tela.

         O segundo e o item 4 do HANDOFF, e e a razao de a capacidade e a reducao
         estarem aqui. A conta do mod so e refeita nos eventos que o servidor NAO
         recebe -- todos os gatilhos de WB_Weight sao de cliente, menos
         OnEquipPrimary/Secondary, que disparam incondicionalmente. Entao no
         servidor a capacidade e a reducao do carrinho ficam paradas no que valia da
         ultima vez que as MAOS mudaram, e e o servidor que valida a transferencia.

         Imprimir os tres numeros juntos -- capacidade, reducao e peso ocupado --
         torna essa divergencia visivel de um lado e do outro, em vez de deduzida do
         sintoma "so entraram 18 de 20". ]]
    local inside = item:getInventory()
    if inside ~= nil then
        parts[#parts + 1] = string.format("dentro=%d itens/%.1f peso cap=%d reducao=%d%%",
            inside:getItems():size(), inside:getCapacityWeight(),
            inside:getCapacity(), item:getWeightReduction())
    end

    return table.concat(parts, " ")
end

--- Rastro de um item, com rotulo.
function WB_Trace.item(category, label, item, character)
    if not enabled then return end
    WB_Trace.log(category, label .. ": " .. WB_Trace.describe(item, character))
end

--- Tudo o que ha de carrinho ao redor do personagem, no chao e nas maos.
---
--- E o rastro que responde "quantos carrinhos existem AQUI", que e a pergunta que
--- o teste em jogo faz e que nenhum rastro por item responde.
---
--- @param radius number raio em squares
function WB_Trace.survey(category, label, character, radius)
    if not enabled then return end
    if character == nil then
        WB_Trace.log(category, label .. ": personagem=nil")
        return
    end

    local lines = {}

    local primary = character:getPrimaryHandItem()
    local secondary = character:getSecondaryHandItem()
    lines[#lines + 1] = string.format("maos=[%s | %s]",
        primary ~= nil and (primary:getFullType() .. "#" .. primary:getID()) or "vazia",
        secondary ~= nil and (secondary:getFullType() .. "#" .. secondary:getID()) or "vazia")

    -- Varredura crua de squares: nao usa WB_Cart de proposito, para nao criar
    -- dependencia circular e para enxergar QUALQUER item, inclusive o que o mod
    -- nao reconhece como carrinho -- se um dia o reconhecimento for a causa, um
    -- rastro que ja filtra por ele nunca mostraria.
    local square = character:getSquare()
    local cell = getCell()
    if square ~= nil and cell ~= nil then
        local found = {}
        local px, py, pz = square:getX(), square:getY(), square:getZ()
        for dx = -radius, radius do
            for dy = -radius, radius do
                local sq = cell:getGridSquare(px + dx, py + dy, pz)
                if sq ~= nil then
                    local objects = sq:getWorldObjects()
                    for i = 0, objects:size() - 1 do
                        local obj = objects:get(i)
                        local item = instanceof(obj, "IsoWorldInventoryObject")
                            and obj:getItem() or nil
                        if item ~= nil
                            and WB_Const.HAULER_TYPES[item:getFullType()] == true then
                            found[#found + 1] = string.format("#%d@%d,%d",
                                item:getID(), sq:getX(), sq:getY())
                        end
                    end
                end
            end
        end
        lines[#lines + 1] = "chao=[" .. table.concat(found, " ") .. "]"
    end

    local inv = character:getInventory()
    if inv ~= nil then
        local found = {}
        local items = inv:getItems()
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            if WB_Const.HAULER_TYPES[item:getFullType()] == true then
                found[#found + 1] = "#" .. item:getID()
            end
        end
        lines[#lines + 1] = "inv=[" .. table.concat(found, " ") .. "]"
    end

    WB_Trace.log(category, label .. ": " .. table.concat(lines, " "))
end

--- Liga ou desliga NESTE processo.
function WB_Trace.set(on)
    enabled = on == true
    -- Fora da guarda de proposito: a linha que anuncia o desligamento tem de sair.
    print(string.format("[WB][%s] rastreamento %s", side(),
        enabled and "LIGADO" or "desligado"))
end

--[[ O servidor recebe o interruptor por comando.

     OnClientCommand so dispara no processo do servidor dedicado, entao nao ha
     guarda de lado a fazer aqui. Em single player nada disto roda, e nem precisa:
     la o proprio WB_Options ja chamou set().

     O modulo e conferido contra WB_Const para o handler nao responder a comando
     de outro mod que use o mesmo nome de comando. ]]
--[[ Anuncio de carga, sem guarda.

     Ele existe por um motivo especifico e pequeno: quando o rastro do servidor nao
     apareceu, a primeira duvida foi "o servidor executou este arquivo?" -- e nao
     havia como responder sem outra rodada de teste. Uma linha no boot responde de
     graca, para sempre.

     Fica FORA da guarda de proposito, mesmo agora que o padrao e desligado: ela e o
     unico sinal de que o mod carregou no servidor, e quem procura por ele esta
     justamente na situacao em que o rastro ainda nao foi ligado.

     So no servidor: no cliente esta pergunta se responde olhando o console, que ja
     tem o rastro. ]]
if isServer() then
    print("[WB][SRV] WB_Trace carregado; rastreamento inicial "
        .. (enabled and "LIGADO" or "desligado"))
end

Events.OnClientCommand.Add(function(module, command, _player, args)
    if module ~= WB_Const.NET_MODULE then return end
    if command ~= "trace" then return end
    WB_Trace.set(args ~= nil and args.on == true)
end)

return WB_Trace
