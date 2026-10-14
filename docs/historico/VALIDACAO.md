# Validação e entrega — etapa 4

## Resultado em 11/10/2026

Ambiente: macOS 27.0.1, Xcode instalado nesta máquina, alvo do projeto macOS 15.0 ou posterior. Todos os testes de execução usaram exclusivamente a home `.fixtures/sample-home` em Debug. O build Release foi compilado, mas não executou limpeza na home real.

| Verificação | Resultado |
| --- | --- |
| Catálogo, exclusões, totais e cancelamento | Passou: `tests/AnalysisSmoke.swift` |
| Estados de análise, seleção, limpeza confirmada e inspeção da Lixeira | Passou: `tests/AnalysisViewModelSmoke.swift` |
| Plano exato, alteração após análise, movimento e Lixeira isolada com link simbólico | Passou: `tests/CleanupSmoke.swift` |
| Sistema, Xcode, Mail Downloads, backups, versões e Lixeira externa fictícia | Passou: `tests/AdvancedSmoke.swift` na fixture Debug |
| Item desconhecido, cache antigo de outro aplicativo, arquivo em uso, permissão negada e arquivo esparso de 5 GiB | Passou: `tests/ValidationSmoke.swift` |
| Troca do caminho elegível por link para documento pessoal após a análise | Passou: limpeza recusada; documento permaneceu igual |
| Builds limpos Debug e Release | Passaram com `xcodebuild ... CODE_SIGNING_ALLOWED=NO clean build` |
| Interface inicial na largura mínima de 960 pontos | Inspecionada visualmente no app Debug em execução; conteúdo visível sem corte |
| Árvore de acessibilidade em tempo de execução | Não verificada: o macOS negou acesso assistivo ao `osascript` (`-1719`) |
| Execução no macOS 15 | Não verificada: essa versão não está disponível nesta máquina |
| Assinatura Developer ID e notarização | Não realizadas; ainda não existe artefato de distribuição |

Os botões usam controles SwiftUI com texto; as caixas de seleção têm rótulos explícitos. A navegação informa o item selecionado por característica de acessibilidade, e os cartões de resumo são agrupados para leitura. Isso foi revisado no código e compilado, mas não substitui um teste com VoiceOver e navegação por teclado no app em execução.

## Permissões e categorias

O teste de Aplicativos em fixture Debug (`tests/ApplicationsSmoke.swift`) passou para app, dados associados, possível resíduo e instalador, além de seleção inválida, app alterado e leitura de appcast. Os builds Debug e Release da V2 compilaram. A execução de remoção na home real e a consulta a feeds externos ainda não foram validadas manualmente.

O teste de Arquivos grandes (`tests/LargeFilesSmoke.swift`) cobre o limite de 100 MB, arquivos menores, atalhos e pacotes de apps na fixture Debug. Os builds Debug e Release com a nova tela compilaram; a análise de pastas pessoais reais ainda não foi executada.

```sh
swiftc -D DEBUG cleanup-mac/ScanScope.swift cleanup-mac/AnalysisModels.swift cleanup-mac/AnalysisCatalog.swift cleanup-mac/AnalysisExclusions.swift cleanup-mac/AnalysisEngine.swift cleanup-mac/CleanupModels.swift cleanup-mac/CleanupEngine.swift cleanup-mac/AdvancedCleanupEngine.swift cleanup-mac/ApplicationsEngine.swift cleanup-mac/AppUpdateChecker.swift tests/ApplicationsSmoke.swift -o /private/tmp/cleanup-mac-applications-smoke
CLEANUP_MAC_FIXTURE_HOME="$PWD/.fixtures/sample-home" /private/tmp/cleanup-mac-applications-smoke
```

