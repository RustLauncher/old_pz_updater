--[[
    Rastro do caminho do cadaver, que e todo do jogo base.

    NAO E TEMPORARIO. Como todo o resto da instrumentacao deste mod, ele custa uma
    comparacao de booleano quando a caixa de depuracao esta desligada, e a caixa e
    que existe para liga-lo. O dia em que o deposito de cadaver quebrar de novo --
    numa atualizacao da B42, por exemplo -- esta janela ja estara aberta.

    ----------------------------------------------------------------------
    POR QUE ELA PRECISA EXISTIR

    O deposito de cadaver em container e do jogo base, nao nosso:
    ISDropCorpseIntoContainer, em shared/TimedActions/. Ela e replicada -- declara
    complete() --, entao roda dos dois lados, e o mod nao tem visibilidade nenhuma
    dentro dela.

    O sintoma e sempre o mesmo e nao distingue causa: o corpo some do mundo e nao
    aparece no carrinho. Isso e compativel com pelo menos quatro historias
    diferentes, e adivinhar entre elas ja custou rodadas hoje:

      1. o targetContainer que a acao guardou envelheceu -- o estacionamento troca o
         objeto do carrinho, e a acao guarda a referencia no new();
      2. o servidor resolveu targetContainer para OUTRA coisa -- o inventario do
         jogador em vez do compartimento do carrinho, porque o ContainerID foi
         montado quando o carrinho ainda estava na mao;
      3. o bodyCache do servidor nao foi preenchido;
      4. foi preenchido e o handler de deadBody/addBody nao achou o corpo.

    O rastro imprime o targetContainer nos tres momentos que separam as quatro.

    ----------------------------------------------------------------------
    POR QUE NAO ENVOLVE `new`

    Porque envolver `new` QUEBRARIA a replicacao. NetTimedAction.set le o Prototype
    da funcao `new` da tabela da classe e usa os NOMES DOS PARAMETROS dela como
    nomes de campo a serializar (offsets 58-141). Um envelope tem os parametros
    dele, nao os da original, e o servidor passaria a reconstruir a acao com os
    campos errados.

    start, perform e complete sao seguros: o engine os resolve por rawget e chama, e
    um envelope que chama a original preserva tudo -- inclusive a existencia de
    `complete`, que e o interruptor da replicacao.
]]

local WB_Trace = require "WB_Trace"

require "TimedActions/ISDropCorpseIntoContainer"

local WB_CorpseTrace = {}

--- @return string o que este container e, do ponto de vista de quem vai enderecar
---
--- Imprime as tres coisas que o ContainerID consulta para decidir como codificar --
--- o dono, o item que o contem e o objeto de mundo desse item. Sem as tres nao da
--- para saber por que ele resolveu para o lugar errado.
local function describe(container)
    if container == nil then return "nil" end

    local parts = { "tipo=" .. tostring(container:getType() or "?") }

    local holder = container:getContainingItem()
    if holder ~= nil then
        parts[#parts + 1] = string.format("item=%s#%d", holder:getFullType(), holder:getID())
        local worldItem = holder:getWorldItem()
        if worldItem ~= nil then
            local square = worldItem:getSquare()
            parts[#parts + 1] = square ~= nil
                and string.format("mundo=%d,%d,%d",
                    square:getX(), square:getY(), square:getZ())
                or "mundo=SEM_SQUARE"
        else
            parts[#parts + 1] = "mundo=nao"
        end
        parts[#parts + 1] = "containerDoItem="
            .. tostring(holder:getContainer() ~= nil and "sim" or "nao")
    else
        parts[#parts + 1] = "item=nenhum"
    end

    parts[#parts + 1] = "dentro=" .. tostring(container:getItems():size())
    return table.concat(parts, " ")
end

local function wrap(name)
    local original = ISDropCorpseIntoContainer[name]
    if original == nil then return end

    ISDropCorpseIntoContainer[name] = function(self, ...)
        WB_Trace.log("CADAVER", string.format("%s: alvo=[%s] arrastando=%s corpo=%s",
            name, describe(self.targetContainer),
            tostring(self.character ~= nil and self.character:isDraggingCorpse() or false),
            tostring(self.grappledChar ~= nil)))
        return original(self, ...)
    end
end

--[[ Envolvido no carregamento e nao num evento.

     A tabela da classe existe assim que o arquivo dela roda, e LoadDirBase executa
     shared/ em ordem alfabetica -- WB_CorpseTrace vem depois de
     TimedActions/ISDropCorpseIntoContainer. O require acima garante a ordem de
     qualquer jeito.

     Envolver mais tarde, num OnGameStart, perderia o servidor dedicado: la esse
     evento nao dispara. ]]
wrap("start")
wrap("perform")
wrap("complete")

return WB_CorpseTrace
