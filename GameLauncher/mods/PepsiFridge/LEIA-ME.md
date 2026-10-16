REMOÇÃO SEGURA — BUILD 42.21
Antes de desativar esta aparência em um mundo existente, faça backup e siga REMOCAO-SEGURA.md, incluído nesta pasta.
Em mundo íntegro, ative VINI Furniture Recovery [B42] (ViniFridgeRecovery) com a aparência ainda ativa; carregue, salve e feche antes de desativar a aparência. Mantenha o Recovery ativo enquanto houver regiões não visitadas, móveis guardados ou tipos Dr Pepper ainda presentes. Não cancele todos os pacotes provedores sem preparar uma cópia independente completa do suporte.
Em multiplayer, servidor e jogadores precisam dos mesmos arquivos. Em mundo já afetado por remoção/conflito, trabalhe numa cópia e siga o guia completo.
O suporte requer Build 42.21. Guia completo: ../ViniFridgeRecovery/common/SAFE-REMOVAL-GUIDE.md.

SAFE REMOVAL — BUILD 42.21
Back up and follow REMOCAO-SEGURA.md before disabling this appearance in an existing world. For an undamaged world, enable VINI Furniture Recovery while the appearance is still active; load, save and close before disabling the appearance. Keep Recovery for unseen regions, stored furniture and remaining Dr Pepper types. Keep a supplying package or a complete standalone copy; servers and players need matching files. Work on a copy of an already affected world. Full guide: ../ViniFridgeRecovery/common/SAFE-REMOVAL-GUIDE.md.

# Pepsi Fridge [B42] — 1.1.3

Mod independente para transformar somente a **White Industrial Fridge** do Project Zomboid em uma geladeira Pepsi. Criado em 16/09/2026 a partir das três referências fornecidas e da arquitetura dos mods anteriores do usuário.

## Variante desgastada (1.1.0)

Além do visual Pepsi original, a geladeira pode aparecer com tinta azul desbotada e descascada, ferrugem nas bordas e grades, sujeira na base e condensador envelhecido. A variante mantém as quatro orientações, os quatro níveis de estoque, luz azul com energia, refrigeração, freezer, sons e ícones próprios para os dois compartimentos. Seu nome aparece como **Geladeira Pepsi desgastada** em português brasileiro e tem tradução nas 29 seleções de idioma suportadas.

Em **Sandbox Options → Pepsi Fridge**, a opção **Worn appearance chance** oferece as mesmas dez escolhas da chance principal: 1%, 5%, 10%, 15%, 25%, 35%, 50%, 75%, 90% e 100%; o padrão é 25%. Valores antigos fora da lista, inclusive 0%, continuam válidos até o jogador selecionar uma nova opção. A chance de aparição da Pepsi entre as geladeiras industriais brancas continua independente. Geladeiras Pepsi limpas de saves anteriores preservam o visual antigo ao carregar ou mover o móvel.

As três matrizes de arte da variante ficam em `variants/Worn/artwork`; a prévia dos sprites exportados fica em `variants/Worn/build/artwork/Pepsi-Fridge-preview.png` no projeto. As duas páginas de textura dividem o mesmo pack e tiledef, sem alterar os sprites originais.

## Design

Revisão visual v6: removido o fragmento cinza de lata entre as duas últimas latas azuis na prateleira inferior da vista cheia marcada pelo usuário. Correção localizada com e sem energia; os demais pixels da matriz foram preservados. A versão anterior está em `revisions/design-v6/before`.

Revisão visual v5: arte frontal e traseira revisada, com maçanetas finas embutidas na moldura preta e vidro inteiro livre. Removidas as faixas e exclusões de imagem que encobriam as bebidas. Cada abertura de vidro é alinhada integralmente a uma referência fixa, preservando o conteúdo e o acabamento da carcaça entre os níveis. A base foi refeita como um rodapé contínuo, com grade organizada e sem pés isolados. O registro passou a incluir toda a borda inferior da nova arte; apenas os pequenos recuos nativos nos dois cantos frontais inferiores foram preenchidos, sem alterar tamanho de textura, deslocamentos ou posicionamento no jogo. Correções aplicadas com e sem energia. A revisão anterior está em `revisions/design-v5/before`.

