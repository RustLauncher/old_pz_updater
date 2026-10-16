# Remoção segura das aparências VINI — Build 42.21

Este procedimento se aplica a Coca-Cola ICE, Monster, Redbull, Pepsi e Dr Pepper. O suporte incluído chama-se **VINI Furniture Recovery [B42]**, Mod ID `ViniFridgeRecovery`, e requer **Build 42.21**, conforme seu `mod.info`. Não presuma que essa cópia do suporte funcione em versões anteriores.

## Português

**Desativar a aparência e reiniciar não basta para um save que já contém móveis personalizados. Colocar a porcentagem em 0% ou visitar uma sala também não converte todas as referências do mundo.**

Para um mundo íntegro, ainda não afetado por remoção ou conflito:

1. Feche o jogo ou servidor e faça backup do save completo. Em servidor, guarde também as configurações e os arquivos de jogadores/contas correspondentes.
2. Atualize os pacotes originais e mantenha as aparências ativas durante a preparação. Ative **VINI Furniture Recovery [B42]** na lista de mods desse mundo, junto com as aparências.
3. Carregue o mundo, espere o carregamento terminar, salve e feche o jogo/servidor. Isso registra identidades dos móveis carregados; não afirma que regiões distantes já foram convertidas.
4. Desative somente as aparências que deseja remover, mantendo **ViniFridgeRecovery** habilitado. Abra novamente o mundo para recuperar os móveis suportados com o visual original.
5. Mantenha o Recovery disponível e ativo enquanto houver regiões não visitadas ou móveis guardados que ainda usem referências antigas. Se o save contém **latas Dr Pepper, fluidos personalizados, itens de pôster ou aliases de pôster presos às paredes**, mantenha o suporte enquanto qualquer um desses tipos permanecer. Visitar uma área não converte todos esses itens/tipos.

### Inscrições da Workshop e cópia independente

Os cinco pacotes fornecem o mesmo suporte opcional. Mantenha pelo menos um pacote provedor instalado. **Não cancele a inscrição de todos os provedores antes de instalar e ativar uma cópia completa e independente de `ViniFridgeRecovery`.**

Para preparar essa cópia, feche o jogo/servidor e copie a pasta inteira `ViniFridgeRecovery`, com `42` e `common` diretamente dentro dela, para a pasta `mods` do perfil/cache realmente usado. O padrão Windows é `%USERPROFILE%\Zomboid\mods\ViniFridgeRecovery`; com `-cachedir`, use `<cache escolhido>\mods\ViniFridgeRecovery`. Não basta copiar apenas `42` ou alguns arquivos Lua. Mantenha o Mod ID `ViniFridgeRecovery` ativo.

Em multiplayer, servidor e jogadores precisam dos mesmos arquivos atualizados e da mesma configuração de mods aplicável ao mundo. Se usar a cópia independente, distribua-a aos jogadores e mantenha `ViniFridgeRecovery` no campo `Mods` do servidor antes de remover todos os provedores da Workshop.

### Mundo já afetado

Se o mundo já foi aberto e salvo após remover uma aparência, ou sofreu conflito, trabalhe primeiro em uma cópia. Não reative os originais à força como regra geral; siga o guia completo. O Recovery usa IDs originais ou identidades exatas sobreviventes. Se a referência original e os registros de orientação foram perdidos, restaure o backup em vez de tentar adivinhar ou destruir o móvel. Este patch de documentação não promete reparar automaticamente um save já danificado.

Guia completo em inglês, incluído no pacote: [SAFE-REMOVAL-GUIDE.md](../ViniFridgeRecovery/common/SAFE-REMOVAL-GUIDE.md).

## English

**Disabling an appearance and restarting alone is insufficient for a save that already contains custom furniture. Setting 0% or visiting a room does not convert every reference.** The included `ViniFridgeRecovery` support requires Build 42.21.

For an undamaged world, close the game/server and back up the complete save, including matching server settings and player/account files. Update the original packages and enable **VINI Furniture Recovery [B42]** in that world's mod list while the appearance mods remain enabled. Load, wait for loading to finish, save and close before disabling only the appearances you want to remove. Leave Recovery enabled when you reopen the world.

Keep Recovery available and enabled while unseen regions or stored furniture still use old references, and for as long as **Dr Pepper cans, custom fluids, poster items or wall-poster aliases** remain. Visiting an area does not convert all of these references.

Keep at least one supplying Workshop package installed. Before unsubscribing from every supplier, install and enable a complete standalone `ViniFridgeRecovery` folder, including both `42` and `common`, in the actual profile/cache `mods` folder. The usual Windows destination is `%USERPROFILE%\Zomboid\mods\ViniFridgeRecovery`; honor a custom `-cachedir`. Multiplayer servers and players need matching files; provide the standalone copy to clients and retain its ID in the server's `Mods` setting before removing all Workshop suppliers.

For a world already affected by removal or a conflict, work on a copy and follow the full guide instead of forcibly re-enabling originals. Recovery needs surviving original IDs or exact identities. If those records and orientation are lost, restore a backup. This documentation patch does not promise automatic repair of an already damaged save.

Full guide: [SAFE-REMOVAL-GUIDE.md](../ViniFridgeRecovery/common/SAFE-REMOVAL-GUIDE.md).
