--[[
    O carrinho REACONDICIONA a carga: item dentro pesa uma fracao, item fora pesa o
    que sempre pesou.

    ======================================================================
    POR QUE ISTO EXISTE

    A capacidade de um container que pertence a um ITEM tem teto de 50, imposto no
    LEITOR e nao no escritor:

        ItemContainer.getCapacity():
            if getVehiclePart() ~= nil                 -> min(cap, 1000)
            if containingItem instanceof InventoryItem -> min(cap, 50)   <- nos
            senao                                      -> min(cap, 100)

    setCapacity(200) grava 200 e getCapacity() devolve 50. O unico discriminante e
    ser container de item; nao ha tipo, tag ou campo que mude isso. Os mods que furam
    esse limite substituem o ItemContainer.class recompilado -- travam numa versao
    exata do jogo e nem funcionam em servidor, que tem teto proprio.

    Se a capacidade nao pode subir, o peso do conteudo desce. getCapacityWeight()
    soma getActualWeight() de cada item, e setActualWeight e publico.

    ======================================================================
    AS TRES REGRAS QUE FAZEM ISTO SER SEGURO

    1. O VALOR VEM DO SCRIPT, NUNCA DO ESTADO ANTERIOR.

       peso dentro = getScriptItem():getActualWeight() * FACTOR
       peso fora   = getScriptItem():getActualWeight()

       Nunca "peso atual * FACTOR". Isso torna a operacao IDEMPOTENTE: rodar duas
       vezes, dez vezes ou depois de trocar o FACTOR da o mesmo resultado. Sem isso,
       duas passadas comprimiriam o item a 0.04 do peso e a terceira a 0.008.

    2. A MARCA E UM BOOLEANO, NAO UM VALOR.

       O ModData do item guarda apenas "eu mexi neste". Se ela se perder, o item fica
       leve -- ruim, mas recuperavel. Se guardasse o peso original e o valor
       estivesse errado uma vez, o peso real estaria perdido PARA SEMPRE. Guardar o
       minimo e o que limita o dano do pior caso.

    3. SO REACONDICIONA ITEM CUJO PESO E O DO SCRIPT.

       Bebida pela metade, comida mordida e item alterado por outro mod tem peso
       legitimamente diferente do script. Restaurar "para o script" apagaria esse
       estado. Entao item cujo peso atual nao bate com o script fica intocado: ele
       ocupa o peso real e ninguem se machuca.

    ======================================================================
    POR QUE RECONCILIACAO POR REGIAO, E NAO GANCHO POR SAIDA

    Um item pode sair do carrinho por arrastar, menu de contexto, pegar tudo, largar
    no chao, tombamento, morte do jogador, fabricacao, outro jogador em MP, menu de
    debug, ou por um mod que nem existe hoje. Enumerar saidas e uma lista que envelhece
    -- e este arquivo existe justamente porque a regra NAO pode ser furada por uma via
    imprevista.

    Entao nao ha ganchos de saida. Ha uma INVARIANTE, reafirmada sobre uma regiao:

        item marcado dentro de um hauler  -> peso = script * FACTOR
        item marcado fora de um hauler    -> peso = script, e a marca sai

    A regiao e "onde o item obrigatoriamente esta depois de sair": o inventario do
    jogador (recursivo), os carrinhos por perto, e o chao ao redor. Qualquer saida
    iniciada por um jogador aterrissa em um desses tres, seja qual for o codigo que a
    executou.

    NAO usamos o container que OnContainerUpdate entrega: ISInventoryPage o recebe,
    mas forageSystem dispara o mesmo evento SEM argumento. Depender do parametro seria
    depender de quem disparou.

    ======================================================================
    O PESO ALTERADO NAO VAI PARA O SAVE, e isso e a maior garantia daqui

    setActualWeight escreve no campo `actualWeight`, e ele NAO e serializado -- o
    save/load de InventoryItem so toca `customWeight`. Conferido no bytecode.

    Consequencia: qualquer item que escape leve volta ao peso do script no proximo
    carregamento, sozinho, sem varredura nenhuma. Corrupcao permanente de peso e
    impossivel por construcao, e a janela do pior caso e uma sessao.

    Isso tambem significa que ao carregar um save o conteudo do carrinho volta ao peso
    cheio por um instante, e a varredura o reacondiciona -- por isso ela roda em
    OnGameStart e OnCreatePlayer, e nao so em mudanca de container.

    ======================================================================
    LIMITE CONHECIDO

    Item que saia para um container distante, sem jogador por perto, continua leve ate
    voltar a uma regiao varrida OU o save ser recarregado -- o que vier primeiro.

    MULTIPLAYER NAO ESTA VERIFICADO. O peso nao e serializado, entao provavelmente nao
    e sincronizado: cada cliente reacondicionaria localmente. Mas as varreduras aqui
    partem do jogador local, e num servidor dedicado nao ha jogador local -- o servidor
    veria os pesos cheios. Se ele revalidar transferencias, a capacidade divergiria.
    Nao afirme suporte a MP para este mecanismo sem testar num servidor.
]]

