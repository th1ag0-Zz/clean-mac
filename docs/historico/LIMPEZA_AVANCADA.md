# Limpeza adicional

O botão **Limpeza adicional** analisa as áreas abaixo. Nada vem selecionado. Arquivos e pastas confirmados vão para a Lixeira; versões anteriores de documentos são removidas pela API `NSFileVersion` após um aviso específico e não podem ser recuperadas pela Lixeira.

| Área | O que o app analisa | Regra |
| --- | --- | --- |
| Cache e temporários do sistema | `/Library/Caches` e `/private/var/tmp` | Arquivos regulares sem alterações há 30 dias |
| Logs do sistema | `/Library/Logs` e `/private/var/log` | `.log`, `.ips`, `.crash` e `.diag` sem alterações há 30 dias |
| Cache de aplicativos | `~/Library/Caches` | Na análise principal; arquivos sem alterações há 30 dias |
| Xcode | Pastas de projetos em `~/Library/Developer/Xcode/DerivedData` | A pasta inteira só aparece quando seu conteúdo não mudou há 30 dias; archives e simuladores ficam fora |
| Anexos do Mail | `Mail Downloads` da home e do contêiner do Mail | Só cópias locais nessa pasta sem alterações há 30 dias; revisar se foram editadas; não acessa a base de mensagens |
| Backups de dispositivos | Pastas em `~/Library/Application Support/MobileSync/Backup` | Cada backup inteiro só aparece se seu conteúdo não mudou há 30 dias |
| Versões de documentos | Documentos locais em `~/Documents` e `~/Desktop` com versões anteriores da API `NSFileVersion` | Preserva a versão atual; ignora documentos identificados como iCloud e conflitos não resolvidos |
| Lixeiras | `~/.Trash` e `.Trashes/<uid>` dos volumes visíveis em `/Volumes` | Ação separada com confirmação de exclusão permanente; só itens acessíveis e revisados |

O app não usa privilégio de administrador. Pastas protegidas podem gerar análise parcial ou falha por item. A checagem valida tipo, volume, inode, metadados e ausência de links simbólicos no caminho antes de mover um item. Pastas inteiras são medidas e verificadas novamente antes da operação. Backups devem ser revisados com cuidado; um backup de restauração pode ser perdido.

O Mail mantém cópias temporárias em *Mail Downloads* e oferece o ajuste **Remove unedited downloads**. A remoção de anexos pela ação **Message > Remove Attachments** pode apagar anexos de contas IMAP também no servidor; este app não chama essa ação nem altera mensagens. [Ajuda do Mail](https://support.apple.com/en-ie/guide/mail/mlhlp1123/16.0/mac/27), [ajuste de downloads](https://support.apple.com/en-ie/guide/mail/cpmlprefgen).

A Apple documenta o local dos [backups locais de iPhone/iPad](https://support.apple.com/en-ie/108809) e a remoção de [versões anteriores](https://developer.apple.com/documentation/foundation/nsfileversion/removeotherversionsofitem%28at%3A%29). Versões são removidas por escrita coordenada. O macOS também limpa certos caches por conta própria quando precisa de espaço, conforme a [Ajuda de armazenamento](https://support.apple.com/en-us/102624).

Teste isolado: `tests/AdvancedSmoke.swift` cria arquivos apenas na fixture Debug, testa as categorias, move itens selecionados, rejeita um item alterado, remove uma versão anterior e esvazia uma Lixeira externa fictícia.
