--[[
    Uma unica resposta para "quem sou eu" e "de quem e este personagem".

    POR QUE ISTO EXISTE: as duas perguntas apareceram em cinco arquivos ao mesmo
    tempo durante o porte para multiplayer, e as duas tem uma resposta contra-
    intuitiva o bastante para divergir na terceira copia.

    ----------------------------------------------------------------------
    AUTORIDADE

        isServer()  ->  GameServer.server   (so o processo de servidor dedicado)
        isClient()  ->  GameClient.client   (so o processo de cliente MP)

    Medido em LuaManager$GlobalObject: os dois sao um getstatic e um ireturn.
    Em single player os DOIS sao falsos -- e por isso `isServer()` sozinho nao
    serve como "sou quem decide": ele deixa o single player de fora.

    `not isClient()` cobre os dois casos que interessam, e so eles:

        single player      -> true    (nao ha outro lado)
        servidor dedicado  -> true    (e ele quem decide)
        cliente MP         -> false   (quem decide esta do outro lado)

    ----------------------------------------------------------------------
    JOGADOR LOCAL

    setPrimaryHandItem e setSecondaryHandItem NAO transmitem nada sozinhos, mas
    disparam OnEquipPrimary/OnEquipSecondary incondicionalmente. E
    EquipPacket.parse os chama no cliente PARA JOGADORES REMOTOS.

    Sem esta guarda, todo handler que MUDA estado passa a mudar o estado de outro
    jogador na sua maquina. O caso pior e a invariante R4 de WB_Placement, que
    tira o carrinho do inventario e larga no chao: a sincronizacao do inventario
    de um jogador remoto passa OBRIGATORIAMENTE pelo estado "carrinho no
    inventario, ainda nao nas maos".

    A guarda e a do jogo base (ISVehicleDashboard, ISTimedActionQueue).
]]

local WB_MP = {}

--- @return boolean se este processo e quem decide a verdade do mundo
function WB_MP.isAuthority()
    return not isClient()
end

--- @return boolean se este personagem e um jogador desta maquina
---
--- instanceof antes de isLocalPlayer nao e defensividade: OnEquipPrimary tambem
--- dispara para zumbi e para animal, e isLocalPlayer nao existe neles.
function WB_MP.isLocalPlayer(character)
    return character ~= nil
        and instanceof(character, "IsoPlayer")
        and character:isLocalPlayer()
end

--- Chave estavel para tabelas indexadas por jogador.
---
--- getPlayerNum() e o indice de TELA, e vale 0 para TODO jogador remoto num
--- cliente -- ou seja, uma colisao garantida assim que dois jogadores existem.
--- O idioma e o de FishingHandler.lua:23.
---
--- @return string|number chave unica por jogador
function WB_MP.playerKey(character)
    if character == nil then return -1 end
    if isMultiplayer() then
        local name = character:getUsername()
        if name ~= nil then return name end
    end
    return character:getPlayerNum()
end

return WB_MP
