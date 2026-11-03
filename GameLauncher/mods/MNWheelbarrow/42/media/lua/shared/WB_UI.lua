--[[
    Avisa a interface que a lista de compartimentos mudou.

    O PROBLEMA QUE ISTO RESOLVE: a barra de containers do inventario -- os icones
    ao lado do inventario do personagem -- nao e recalculada a cada quadro. Ela e
    reconstruida em eventos especificos da UI, e mexer nas maos por Lua nao e um
    deles.

    O sintoma era exatamente esse: equipar o carrinho nao fazia o compartimento
    dele aparecer ate o jogador clicar em algo; largar deixava o icone la, tambem
    ate um clique. A lista estava certa por dentro, so nao redesenhada.

    ISInventoryPage.dirtyUI e o helper do proprio jogo para isso, e cuida dos dois
    paineis -- o do personagem e o de saque -- para todos os jogadores em tela
    dividida. E o mesmo caminho que o jogo usa quando uma mochila e vestida.

    POR QUE UM ARQUIVO SO PARA UMA CHAMADA: quem precisa avisar sao as timed
    actions e o WB_Spill, que moram em shared/ e portanto tambem carregam num
    servidor dedicado -- onde ISInventoryPage nao existe. A guarda precisa existir,
    e repeti-la em cinco lugares e o comeco de esquecer dela em um.
]]

local WB_UI = {}

--- Reconstroi a barra de compartimentos. Silenciosa quando nao ha interface.
function WB_UI.refreshContainers()
    if ISInventoryPage == nil or ISInventoryPage.dirtyUI == nil then return end
    ISInventoryPage.dirtyUI()
end

return WB_UI