O aplicativo não solicita privilégio de administrador nem Acesso Total ao Disco. O App Sandbox está desativado para a distribuição direta planejada, mas o macOS ainda pode negar acesso por permissões do arquivo ou controles de privacidade. Falhas de acesso aparecem como resultado parcial ou impedem a operação. A [documentação de segurança da Apple](https://support.apple.com/en-lamr/guide/security-pdf/secddd1d86a6/web) descreve esses controles do macOS.

O catálogo principal contém arquivos `.log` em `~/Library/Logs`, relatórios `.ips`/`.crash`/`.diag` em `~/Library/Logs/DiagnosticReports`, arquivos em `~/Library/Caches` e instaladores `.dmg`/`.pkg` diretamente em `~/Downloads`, todos sem modificação há pelo menos 30 dias. A [limpeza adicional](LIMPEZA_AVANCADA.md) cobre as outras áreas por regras próprias. Nenhum item vem selecionado. A Lixeira da home e as Lixeiras acessíveis de volumes montados são analisadas em fluxo separado e só são esvaziadas depois de confirmação específica.

## Limites para a entrega

- A validação de identidade impede trocas detectadas antes da operação. Uma troca concorrente no intervalo entre a última checagem e o movimento ainda não tem prova de segurança completa; avaliar esse risco antes de distribuir a V1.
- A detecção de arquivo em uso depende de bloqueios consultivos. Programas que não cooperam com esse mecanismo podem manter um arquivo aberto.
- O tamanho encontrado é lógico. Mover para a Lixeira não equivale a liberar espaço. A estimativa de bytes alocados excluídos da Lixeira não mede espaço efetivamente livre em volumes com clones ou outros mecanismos de compartilhamento.
- A inspeção cobre a Lixeira da home e `.Trashes/<uid>` nos volumes visíveis em `/Volumes`; itens inacessíveis não são incluídos no esvaziamento revisado. Lixeiras de outros usuários e volumes desmontados ficam fora.
- Antes de declarar a V1 pronta para distribuição: testar VoiceOver e teclado com a permissão assistiva adequada, executar em macOS 15, revisar a corrida de troca de caminho e gerar um app assinado e notarizado com Developer ID.

## Comandos reproduzíveis

Execute os testes em sequência, porque compartilham a fixture:

```sh
swiftc -D DEBUG cleanup-mac/ScanScope.swift cleanup-mac/AnalysisModels.swift cleanup-mac/AnalysisCatalog.swift cleanup-mac/AnalysisExclusions.swift cleanup-mac/AnalysisEngine.swift tests/AnalysisSmoke.swift -o /private/tmp/cleanup-mac-analysis-smoke
swiftc -D DEBUG cleanup-mac/ScanScope.swift cleanup-mac/AnalysisModels.swift cleanup-mac/AnalysisCatalog.swift cleanup-mac/AnalysisExclusions.swift cleanup-mac/AnalysisEngine.swift cleanup-mac/CleanupModels.swift cleanup-mac/CleanupEngine.swift cleanup-mac/TrashEngine.swift cleanup-mac/AnalysisViewModel.swift tests/AnalysisViewModelSmoke.swift -o /private/tmp/cleanup-mac-ui-smoke
swiftc -D DEBUG cleanup-mac/ScanScope.swift cleanup-mac/AnalysisModels.swift cleanup-mac/AnalysisCatalog.swift cleanup-mac/AnalysisExclusions.swift cleanup-mac/AnalysisEngine.swift cleanup-mac/CleanupModels.swift cleanup-mac/CleanupEngine.swift cleanup-mac/TrashEngine.swift tests/CleanupSmoke.swift -o /private/tmp/cleanup-mac-cleanup-smoke
swiftc -D DEBUG cleanup-mac/ScanScope.swift cleanup-mac/AnalysisModels.swift cleanup-mac/AnalysisCatalog.swift cleanup-mac/AnalysisExclusions.swift cleanup-mac/AnalysisEngine.swift cleanup-mac/CleanupModels.swift cleanup-mac/CleanupEngine.swift cleanup-mac/TrashEngine.swift tests/ValidationSmoke.swift -o /private/tmp/cleanup-mac-validation-smoke
CLEANUP_MAC_FIXTURE_HOME="$PWD/.fixtures/sample-home" /private/tmp/cleanup-mac-analysis-smoke
CLEANUP_MAC_FIXTURE_HOME="$PWD/.fixtures/sample-home" /private/tmp/cleanup-mac-ui-smoke
CLEANUP_MAC_FIXTURE_HOME="$PWD/.fixtures/sample-home" /private/tmp/cleanup-mac-cleanup-smoke
CLEANUP_MAC_FIXTURE_HOME="$PWD/.fixtures/sample-home" /private/tmp/cleanup-mac-validation-smoke
xcodebuild -quiet -project cleanup-mac.xcodeproj -scheme cleanup-mac -configuration Debug -derivedDataPath /private/tmp/cleanup-mac-debug CODE_SIGNING_ALLOWED=NO clean build
xcodebuild -quiet -project cleanup-mac.xcodeproj -scheme cleanup-mac -configuration Release -derivedDataPath /private/tmp/cleanup-mac-release CODE_SIGNING_ALLOWED=NO clean build
```