local WB_Cart = require "WB_Cart"
local WB_Sandbox = require "WB_Sandbox"

local WB_Repack = {}

--- Marca de "este item esta reacondicionado". Booleano, nunca um peso -- ver a
--- regra 2 no cabecalho.
local MARK = "MNWB_repacked"

--- Fracao do peso real que o item ocupa dentro do carrinho.
---
--- 0.2 foi escolhido contra um teto de 50 que nao era o teto -- o calculo original
--- dizia "25 troncos sao 225 de peso real, 225 * 0.2 = 45, cabe nos 50 com folga".
--- O teto real e o orcamento de peso da SQUARE, e depois de descontar o carrinho e a
--- margem do item que entra ele vale 38 (ver WB_Weight.floorCeiling).
---
--- O numero ficou porque o resultado MEDIDO em jogo e bom: 21 troncos entram e a
--- barra le 37.8 de 38 -- cheia exatamente quando o jogo para de aceitar. Mexer no
--- fator agora mudaria o balanceamento publicado sem necessidade.
local FACTOR = 0.2

--- Profundidade maxima da descida por containers aninhados.
---
--- Nao e paranoia: isto roda a cada mudanca de container, e estouro de pilha num
--- handler desses derruba o jogo inteiro em vez de falhar sozinho. WB_Legacy escolheu
--- o mesmo 3 pelo mesmo motivo, e nenhuma arvore real de inventario passa disso.
local MAX_DEPTH = 3

--- @return number|nil peso canonico do script, ou nil se nao houver
local function scriptWeight(item)
    local script = item ~= nil and item:getScriptItem()
    if script == nil then return nil end
    return script:getActualWeight()
end

--- @return boolean se este item pode ser reacondicionado sem perder estado
---
--- Regra 3 do cabecalho. Bebida, comida e roupa tem peso que muda com o uso, e um
--- item alterado por outro mod tambem. Se o peso atual nao e o do script, nao ha como
--- restaurar depois sem inventar um numero.
local function repackable(item)
    if item == nil then return false end

    local real = scriptWeight(item)
    if real == nil or real <= 0 then return false end

    --[[ SO CARGA PESADA. O reacondicionamento existe para vencer o teto de 50 no que
         e pesado; item leve nao precisa dele e nao deve receber.

         Duas razoes. O teto de carga leve (LightCapacity, ver WB_AcceptItem) e medido
         em peso REAL, entao comprimir item leve nao aumentaria quanta tralha cabe --
         seria so trabalho. E cada item tocado e uma chance de vazamento: restringir ao
         que precisa reduz a superficie do unico risco real deste arquivo. ]]
    if real < WB_Sandbox.get("HeavyThreshold") then return false end

    -- Peso que muda com o uso: comprimir apagaria esse estado na restauracao, porque
    -- o valor de volta vem do script. Ver a regra 3 no cabecalho.
    if instanceof(item, "DrainableComboItem") then return false end
    if instanceof(item, "Food") then return false end
    if instanceof(item, "Clothing") then return false end
    if WB_Cart.is(item) then return false end

    local marked = item:hasModData() and item:getModData()[MARK] == true
    if marked then return true end
    -- Ainda nao mexemos: so aceita se o peso for exatamente o do script.
    return math.abs(item:getActualWeight() - real) < 0.001
end

--- @return number o peso REAL do item, ignorando o reacondicionamento
---
--- Existe para WB_Weight e WB_AcceptItem: os dois classificam pesado e leve, e um
--- tronco reacondicionado pesa 1.8, que cairia como carga leve e perderia a reducao
--- de peso -- invertendo justamente o que o mod faz.
function WB_Repack.realWeight(item)
    if item == nil then return 0 end
    if item:hasModData() and item:getModData()[MARK] == true then
        return scriptWeight(item) or item:getActualWeight()
    end
    return item:getActualWeight()
end

local function repack(item)
    local real = scriptWeight(item)
    if real == nil then return end
    -- Derivado do SCRIPT, e nao do peso atual: e o que torna isto idempotente.
    item:setActualWeight(real * FACTOR)
    item:getModData()[MARK] = true
end

local function restore(item)
    local real = scriptWeight(item)
    if real ~= nil then item:setActualWeight(real) end
    if item:hasModData() then item:getModData()[MARK] = nil end
end

--[[ Reafirma a invariante num container, descendo pela arvore.

     O ESTADO "dentro" E DECIDIDO NA DESCIDA, e nao pelo chamador. Ao entrar num item
     que e um hauler, `inside` passa a ser verdadeiro para tudo abaixo dele.

     A primeira versao recebia `inside` do chamador e tinha um defeito grave por isso:
     o carrinho EQUIPADO vive dentro do inventario do jogador, entao a passada que
     varria o inventario com inside=false descia no carrinho e RESTAURAVA o conteudo
     dele -- desfazendo o reacondicionamento. E rodava depois da passada que
     reacondicionava, entao ganhava. Carrinho na mao perdia o efeito inteiro.

     Decidir na descida tambem eliminou as passadas separadas por carrinho: uma
     varredura do inventario do jogador ja cobre carrinho na mao e bolsa dentro do
     carrinho, na profundidade que existir.

     @param inside boolean se algum ancestral ja e um hauler ]]
