--[[
    O carrinho fica TOMBADO quando a manobra e interrompida, e se levanta ao ser
    pego.

    Cancelar ja derramava a carga, mas o carrinho continuava de pe no meio dos
    itens espalhados -- o resultado nao se lia como "tombou", se lia como "os
    itens sairam sozinhos". A inclinacao e o que conta a historia.

    ----------------------------------------------------------------------
    NAO HA ANIMACAO DE QUEDA, e a tentativa de fazer uma fracassou por razao
    estrutural, nao por falta de ajuste.

    O desenho de item no chao e cacheado num ATLAS indexado pelos parametros de
    render, inclusive as rotacoes. Cada angulo distinto vira uma entrada nova, e
    criar a entrada aparece em tela como um PISCA. Uma queda animada e, por
    definicao, uma sequencia de angulos distintos -- ou seja, uma sequencia de
    piscas. Foi exatamente o que apareceu em jogo: "parece baixo fps e ele pisca
    quando atualiza cada posicao".

    Passos maiores diminuem os piscas e pioram a fluidez; passos menores fazem o
    contrario. Nao ha ponto bom nesse eixo, porque o custo E a mudanca de angulo.
    Entao a pose e uma so, aplicada de uma vez.

    ----------------------------------------------------------------------
    COMO O ENGINE DESENHA ITEM NO CHAO

    InventoryItem tem tres rotacoes de mundo, lidas em
    WorldItemAtlas.ItemParams.init:

        worldXRotation  -> angle.x
        worldZRotation  -> angle.y   (a guinada, que WB_Spill usa)
        worldYRotation  -> angle.z

    Duas restricoes saem do bytecode:

    1. O construtor de IsoWorldInventoryObject ZERA worldXRotation e
       worldYRotation. A inclinacao tem de ser aplicada DEPOIS de o objeto
       existir. (A guinada escapa porque o construtor so a sorteia quando ela
       chega negativa.)

    2. Isso vale a cada criacao do objeto, e recarregar o save recria. Por isso o
       estado tombado vive no ModData do ITEM, que persiste, e a rotacao e
       reaplicada por WB_Tipping.restore.
]]

local WB_Spill = require "WB_Spill"
local WB_Trace = require "WB_Trace"

local WB_Tipping = {}

--- Marca no ModData do item. Precisa persistir: a rotacao nao sobrevive ao
--- recarregamento, porque o objeto de mundo e recriado e o construtor a zera.
local TIPPED_KEY = "MNWB_tipped"

--- Modelos de mundo, trocados em runtime por setWorldStaticModel. O de pe
--- tem o quad de sombra; o tombado nao.
local UPRIGHT_MODEL = "MNWheelbarrow_Ground"
local TIPPED_MODEL = "MNWheelbarrow_Tipped"

--- Quanto o carrinho deita, em graus, e a que altura fica na square.
---
--- Medidos em jogo, num laboratorio de teclas que ja cumpriu o papel e saiu. A
--- altura existe como parametro porque deitado o carrinho ocupa outro volume:
--- com zero, parte dele afundava no piso.
local tipAngle = 280.0
local tipHeight = 0.08

--- Correcao de direcao do carrinho TOMBADO, em graus.
---
--- Deitado, ele saia bem fora do que sai de pe, ainda que os dois usem a mesma
--- guinada. O motivo e que inclinar em torno do eixo comprido troca qual
--- face do carrinho aponta para a frente: de pe a referencia e a cacamba, e
--- deitado passa a ser a lateral. A guinada e a mesma; o que muda e o que ela
--- gira.
---
--- Por isso a correcao vive aqui e nao em WB_Spill: ela nao e da colocacao, e da
--- POSE. Carrinho de pe nao precisa dela.
---
--- 105 e medido, nao deduzido -- se fosse so a troca de face seria 90 redondo. Os
--- 15 a mais vem de a inclinacao nao ser 90 exatos: a 280 o carrinho fica
--- apoiado, nao perfeitamente deitado, e a face de referencia gira um pouco
--- junto. Mexer na inclinacao pede remedir isto.
local tipYawOffset = 105.0

