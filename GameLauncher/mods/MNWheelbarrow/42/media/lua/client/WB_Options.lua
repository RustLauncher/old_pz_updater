--[[
    A caixa "Debug mode" em Opcoes -> Mods, e o que ela liga do outro lado.

    ----------------------------------------------------------------------
    POR QUE OPCAO DE MOD E NAO SANDBOX OPTION

    As duas existem no mod e servem a coisas diferentes, e misturar as duas seria
    o comeco de "o jogador mudou e nao aconteceu nada":

      sandbox option  regra do MUNDO, decidida por quem hospeda, igual para todos,
                      fixada na criacao do save. Capacidade, derrame, duracao.
      opcao de mod    preferencia de QUEM JOGA, muda a qualquer momento, so vale
                      na maquina dele. Rastreamento e isso.

    Um interruptor de depuracao que exigisse recriar o save, ou que so o dono do
    servidor pudesse mexer, nao serviria para o uso real: ligar no meio de um teste,
    reproduzir o defeito, desligar.

    ----------------------------------------------------------------------
    PZAPI.ModOptions E VANILLA, e isto e novidade que vale registrar

    Ela mora em media/lua/client/PZAPI/ModOptions.lua e alimenta a aba de mods do
    proprio menu de opcoes -- nao e o mod ModOptions da workshop, e nao ha
    dependencia a declarar. O contrato usado aqui:

        PZAPI.ModOptions:create(id, nome)      -> tabela de opcoes
        opcoes:addTickBox(id, nome, valor, dica)
        PZAPI.ModOptions:getOptions(id):getOption(id):getValue()

    O valor e salvo em ModOptions.ini pelo proprio jogo, entao a escolha sobrevive
    ao fechar o jogo -- inclusive LIGADA, o que e proposital: quem estava depurando
    ontem continua depurando hoje sem procurar a caixa de novo.

    ----------------------------------------------------------------------
    COMO O SERVIDOR FICA SABENDO

    Esta tela nao existe no servidor dedicado: lua/client/ nao e executado la. Entao
    ligar a caixa manda um comando, e o servidor liga o proprio interruptor.

    Ele e reenviado no OnGameStart alem de na mudanca, porque a conexao pode ter
    sido feita DEPOIS da ultima vez que a caixa mudou -- reconectar com a opcao ja
    ligada tem de continuar rastreando, senao o rastro some no exato momento em que
    se estava testando reconexao.
]]

local WB_Const = require "WB_Const"
local WB_Trace = require "WB_Trace"

local WB_Options = {}

local OPTIONS_ID = "MNWheelbarrow"
local TICKBOX_ID = "DebugMode"

--- @return boolean o valor atual da caixa, ou false se a tela nao existir
local function isTicked()
    if PZAPI == nil or PZAPI.ModOptions == nil then return false end
    local options = PZAPI.ModOptions:getOptions(OPTIONS_ID)
    if options == nil then return false end
    local option = options:getOption(TICKBOX_ID)
    if option == nil then return false end
    return option:getValue() == true
end

--- Aplica o valor da caixa aqui e no servidor.
---
--- Chamada tambem pelo gancho `apply` da tela de opcoes, quando o jogador fecha em
--- "Aceitar" -- e ai o envio ao servidor acontece de imediato, porque a essa altura
--- a conexao ja esta estabelecida ha muito.
function WB_Options.apply()
    local on = isTicked()
    WB_Trace.set(on)

    -- So em multiplayer ha outro lado para avisar. Em single player e no processo
    -- que hospeda, o set() acima ja alcancou quem executa a mutacao.
    if isClient() then
        local player = getSpecificPlayer(0)
        if player ~= nil then
            sendClientCommand(player, WB_Const.NET_MODULE, "trace", { on = on })
        end
    end
end

--[[ A TELA E MONTADA NO CARREGAMENTO DO LUA, e nao num evento.

     PZAPI.ModOptions:load() roda dentro de MainOptions e le o ModOptions.ini
     procurando as opcoes JA REGISTRADAS. Registrar tarde -- num OnGameStart, por
     exemplo -- faria a caixa aparecer com o valor padrao e nao com o que o jogador
     escolheu, uma vez a cada partida, ate ele mexer nela. ]]
--[[ SEM getText, e a excecao e deliberada.

     A politica do gerador de traducoes deste mod esta escrita nele: traduz-se
     rotulo CURTO de jogador, e nao texto tecnico, porque chave ausente cai para o
     ingles em silencio enquanto chave ERRADA fica errada para sempre -- e ninguem
     aqui fala tailandes.

     Isto e um interruptor de depuracao. Nao e conteudo de jogo, e traduzi-lo em 23
     idiomas seria risco e manutencao por zero ganho. ]]
if PZAPI ~= nil and PZAPI.ModOptions ~= nil then
    local options = PZAPI.ModOptions:create(OPTIONS_ID, "Wheelbarrow")
    options:addTickBox(TICKBOX_ID, "Debug mode", false,
        "Prints a detailed trace of every wheelbarrow operation to the console, "
        .. "on this client and on the server. Leave off unless you are "
        .. "investigating a problem.")

    -- apply() e o gancho que a tela chama ao fechar com "Aceitar".
    options.apply = function(_self) WB_Options.apply() end
end

--[[ O ENVIO PRECISA INSISTIR, e isto foi medido depois de duas tentativas falharem.

     OnGameStart e OnCreatePlayer disparam no CLIENTE, e os dois podem acontecer
     antes de o SERVIDOR ter associado um jogador aquela conexao. Quando isso ocorre,
     GameServer.receiveClientCommand (offsets 82-93) registra
     "receiveClientCommand: player is null" e volta -- sem disparar OnClientCommand,
     sem erro, sem nada. O comando some.

     Foi exatamente o que aconteceu: o cliente imprimia "rastreamento LIGADO" no
     quadro zero e o servidor nunca recebia. O rastro do servidor so existia por
     causa do padrao ligado no carregamento, que era muleta e nao solucao.

     Entao o envio vira tentativa repetida, espacada, e limitada. Nao ha confirmacao
     do outro lado -- montar um canal de volta para um interruptor de depuracao seria
     desproporcional -- mas tres tentativas ao longo dos primeiros segundos cobrem a
     janela de estabelecimento da conexao com folga. ]]
local RESEND_ATTEMPTS = 3
local RESEND_SPACING = 120

local pending, ticks, nextTick = 0, 0, 0

--- Reagenda o envio. Chamado sempre que o valor pode ter mudado.
local function scheduleResend()
    pending = RESEND_ATTEMPTS
    nextTick = 0
end

Events.OnTick.Add(function()
    if pending <= 0 then return end
    ticks = ticks + 1
    if ticks < nextTick then return end
    nextTick = ticks + RESEND_SPACING
    pending = pending - 1
    WB_Options.apply()
end)

Events.OnGameStart.Add(function()
    WB_Options.apply()
    scheduleResend()
end)

Events.OnCreatePlayer.Add(function(_index, _player)
    WB_Options.apply()
    scheduleResend()
end)

return WB_Options