Revisão visual v4: maçaneta no lado esquerdo físico da porta nas duas vistas frontais (na vista com lateral à esquerda, ela fica junto ao canto central), com altura equivalente após a projeção. Moldura e grade pretas mais definidas; uma única carcaça por orientação mantém posição, letreiro, logotipos e maçaneta iguais nos quatro níveis. As variações de estoque ficam restritas ao vidro e a iluminação do letreiro usa uma referência fixa. A exportação aplica a transparência nativa uma única vez, eliminando a duplicação das bordas. A amostragem do teto foi limitada ao interior da face azul para impedir que pixels claros do fundo da matriz contaminem o contorno. Os ajustes foram aplicados com e sem energia. A versão v3 foi preservada em `revisions/design-v4/before`.

Revisão visual v3: nome Pepsi com letras maiores e traços mais espessos nas frentes e laterais; ajuste das duas garrafas do estado pouco cheia; rótulo da garrafa destacada em quase cheia corrigido, com a base marrom exposta abaixo da faixa azul. Revisões aplicadas com e sem energia. O tamanho nativo do sprite foi preservado; a melhoria é de legibilidade da arte, não um aumento da resolução do motor. A versão anterior está em `revisions/design-v3/before`.

Corpo e teto azul Pepsi, logotipo nas laterais e no cabeçalho, moldura preta, vidro transparente, prateleiras metálicas, latas e garrafas de Pepsi. As duas vistas traseiras mostram condensador, grade e painel de manutenção. Há versões com iluminação e sem energia.

Revisão visual v2: teto azul nas quatro orientações; garrafas menores no estado pouco cheia, com espaço entre a tampa e a prateleira superior; redução moderada do estoque no estado quase cheia. Alterações aplicadas com e sem energia. O design anterior foi preservado em `revisions/design-v2/before`. Os limites de preenchimento e as regras do mod permanecem iguais.

A arte em alta resolução foi criada com a ferramenta integrada image_gen. As faces foram registradas nas dimensões, deslocamentos e mapas de profundidade dos sprites 40, 41, 42 e 43 de `appliances_refrigeration_01`. A transparência original é preservada, exceto pelo preenchimento localizado dos pequenos recuos nos cantos inferiores frontais para o novo rodapé contínuo; nenhuma textura ultrapassa o tamanho nativo.

- `artwork/Pepsi-Fridge-master.png`: matriz frontal em alta resolução, com quatro níveis e duas orientações.
- `artwork/Pepsi-Fridge-unpowered-master.png`: matriz frontal sem iluminação.
- `artwork/Pepsi-Fridge-rear-master.png`: duas vistas traseiras.
- `artwork/Pepsi-Fridge-preview.png`: prévia das texturas realmente exportadas, ampliadas 2×.
- `artwork/Pepsi-Fridge-preview-v6.png` e `artwork/Pepsi-Fridge-preview-unpowered-v6.png`: cópias da revisão atual com e sem energia.
- `artwork/design-v6-prompts.json`: instruções da correção localizada feita com image_gen e registro da integração.
- `artwork/Pepsi-Fridge-native-comparison.png`: comparação do móvel original com os quatro sprites Pepsi.

As imagens são artes/prévias de textura, não capturas em partida.

## Quatro níveis de preenchimento

| Ocupação | Aparência |
| --- | --- |
| Abaixo de 10% | Vazia |
| De 10% a menos de 20% | Pouco cheia |
| De 20% a menos de 30% | Quase cheia |
| A partir de 30% | Cheia |

A ocupação é calculada pelo peso armazenado dividido pela capacidade total dos compartimentos refrigerados. Com capacidades nativas 40 + 20, os limites são 6, 12 e 18 unidades de peso somadas. O estado cheio aos 30% é somente visual: continua sendo possível guardar itens até o limite normal. Itens de peso zero ou conteúdo abaixo de 10% podem existir mesmo quando a arte mostra prateleiras vazias.

As bebidas são uma representação visual do estoque; não são novos itens consumíveis. O preenchimento continua atualizado sem energia. As vistas traseiras ocultam naturalmente o conteúdo.

## Recursos preservados

