--[[
    Uma unica definicao de "isto e um carrinho", e as buscas que dependem dela.

    POR QUE ISTO EXISTE: a mesma funcao estava copiada em tres arquivos --
    WB_Weight, WB_Hands e WB_Move -- e as tres versoes ja tinham divergido em
    detalhes. Um teste de tipo duplicado e o tipo de coisa que so aparece quando
    metade do mod passa a reconhecer um carrinho novo e a outra metade nao.
]]

local WB_Const = require "WB_Const"

local WB_Cart = {}

--- @return boolean se o item e um carrinho
function WB_Cart.is(item)
    if item == nil then return false end
    -- O teste de tipo NAO e precaucao: getFullType existe em InventoryItem, mas
    -- so container tem inventario, e todo chamador daqui vai querer o
    -- inventario logo em seguida.
    if not instanceof(item, "InventoryContainer") then return false end
    return WB_Const.HAULER_TYPES[item:getFullType()] == true
end

--- @return boolean se o personagem esta com um carrinho em alguma das maos
function WB_Cart.inHands(character)
    if character == nil then return false end
    return WB_Cart.is(character:getPrimaryHandItem())
        or WB_Cart.is(character:getSecondaryHandItem())
end

--- @return InventoryItem|nil o carrinho equipado, se houver
function WB_Cart.equipped(character)
    if character == nil then return nil end
    local primary = character:getPrimaryHandItem()
    if WB_Cart.is(primary) then return primary end
    local secondary = character:getSecondaryHandItem()
    if WB_Cart.is(secondary) then return secondary end
    return nil
end

--- Aplica `fn` a cada carrinho DIRETAMENTE dentro do container.
---
--- Sem recursao de proposito: o carrinho nao pode entrar em outro carrinho (ver
--- WB_AcceptItem) e nao cabe numa bolsa, entao um nivel cobre todos os casos
--- reais. Recursao aqui seria custo por evento sem caso de uso.
function WB_Cart.forEachIn(container, fn)
    if container == nil then return end
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if WB_Cart.is(item) then fn(item) end
    end
end

--- Aplica `fn` a cada carrinho largado no chao ao redor do personagem.
---
--- ISTO NAO E CASO DE BORDA, e sim o fluxo principal: o engine so aceita item
--- pesado num container equipado se ele tambem couber no inventario do JOGADOR
--- (medido em ItemContainer.hasRoomFor). Como geladeira e gerador nao cabem,
--- carregar o carrinho exige larga-lo no chao. Varrer so o inventario deixava
--- justamente o caso principal de fora.
---
--- Aplica `fn` a cada ITEM largado no chao ao redor do personagem.
---
--- @param radius number raio em squares
--- @param fn function(item, worldObject, square)
function WB_Cart.forEachItemOnGround(character, radius, fn)
    if character == nil then return end
    local square = character:getSquare()
    local cell = getCell()
    if square == nil or cell == nil then return end

    local px, py, pz = square:getX(), square:getY(), square:getZ()
    for dx = -radius, radius do
        for dy = -radius, radius do
            local sq = cell:getGridSquare(px + dx, py + dy, pz)
            if sq ~= nil then
                local objects = sq:getWorldObjects()
                for i = 0, objects:size() - 1 do
                    local obj = objects:get(i)
                    -- getWorldObjects devolve todo IsoObject da square: piso,
                    -- parede, movel. Chamar getItem() num deles levanta
                    -- "No implementation found", entao o teste de tipo aqui e
                    -- obrigatorio, nao defensivo.
                    if instanceof(obj, "IsoWorldInventoryObject") then
                        local item = obj:getItem()
                        if item ~= nil then fn(item, obj, sq) end
                    end
                end
            end
        end
    end
end

--- Aplica `fn` a cada carrinho largado no chao ao redor do personagem.
---
--- Um FILTRO sobre forEachItemOnGround, e nao uma segunda varredura de squares.
--- WB_Repack precisa dos itens SOLTOS pelo mesmo raio, e ter duas travessias
--- separadas foi exatamente o defeito: a dele olhava so a square do personagem,
--- enquanto o carrinho tombado espalha a carga por ate nove.
---
--- @param radius number raio em squares
function WB_Cart.forEachOnGround(character, radius, fn)
    WB_Cart.forEachItemOnGround(character, radius, function(item, obj, sq)
        if WB_Cart.is(item) then fn(item, obj, sq) end
    end)
end

return WB_Cart
