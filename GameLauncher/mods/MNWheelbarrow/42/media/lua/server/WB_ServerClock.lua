--[[
    O relogio que refaz, no servidor, a contabilidade que o mod so refazia no
    cliente.

    ----------------------------------------------------------------------
    O QUE ESTAVA ERRADO, medido em jogo e nao suposto

    Carregar 20 troncos punha 18 e recusava 2. O rastro do servidor, durante o
    carregamento e na linha seguinte:

        [PEGAR] complete:    dentro=18 itens/162.0 peso  cap=50  reducao=0%
        [MAO] toHands saida: dentro=18 itens/162.0 peso  cap=50  reducao=95%

    Tres coisas erradas ao mesmo tempo, e e o servidor quem valida a transferencia:

    1. REDUCAO PARADA EM ZERO durante todo o carregamento. Ela so virou 95% na
       linha seguinte, quando o carrinho voltou para a mao. A causa esta nos
       gatilhos de WB_Weight: todos sao eventos de cliente
       (OnContainerUpdate, OnRefreshInventoryWindowContainers, OnGameStart,
       OnCreatePlayer) menos OnEquipPrimary/Secondary, que disparam
       incondicionalmente -- e sao os unicos que alcancam o servidor. Ou seja, a
       conta era refeita quando as MAOS mudavam e nunca quando o CONTEUDO mudava.

    2. PESO BRUTO. 18 troncos x 9.0 = 162, e nao os 32.4 que o cliente via. O
       reacondicionamento vive em setActualWeight, que NAO e serializado -- decisao
       da secao 11 do HANDOFF, tomada de proposito: um item que escape leve volta ao peso
       do script sozinho, e corrupcao permanente de peso fica impossivel por
       construcao. O preco e este: o servidor precisa refazer a conta dele.

    3. Capacidade 50, nao 200 -- o teto do engine na leitura. Esse nao tem conserto
       e nao e deste arquivo; esta medido em WB_Weight.

    Daqui sai a licao que vale para o resto do porte: nao basta o codigo estar em
    shared/. Se todos os GATILHOS dele forem de cliente, ele nao roda no servidor,
    e a diferenca so aparece quando o servidor precisa decidir alguma coisa.

    ----------------------------------------------------------------------
    POR QUE OnTick E NAO OUTRO EVENTO

    A lista do que dispara no servidor dedicado e curta -- OnTick, LoadGridsquare,
    OnClientCommand, EveryOneMinute e as outras de tempo de jogo. As de tempo sao
    grossas demais: um minuto de jogo passa varias transferencias.

    OnTick com contador e o idioma do proprio jogo base para isto; ver
    server/Foraging/forageServer.lua:455-502, que faz exatamente a mesma coisa com
    getOnlinePlayers.

    ----------------------------------------------------------------------
    POR QUE AO REDOR DOS JOGADORES E NAO O MUNDO INTEIRO

    Um carrinho que ninguem esta usando nao precisa de conta atualizada. Ela precisa
    estar certa ANTES da primeira transferencia ser validada -- e para isso basta o
    jogador estar por perto, porque ele precisa estar por perto para transferir.

    Varrer todos os chunks carregados custaria proporcional ao mapa carregado e nao
    ao numero de jogadores, para cobrir carrinhos que ninguem esta olhando.
]]

local WB_Cart = require "WB_Cart"
local WB_Repack = require "WB_Repack"
local WB_Trace = require "WB_Trace"
local WB_Weight = require "WB_Weight"

local WB_ServerClock = {}

--- De quantos em quantos ticks a varredura acontece.
---
--- Trinta ticks e por volta de meio segundo. O numero nao precisa ser preciso: ele
--- so tem de ser MENOR que o intervalo entre o jogador chegar perto de um carrinho
--- e a primeira transferencia dele ser validada, e qualquer coisa abaixo de um
--- segundo cumpre isso com folga.
local EVERY_TICKS = 30

--- Raio da varredura, em squares.
---
--- NAO e WB_Const.CART_REACH, e a diferenca e proposital. Aquele responde "o
--- carrinho esta ao alcance do braco"; este responde "o carrinho esta perto o
--- bastante para o jogador comecar a mexer nele antes da proxima varredura". Dez
--- squares dao meio segundo de caminhada de folga.
local RADIUS = 10

local ticks = 0

--- Refaz a conta de um carrinho: primeiro o peso, depois a capacidade.
---
--- A ORDEM IMPORTA. WB_Weight classifica pesado e leve por WB_Repack.realWeight, e
--- a reducao que ele calcula depende de o conteudo estar reacondicionado ou nao. Ao
--- contrario, a marca de reacondicionado nao depende da reducao. Entao reacondiciona
--- primeiro e conta depois.
local function refreshFor(player)
    -- O que ele carrega: cobre o carrinho na mao e o que esta dentro dele.
    WB_Repack.sweepCarried(player)
    WB_Weight.refreshPlayer(player)

    -- O que esta no chao ao redor: e o caso normal em multiplayer, porque carregar
    -- o carrinho exige larga-lo -- ver o estacionamento em WB_Parking.
    WB_Repack.sweepGround(player, RADIUS)
    WB_Cart.forEachOnGround(player, RADIUS, function(cart)
        WB_Weight.refresh(cart)
    end)
end

function WB_ServerClock.tick()
    ticks = ticks + 1
    if ticks < EVERY_TICKS then return end
    ticks = 0

    --[[ getOnlinePlayers, e nao getNumActivePlayers.

         getNumActivePlayers/getSpecificPlayer so enxergam a tela LOCAL -- no maximo
         quatro, em tela dividida, e ZERO num servidor dedicado. Quem lista jogadores
         no servidor e getOnlinePlayers. Trocar um pelo outro faz este arquivo inteiro
         nao fazer nada, em silencio. ]]
    local players = getOnlinePlayers()
    if players == nil then return end

    for i = 0, players:size() - 1 do
        local player = players:get(i)
        if player ~= nil and not player:isDead() then
            refreshFor(player)
        end
    end
end

--[[ SO NO SERVIDOR, e a guarda nao e a de autoridade.

     lua/server/ NAO e do servidor -- GameLoadingState.enter() carrega "server" no
     cliente tambem. E aqui a guarda certa e isServer() e nao WB_MP.isAuthority(),
     porque as duas respondem coisas diferentes:

         isAuthority()  single player TAMBEM
         isServer()     so quem hospeda

     Em single player os eventos de cliente de WB_Weight e WB_Repack ja fazem este
     trabalho, e a cada mudanca de container em vez de a cada trinta ticks. Rodar o
     relogio la seria refazer, meio segundo depois, uma conta que ja esta certa.

     Quem HOSPEDA cai deste lado e isso e proposital: os eventos de cliente dele
     cobrem o proprio jogador, mas nao os carrinhos dos outros. ]]
if isServer() then
    Events.OnTick.Add(WB_ServerClock.tick)
    WB_Trace.log("RELOGIO", string.format(
        "relogio de servidor ligado: a cada %d ticks, raio %d", EVERY_TICKS, RADIUS))
end

return WB_ServerClock