- Quatro orientações; recolher e recolocar preserva a escolha visual.
- Geladeira com capacidade 40 e freezer com capacidade 20, conforme as definições nativas instaladas. Capacidade, peso, sons e propriedades de refrigeração não foram reescritos pelo código Lua.
- Luz azul escura (RGB 12/45/150, raio 2) com energia; apagada durante falta de energia ou desligamento pelo Nick's Turn Off Fridges.
- Atualização imediata após transferências, sem sobreposição de alimentos padrão.
- Miniaturas transparentes distintas de 64 × 64 para a geladeira e o freezer, seguindo o padrão do Monster. O freezer tem um floco de neve. Nome localizado no inventário, na seleção de móveis, no Sandbox e no menu de mods; em português brasileiro: **Geladeira Pepsi**.
- Capa exclusiva de 1024 × 1024 para a lista de mods e ícone de 256 × 256. Artes criadas com image_gen; originais e instruções em `artwork/local-release-prompts.json`. O design aprovado v6 das texturas no mundo foi preservado.
- Dez chances no Sandbox: 1%, 5%, 10%, 15%, 25%, 35%, 50%, 75%, 90% e 100%. Padrão: 100%.
- Traduções em todas as 29 seleções reconhecidas pelo B42 instalado: EN, AR, CA, CH, CN, CS, DA, DE, ES, ES_CL, ES_MX, FI, FR, HU, ID, IT, JP, KO, NL, NO, PL, PT, PTBR, RO, RU, STREW, TH, TR e UA. São 28 opções de idiomas/regiões e a opção experimental Strewberrie, seguindo o padrão do próprio jogo.
- Mod independente; não exige Coca-Cola, Monster, Redbull ou Nick. Os três outros modelos de geladeira/freezer ficam fora da seleção da Pepsi.

A chance aplica-se a cada geladeira industrial branca existente, não cria móveis extras. Alterar o Sandbox afeta os objetos quando forem novamente processados/carregados. O dado de escolha acompanha o móvel. Em multijogador, a distribuição é controlada pelo servidor.

## Pacote de teste local

Arquivo da variante: `PepsiFridge-1.1.0-WORN-LOCAL.zip`.

1. Feche o jogo.
2. Extraia a pasta `PepsiFridge` do ZIP para a pasta `Zomboid/mods` do seu usuário.
3. Confira `PepsiFridge/42/mod.info` e a pasta `PepsiFridge/common` ao lado de `42`.
4. Ative **Geladeira Pepsi [B42]** em português brasileiro, ou **Pepsi Fridge [B42]** em inglês. Para uma partida existente, ative também na lista de mods dessa partida.
5. Para conferir o resultado, use uma partida de teste com a opção Pepsi em 100% e uma White Industrial Fridge.

ID: `PepsiFridge`. Tiledef: `4862`. Versão mínima: `42.20.4`.

## Validação e limites

Passaram os testes locais:

- Leitura das 40 texturas (20 originais e 20 desgastadas) pelo TexturePackDevice do motor B42 instalado.
- Compilação de todos os arquivos Lua pelo compilador Kahlua do jogo.
- Comparação das propriedades nativas e resolução das quatro rotações.
- Carregamento e atribuição dos 40 mapas de profundidade nativos em um contexto gráfico oculto.
- Registro/remoção da luz azul com objetos Java e ponte Lua reais, preservando outra lâmpada.
- Limites exatos de 10%, 20% e 30%, esvaziamento, preenchimento acima de 30%, dois compartimentos, transferências imediatas, recuperação de sobreposição e 2.000 ciclos sem regravação desnecessária.
- 100 ciclos de desligar/religar usando o código instalado do Nick para os tipos de recipiente, incluindo transferências enquanto desligada.
- 220.000 objetos simulados para dez chances e o valor técnico 0%, escolha persistente, isolamento e transporte usando os trechos nativos de recolher/recolocar.
- Menu de Sandbox em 29 idiomas × 24 ordens de carregamento de Pepsi/Coca-Cola/Monster/Redbull.
- Botões e cabeçalho do inventário com métodos nativos, incluindo reutilização de botões.
- Carregamento nativo de 116 arquivos de tradução e 899 textos, cobrindo exatamente a lista de idiomas da instalação.
- Conferência visual das texturas exportadas, transparência e integridade do ZIP.
- Revisão v5: vidro contínuo, sem faixas ou exclusões internas; moldura e marca fixas entre níveis; contorno consistente nos dois estados de energia; preenchimento da transparência limitado ao rodapé frontal, com dimensões e deslocamentos preservados. Relatório em `qa/design-v5-result.json`.

**Ainda não observado em uma partida na versão 1.1.3:** a miniatura revisada do freezer no inventário, aparência e iluminação da variante desgastada no ambiente, oclusão do personagem, ciclo real de refrigeração, salvar/reabrir um mundo e servidor com jogadores conectados. Os testes locais não substituem essa validação.

Destino da instalação local para teste: `C:\Users\vssvi\Zomboid\mods\PepsiFridge`. A confirmação da instalação estará em `qa/worn-local-install-result.json` no projeto. Oficina Steam: https://steamcommunity.com/sharedfiles/filedetails/?id=3803017298

Mod de fã sem vínculo com PepsiCo; marcas pertencem aos respectivos titulares.
