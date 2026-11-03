# Offline Survivor Silent Death

Mod ID: `OfflineSurvivorSilentDeath`

Esta e a variante PvP do Offline Survivor. Ela inclui todos os recursos da
variante principal e permite assassinar um sobrevivente offline com uma faca.

## Recursos adicionais

- acao **Assassinar enquanto dorme** para jogadores proximos com uma faca;
- substituicao do corpo de descanso por um cadaver normal do jogo;
- inventario, roupas e equipamentos liberados no cadaver apos o assassinato;
- aviso para a vitima com o nome do assassino ao reconectar.

## Uso

Ative somente este mod em servidores PvP. Nao combine com
`OfflineSurvivor`. O assassinato faz parte desta variante e nao possui uma
opcao Sandbox separada. Copie a pasta `42.0` completa para o servidor e use o
Mod ID acima. Substitua tambem o `mod.info` da raiz, nao apenas os Lua;
uma instalacao antiga sem as opcoes atuais faz o servidor desativar recursos
novos, como morte por zumbis, no proximo reinicio.

Depois de atualizar arquivos Lua, reinicie o servidor e os clientes.

## Revisão local de 18/09/2026

Inclui proteção de idade dos corpos visuais, compensação específica de enjoo,
identificação de sessões de arrasto e correções no ciclo de morte/reconexão.
O áudio nativo de moscas ainda pode ocorrer. A validação em servidor real
continua necessária; não foi iniciado jogo ou servidor nesta revisão.

Admins podem usar o botão direito, escolher **Remover corpos ao redor** e
confirmar. O raio é configurável no sandbox: padrão 15, de 1 a 50 quadrados.
Afeta apenas o mesmo andar e a área carregada. Cadáveres reais e seus itens
são apagados; remover o visual offline não mata o dono nem apaga seu inventário
real. Mortes anteriores não são canceladas por essa limpeza.

Consulte também o README principal do pacote para instalação, limitações e
roteiro de validação.