local function reconcile(container, inside, depth)
    depth = depth or 0
    if container == nil or depth > MAX_DEPTH then return end

    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)

        --[[ Um `elseif` cobre os tres casos, e o terceiro nao e obvio:

               dentro e reacondicionavel  -> comprime (rederivado, idempotente)
               dentro e marcado, mas ja NAO reacondicionavel -> restaura
               fora e marcado -> restaura

             O do meio acontece se o limite de peso pesado subir na sandbox: um item
             marcado que passou a contar como leve ficaria comprimido para sempre
             dentro do carrinho, porque a restauracao so olhava quem estava fora. ]]
        if inside and repackable(item) then
            repack(item)
        elseif item:hasModData() and item:getModData()[MARK] == true then
            restore(item)
        end

        if instanceof(item, "InventoryContainer") then
            reconcile(item:getInventory(), inside or WB_Cart.is(item), depth + 1)
        end
    end
end

--- Reafirma a invariante no que o jogador carrega.
---
--- Cobre carrinho na mao, bolsa dentro do carrinho e qualquer item marcado que tenha
--- acabado de sair para o inventario -- os destinos de toda saida iniciada por quem
--- esta segurando as coisas.
function WB_Repack.sweepCarried(character)
    if character == nil then return end
    reconcile(character:getInventory(), false)
end

--- Reafirma a invariante nos carrinhos e itens largados ao redor.
---
--- Separado de sweepCarried porque varrer o chao custa uma varredura de squares, e
--- WB_Weight ja decidiu estrangular isso -- esta funcao e chamada de dentro do trecho
--- estrangulado, e nao a cada mudanca de container.
---
--- @param radius number raio em squares
function WB_Repack.sweepGround(character, radius)
    if character == nil then return end

    WB_Cart.forEachOnGround(character, radius, function(cart)
        reconcile(cart:getInventory(), true)
    end)

    --[[ Itens soltos pelo MESMO raio dos carrinhos.

         A primeira versao olhava so a square do personagem, e isso deixou passar o
         caso mais visivel: o carrinho tombado ESPALHA a carga por ate nove squares
         (WB_Spill.dump respeita um limite de peso por square). Os troncos ficavam
         comprimidos no chao ate alguem pega-los.

         O erro de fundo era duplicacao: WB_Cart ja sabia varrer squares por raio e eu
         escrevi uma segunda travessia, pela metade. Agora as duas passam por
         forEachItemOnGround. ]]
    WB_Cart.forEachItemOnGround(character, radius, function(item)
        if not WB_Cart.is(item)
            and item:hasModData() and item:getModData()[MARK] == true then
            restore(item)
        end
    end)
end

--[[ Reacondiciona UM item, o que esta ENTRANDO no carrinho.

     Existe para o portao de entrada. O engine mede o item que entra pelo peso de
     FORA -- 9.0 para um tronco -- e compara com a capacidade do carrinho, mas la
     dentro ele vai pesar 1.8. Sem isto, o jogador ve 30.6 de 38 na barra, sobrando
     7.4, e o jogo recusa mesmo assim: a conta usou 9.0.

     Reacondicionar aqui faz a comparacao usar o peso que o item VAI TER, que e a
     unica versao honesta dela.

     E se a transferencia acabar recusada por outro motivo, o item fica comprimido
     fora de um carrinho -- estado que a invariante de reconcile ja desfaz sozinha,
     porque "item marcado fora de um hauler -> restaura" e uma das tres regras dela.
     Nao ha caminho novo a manter.

     @param item InventoryItem ]]
function WB_Repack.repackIncoming(item)
    if item == nil then return end
    if not repackable(item) then return end
    repack(item)
end

--- Reafirma a invariante dentro de UM carrinho.
---
--- As outras duas varreduras partem de um personagem. Esta parte do carrinho, e
--- existe para o portao de entrada: MNWheelbarrow.AcceptItem precisa dos numeros em
--- dia no instante em que o engine decide, e ali o que se tem em mao e o container,
--- nao o dono dele.
---
--- REMOVIDA EM 16/08/2026 E RESTAURADA NO MESMO DIA. A remocao argumentava que
--- reacondicionar o item que ENTRA tornava a varredura redundante, porque nenhum
--- item chegaria cru la dentro. O argumento supoe que todo item entra pelo portao, e
--- isso e falso -- foi MEDIDO no mesmo dia que o engine consulta o portao em alguns
--- caminhos e nao em outros (ver secao 5 do HANDOFF-MP). Item que entra por um caminho
--- sem portao fica cru ate a proxima batida do relogio, o peso do conteudo incha, e a
--- comparacao de capacidade recusa cedo. Sintoma medido: uma leva de 20 troncos
--- parava em 17, e um a um depois enchia ate 21.
---
--- @param cart InventoryItem
function WB_Repack.sweepCart(cart)
    if not WB_Cart.is(cart) then return end
    reconcile(cart:getInventory(), true)
end

return WB_Repack
