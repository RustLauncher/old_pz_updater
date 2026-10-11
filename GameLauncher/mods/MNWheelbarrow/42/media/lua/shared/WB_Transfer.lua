--[[
    Sinaliza "o mod esta movendo o carrinho de proposito, nao atrapalhe".

    POR QUE ISTO EXISTE, e por que num arquivo separado:

    WB_Placement mantem a invariante de que o carrinho nunca fica desequipado num
    inventario -- se encontrar um assim, poe no chao. Mas EQUIPAR passa por esse
    estado: o item precisa entrar no inventario antes de ir para a mao, porque no
    PZ a mao e um slot que aponta para um item de la.

    Sem um aviso, a rede nao distingue "estado invalido" de "meio de uma
    transicao valida". O sintoma em jogo foi exato: apertar a tecla de interagir
    teleportava o carrinho para os pes do jogador em vez de equipar.

    O sinalizador vive em shared/ e nao junto da rede porque quem PRECISA
    levanta-lo sao as timed actions, que tambem moram em shared/ -- o servidor
    dedicado carrega as duas. Um require de shared/ para client/ seria codigo
    morto la.

    Contador e nao booleano: acoes podem se aninhar, e um booleano faria a
    primeira a terminar liberar a rede no meio da segunda.
]]

local WB_Transfer = {}

local depth = 0

--- Marca o inicio de um movimento feito pelo mod.
function WB_Transfer.begin()
    depth = depth + 1
end

--- Marca o fim. Sempre em par com begin, inclusive nos caminhos de erro.
function WB_Transfer.finish()
    if depth > 0 then depth = depth - 1 end
end

--- @return boolean se ha movimento do mod em andamento
function WB_Transfer.active()
    return depth > 0
end

return WB_Transfer
