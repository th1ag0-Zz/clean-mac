# Validação desta reconstrução

Data: 14/10/2026. Host: Apple Silicon, macOS 27, Xcode 27.0 / Swift 6.4. Deployment target: macOS 15.

## Gates executados

- Build Xcode Debug arm64: passou.
- Build Xcode Release arm64: passou.
- 16 programas smoke: passaram. Quinze na rodada completa e monitor FSEvents em execução separada fora do sandbox.
- `git diff --check`: passou.
- Release copiado para `build/Clean Mac.app` e aberto neste Mac.
- Prévia da interface e árvore de acessibilidade observadas pelo REA no Release: `ev_f8d5664d39199a6af1fc3bcfd9fa18204709305639d2f24b9f943b12f0c2e094`.
- Navegação nativa por 13 destinos passou via AXPress, sem executar limpeza: `ev_1d73623a248065e3a327804dc19ea21c1293430e2f17cd3fd2ef3a09a063bcc6`.
- Prévia final em Cuidados Inteligentes: `ev_f54153a1e6bb97a6ab8ed5353fb5c7c91f50fc7af9a8c567f893d35ea9c325b2`. Registros completos em [rea-evidence.json](rea-evidence.json).

```sh
python3 scripts/test_local.py
```

O runner valida `.fixtures/sample-home/.cleanup-mac-fixture` e exporta `CLEANUP_MAC_FIXTURE_HOME` apenas para os executáveis de teste. NSFileVersion e FSEvents exigiram executar fora do sandbox do agente; as remoções permaneceram nas fixtures. O teste Toolbox usa seu próprio diretório temporário, com seleção fora da fixture bloqueada quando a variável está presente.

| Teste | Evidência de aceitação |
| --- | --- |
| AnalysisSmoke | Catálogo, totais, exclusões persistidas, cancelamento |
| AnalysisViewModelSmoke | Estados, seleção inicialmente vazia, limpeza confirmada, inspeção da Lixeira |
| CleanupSmoke | Plano exato, arquivo alterado recusado, movimento para Trash da fixture, symlinks |
| AdvancedSmoke | Sistema fictício, Xcode, Mail Downloads, backups, NSFileVersion e lixeira de volume fictício |
| AdditionalCleanupSmoke | Inventário de modelo local; preferência válida/recentemente modificada preservada; somente seleção movida |
| ApplicationsSmoke | App, dados associados, possível resíduo e instalador; seleção inválida e app alterado recusados |
| OrganizationSmoke | Duplicados SHA256, imagens semelhantes reais, idade, links e totais por pasta |
| PersonalFileActionsSmoke | Cópia duplicada preservada e revalidada; alteração/symlink em arquivo/ancestral; pacote/cloud/home rejeitados |
| LargeFilesSmoke | Limite de 100 MB, arquivos menores, links e pacotes |
| SpaceLensSmoke | Áreas proporcionais, ausência de sobreposição, árvore, pasta escolhida e Trash individual |
| ProtectionSmoke | EICAR, persistência, TCC SQLite readonly, grupos de navegador, mudança de conteúdo e symlinks recusados |
| ProtectionMonitorSmoke | Eventos recursivos de arquivo real da fixture; ausência de callbacks depois de parar |
| PhotosClutterSmoke | PNGs reais/dHash, grupos SHA256, proporção visual, seleção preservando uma foto, acesso real negado em fixture |
| ToolboxSmoke | Unlink de arquivo individual, preservação de irmão, identidade/ancestral, snapshot date, parser DMG, backup SQLite Mail, métricas reais |
| AppSlimmingSmoke | Dois Mach-O FAT reais gerados no teste, framework com links relativos, idioma preservado, redução de arquitetura, codesign ad hoc verificado e original idêntico |
| ValidationSmoke | Exclusão desconhecida, flock, permissão negada, arquivo esparso 5 GiB, substituição por symlink e arquivo pessoal preservado |

## Limites desta validação

Não foram apagados arquivos pessoais nem executadas manutenção administrativa, varredura ClamAV real, remoção na fototeca real ou esvaziamento da Lixeira real. O teste de Photos valida algoritmos e bloqueio da fixture, não autorização/remoção numa fototeca do usuário. O monitor foi exercitado com arquivos locais reais da fixture. A cópia otimizada foi testada com um app fictício, não com software comercial instalado.

Compatibilidade em máquina macOS 15, uso assistivo completo, distribuição assinada/notarizada e resultados idênticos ao CleanMyMac não foram demonstrados. As permissões nativas e efeitos de assinatura em aplicativos reais precisam ser avaliados durante o uso autorizado.

SHA256 do executável Release validado: `d6a67a81858aae67595c9877134e6e3b45a87a74af8ba106695e817ffb218aa8`.
