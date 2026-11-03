--[[
    Rastro do caminho de fabricacao, que e todo do jogo base.

    NAO E TEMPORARIO. Como o resto da instrumentacao deste mod, custa uma comparacao
    de booleano com a caixa de depuracao desligada, e a caixa e que existe para
    liga-lo.

    ----------------------------------------------------------------------
    POR QUE ELA PRECISA EXISTIR

    ISHandcraftAction:performRecipe() e um beco silencioso:

        if self.logic then
            if self.logic:performCurrentRecipe() then
                ... cria a saida, consome as entradas ...
            end
        end

    Quando performCurrentRecipe() devolve false NADA acontece -- nenhuma saida,
    nenhum consumo, nenhuma linha de log, nenhuma excecao. A animacao roda inteira e
    o jogador fica com os componentes na mao achando que o mod nao criou o item.

    Foi exatamente o sintoma medido em 16/08/2026: craft do carrinho com a animacao
    completa e nenhum resultado.

    A suspeita e o ESTACIONAMENTO, e ela e consequencia direta da decisao de projeto
    de que toda acao estaciona (secao 11 do HANDOFF). A HandcraftLogic e montada no
    instante do clique, com o estado daquele momento; WB_Parking enfileira um
    "largar" ANTES da acao de craft; quando ela termina, a revalidacao encontra um
    estado diferente do que foi capturado.

    Se a suspeita estiver certa, o conserto e no estacionamento e nao aqui -- e o
    caso geral e feio: QUALQUER acao cuja validade dependa do estado anterior ao
    estacionamento pode falhar assim.

    ----------------------------------------------------------------------
    COMO ELE RESPONDE A PERGUNTA

    Envolvendo performRecipe e contando o inventario do personagem antes e depois. A
    contagem e o unico jeito de saber, de fora, se performCurrentRecipe() venceu:

        delta > 0   a receita rodou e entregou
        delta <= 0  performCurrentRecipe() devolveu false, ou logic era nulo

    E imprime junto o estado que a suspeita acusa -- maos, carrinho estacionado,
    quantos containers a acao guardou.

    ----------------------------------------------------------------------
    POR QUE NAO ENVOLVE `new`

    Mesmo motivo de WB_CorpseTrace: NetTimedAction.set le o Prototype da funcao `new`
    e usa os NOMES DOS PARAMETROS dela como campos a serializar (offsets 58-141). Um
    envelope tem os parametros dele, e o servidor passaria a reconstruir a acao com
    os campos errados. ISHandcraftAction declara complete(), entao E replicada, e
    quebra-la sairia caro.
]]

local WB_Cart = require "WB_Cart"
local WB_Trace = require "WB_Trace"

require "Entity/TimedActions/ISHandcraftAction"

local WB_CraftTrace = {}

--- @return number quantos itens ha no inventario do personagem, ou -1 sem inventario
local function countInventory(character)
    if character == nil then return -1 end
    local inv = character:getInventory()
    if inv == nil then return -1 end
    return inv:getItems():size()
end

--- @return string o estado que a suspeita do estacionamento acusa
local function describe(self)
    local character = self.character
    if character == nil then return "sem personagem" end

    local primary = character:getPrimaryHandItem()
    local secondary = character:getSecondaryHandItem()
    local parts = {
        string.format("maos=[%s | %s]",
            primary ~= nil and primary:getFullType() or "vazia",
            secondary ~= nil and secondary:getFullType() or "vazia"),
        "carrinhoNaMao=" .. tostring(WB_Cart.is(primary) or WB_Cart.is(secondary)),
    }

    -- Os containers que a acao guardou no new(). Se a logica perdeu de vista uma
    -- fonte de entrada, e por aqui que se ve.
    parts[#parts + 1] = "containers="
        .. tostring(self.containers ~= nil and self.containers:size() or "nil")
    parts[#parts + 1] = "logic=" .. tostring(self.logic ~= nil)
    parts[#parts + 1] = "receita="
        .. tostring(self.craftRecipe ~= nil and self.craftRecipe:getName() or "nil")

    return table.concat(parts, " ")
end

--[[ SOB pcall, e isto nao e paranoia de estilo.

     Este envelope fica no caminho de TODA fabricacao do jogo, do mod e do jogo base.
     Um erro dentro do rastro -- um campo que a proxima B42 renomeie, um getter que
     saia -- derrubaria o craft inteiro do jogador, e o mod seria a causa de um
     defeito que ele so queria observar.

     Instrumentacao permanente que pode quebrar o que observa e pior que nenhuma. Se
     o rastro falhar, ele se cala e a acao segue. ]]
local function safeDescribe(self)
    local ok, text = pcall(describe, self)
    return ok and text or "rastro falhou ao descrever"
end

local function wrap(name)
    local original = ISHandcraftAction[name]
    if original == nil then return end

    ISHandcraftAction[name] = function(self, ...)
        WB_Trace.log("CRAFT", name .. ": " .. safeDescribe(self))
        return original(self, ...)
    end
end

--[[ performRecipe merece tratamento proprio: e o unico ponto em que da para saber
     se a receita venceu, e a resposta so existe comparando antes com depois. ]]
local originalPerformRecipe = ISHandcraftAction.performRecipe
if originalPerformRecipe ~= nil then
    ISHandcraftAction.performRecipe = function(self, ...)
        local okBefore, before = pcall(countInventory, self.character)
        if not okBefore then before = -1 end

        -- A original roda FORA de qualquer pcall: quebrar a fabricacao para proteger
        -- o rastro seria trocar o defeito de lugar.
        local result = { originalPerformRecipe(self, ...) }

        local okAfter, after = pcall(countInventory, self.character)
        if not okAfter then after = -1 end

        local verdict = (before >= 0 and after > before)
            and "ENTREGOU"
            or "NADA -- performCurrentRecipe() devolveu false ou logic era nulo"

        WB_Trace.log("CRAFT", string.format(
            "performRecipe: inventario %d -> %d  %s  [%s]",
            before, after, verdict, safeDescribe(self)))

        return unpack(result)
    end
end

wrap("start")
wrap("perform")
wrap("complete")
wrap("stop")

return WB_CraftTrace
