--[[
    Identificadores do mod. NENHUM numero de balanceamento entra aqui.

    Regra rigida: tudo que o jogador pode ajustar mora em sandbox-options.txt e
    so la. Este arquivo guarda nomes e chaves -- coisas que, se mudassem,
    quebrariam saves ou o contrato com os scripts .txt.

    Havia aqui uma constante ENGINE_CAPACITY_CEILING = 50, e ela estava ERRADA.
    Ver WB_Weight.lua: o bytecode de ItemContainer.setCapacity mostra que 50 e
    apenas o limiar de um aviso de debug, nao um teto imposto.
]]

local WB_Const = {}

--- Itens que se comportam como carrinho.
---
--- NAO usamos hasTag() aqui. Na B42 a assinatura e hasTag(ItemTag), e passar
--- uma string levanta "No implementation found for function: hasTag(...,
--- java.lang.String)" -- o padrao hasTag("nome") que se ve em mods antigos e de
--- B41.
---
--- Um registro por fullType entrega o mesmo que a tag entregaria: adicionar um
--- segundo carrinho (de supermercado, carroca) e acrescentar uma linha de dado
--- aqui, sem tocar em logica nenhuma.
---
--- A linha `Tags = MNWheelbarrow:mnwbHauler` continua no script do item de
--- proposito: nao custa nada e deixa outros mods detectarem o carrinho.
--- O carrinho do mod. Nomeado porque o spawner precisa criar o item por tipo, e
--- uma segunda copia desta string e uma divergencia esperando acontecer.
WB_Const.CART_TYPE = "MNWheelbarrow.Wheelbarrow"

WB_Const.HAULER_TYPES = {
    [WB_Const.CART_TYPE] = true,
}

--- Namespace das sandbox options. Precisa bater com o "page" e com o prefixo
--- dos nomes de option em sandbox-options.txt.
WB_Const.SANDBOX_NS = "MNWheelbarrow"

--- Quantas squares de distancia ainda contam como "o carrinho esta aqui".
---
--- Uma pergunta, uma resposta. Este numero ja existiu em TRES lugares com tres
--- nomes -- o alcance do estacionamento, o raio da limpeza de objeto obsoleto e o
--- da busca do carrinho vivo -- e os tres respondiam exatamente a mesma coisa:
--- "o carrinho que o servidor acabou de mexer esta ao alcance do braco?".
---
--- Tres copias de um numero e como duas ideias de "cabe aqui" nasceram neste mod
--- antes, e aquela deixou carga cair debaixo de carro.
---
--- Dois e o alcance do braco mais uma square de folga, porque a colocacao pode
--- escolher a vizinha quando a square pedida esta ocupada -- ver pickSquare.
WB_Const.CART_REACH = 2

--[[ Tipo que o compartimento do carrinho anuncia ao engine.

     NAO E COSMETICO. ItemContainer.canHumanCorpseFit termina em "o meu getType()
     esta nesta lista?", e a lista e fixa no engine: bin, cardboardbox, crate,
     militarycrate, clothingdryer, clothingwasher, coffin, doghouse, dumpster,
     fireplace, fridge, freezer, locker, militarylocker, postbox, shelter, tent,
     wardrobe. Compartimento que nasce de item nunca esta nela.

     "crate" e o analogo honesto: caixa aberta em que se despeja coisa. O tipo so e
     lido para escolher IGUI_ContainerTitle_<tipo>, e esse caminho nao vale para
     container que vem de item -- ali o titulo e o nome do item.

     POR QUE VIVE AQUI E NAO SO EM WB_Corpse: porque precisa valer nos DOIS
     processos, e WB_Corpse mora em client/. O servidor mantinha o tipo original, e
     dai o defeito medido em 16/08/2026 -- o cliente via "crate", aceitava e tirava o
     corpo do mundo; o servidor via "Wheelbarrow", canHumanCorpseFit recusava,
     becomeCorpseItem devolvia nulo, e o cadaver deixava de existir. ]]
WB_Const.CORPSE_CONTAINER_TYPE = "crate"

--- Modulo dos comandos cliente->servidor (sendClientCommand / OnClientCommand).
---
--- O modulo e conferido em TODO handler antes do nome do comando: OnClientCommand
--- dispara para o trafego de todos os mods, e "trace" ou "park" sao nomes que
--- outro mod pode ter escolhido tambem.
WB_Const.NET_MODULE = "MNWheelbarrow"

--- Rooms onde o carrinho pode aparecer solto no mundo. Nomes reais da lista de
--- rooms da B42. Ainda nao usado -- e a Fase E do plano.
WB_Const.SPAWN_ROOMS = {
    construction = true,
    warehouse = true,
    storageunit = true,
    shed = true,
    garage = true,
    garagestorage = true,
    toolstore = true,
    toolstorestorage = true,
    loggingwarehouse = true,
    factorystorage = true,
    metalfabricationstorage = true,
}

--- Chave de ModData que marca chunks ja processados pelo spawner, para o mesmo
--- lugar nunca gerar dois carrinhos. Fase E.
WB_Const.MODDATA_SPAWN_KEY = "MNWheelbarrow_spawnedChunks"

return WB_Const
