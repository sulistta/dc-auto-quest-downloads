# DC Auto Quest — instalação

Feche completamente o Discord, inclusive pela bandeja, e execute como usuário normal.

Linux x86_64:

```sh
bash -o pipefail -c 'curl -fsSL https://raw.githubusercontent.com/sulistta/dc-auto-quest-downloads/main/install.sh | bash'
```

Windows x64, no PowerShell de 64 bits:

```powershell
irm https://raw.githubusercontent.com/sulistta/dc-auto-quest-downloads/main/install.ps1 | iex
```

O instalador baixa o pacote da versão publicada, verifica SHA-256 e o conteúdo do arquivo, e integra o Discord. Reabra o Discord após concluir. Não é necessário instalar Rust, Node.js nem executar como administrador. Repita o mesmo comando para atualizar ou reparar.

A integração gerencia somente seu próprio bloco no carregador do Discord e preserva outras modificações. Use o DC Auto Quest na página de missões; os controles originais permanecem disponíveis.

## Verificar ou remover

Feche completamente o Discord antes de remover.

Linux:

```sh
~/.local/bin/dc-auto-quest --status
~/.local/bin/dc-auto-quest --remove
```

Windows:

```powershell
& "$env:LOCALAPPDATA\dc-auto-quest\bin\dc-auto-quest.exe" --status
& "$env:LOCALAPPDATA\dc-auto-quest\bin\dc-auto-quest.exe" --remove
```

A remoção retira somente a integração e seus runtimes. O comando local continua disponível para verificar o estado ou instalar novamente. A ferramenta portátil também está nos [downloads](https://github.com/sulistta/dc-auto-quest-downloads/releases).

Este repositório distribui os instaladores e os executáveis. O código do aplicativo é mantido separadamente.