--- Inclina o carrinho no eixo LOCAL dele.
---
--- QUAL EIXO USAR NAO E ESCOLHA, e sim consequencia da ordem em que o engine
--- compoe as rotacoes. O atlas monta a matriz com Matrix4f.rotateXYZ, que aplica
--- X, depois Y, depois Z -- e o mapeamento e
---
---     angle.x = worldXRotation
---     angle.y = worldZRotation   (a guinada)
---     angle.z = worldYRotation
---
--- Entao worldXRotation entra DEPOIS da guinada, em espaco de MUNDO, enquanto
--- worldYRotation entra ANTES, no espaco do proprio carrinho. Por isso inclinar
--- em X fazia a direcao da queda depender de para onde o carrinho apontava --
--- era world-space -- e por isso inclinar em Y e consistente de graca.
---
--- Duas tentativas anteriores morreram por nao saber disto: inclinar so em X
--- (tombava na diagonal) e depois espalhar o angulo entre X e Y por seno e
--- cosseno. A segunda e matematicamente invalida: rotacao nao se decompoe como
--- vetor, so vale para angulo infinitesimal, e a 50 graus ja gira torto. Nada
--- disso e necessario -- basta usar o eixo local.
---
--- De quebra some a explosao de entradas de atlas: como a inclinacao nao depende
--- mais da guinada, existe UM valor de angulo, e nao um por direcao.
local function applyAngle(cart, degrees)
    cart:setWorldXRotation(0.0)
    cart:setWorldYRotation(degrees)
end

--- @return boolean se o carrinho esta marcado como tombado
function WB_Tipping.isTipped(cart)
    return cart ~= nil and cart:hasModData()
        and cart:getModData()[TIPPED_KEY] == true
end

--- Poe o carrinho no chao JA TOMBADO.
---
--- Faz a colocacao inteira em vez de so inclinar um carrinho que ja esta la, e o
--- motivo e a ALTURA: o deslocamento vertical so pode ser dado em
--- AddWorldInventoryItem, na criacao do objeto. Inclinar sem poder ajustar a
--- altura deixaria o carrinho enterrado no piso, sem conserto possivel.
function WB_Tipping.dropTipped(character, cart, square)
    if character == nil or cart == nil then return end
    WB_Trace.item("TOMBO", "dropTipped", cart, character)

    cart:getModData()[TIPPED_KEY] = true
    -- Modelo SEM o quad de sombra: assada na malha, ela inclinaria junto e
    -- viraria uma mancha de contato de pe no ar.
    cart:setWorldStaticModel(TIPPED_MODEL)

    -- A colocacao e de WB_Spill, e nao feita aqui. Quando este arquivo montava a
    -- propria, ele esqueceu de definir a DIRECAO, e o carrinho tombado apontava
    -- para qualquer lado enquanto o de pe apontava certo.
    local placed, container = WB_Spill.placeOnGround(character, cart, square, tipHeight)
    if not placed then return end

    -- Sempre depois da criacao: o construtor zera as duas rotacoes de inclinacao.
    applyAngle(cart, tipAngle)
    -- A guinada, ao contrario, sobrevive a criacao -- so e sorteada quando chega
    -- negativa. Aqui ela ja veio da direcao do personagem, e so recebe a correcao
    -- da pose deitada.
    cart:setWorldZRotation((cart:getWorldZRotation() + tipYawOffset) % 360)

    -- SO AGORA a rede pode saber, e este e o motivo de WB_Spill.placeOnGround nao
    -- transmitir sozinho: as tres rotacoes viajam dentro do item serializado, e as
    -- duas que fazem a pose acabaram de ser escritas. Anunciar antes mandaria um
    -- carrinho de pe para todo mundo, e o tombo existiria so aqui.
    WB_Spill.settle(character, cart, container)
end

--- Devolve o carrinho a posicao normal. Idempotente.
function WB_Tipping.reset(cart)
    if cart == nil then return end
    if cart:hasModData() then
        cart:getModData()[TIPPED_KEY] = nil
    end
    cart:setWorldStaticModel(UPRIGHT_MODEL)
    cart:setWorldXRotation(0.0)
    cart:setWorldYRotation(0.0)
end

--- Reaplica a inclinacao de um carrinho que ja estava tombado.
---
--- Necessario porque o construtor do objeto de mundo zera as rotacoes, e ele
--- roda de novo a cada recarregamento do save ou retorno do chunk. Sem isto, um
--- carrinho tombado se levantaria sozinho ao voltar ao jogo.
function WB_Tipping.restore(cart)
    if not WB_Tipping.isTipped(cart) then return end

    -- O modelo tambem nao sobrevive ao recarregamento: e estado de runtime.
    cart:setWorldStaticModel(TIPPED_MODEL)

    if math.abs(cart:getWorldYRotation()) < 0.5 then
        applyAngle(cart, tipAngle)
    end
end

return WB_Tipping
