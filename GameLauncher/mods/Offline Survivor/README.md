# Offline Survivor

Mod ID: `OfflineSurvivor`

Quando um jogador desconecta, um corpo humano permanece no local usando a
aparencia do personagem. Os demais jogadores podem usar a acao **Revistar**
para acessar os itens permitidos pelo servidor.

## Recursos

- aparencia, roupas e itens equipados reproduzidos pelo modelo nativo;
- posicionamento no chao, cama ou sofa proximo;
- painel de revista com limite de itens e tempo de espera;
- configuracoes Sandbox aplicadas pelo servidor;
- suporte a servidor dedicado e multiplayer.

## Uso

Ative somente este mod para usar a variante padrao. Nao ative junto com
`OfflineSurvivorSilentDeath`, pois as duas variantes controlam o mesmo
evento de desconexao. Copie a pasta `42.0` completa para o servidor e use o
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
