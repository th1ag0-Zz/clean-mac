# Limpeza — etapa 3

O plano contém somente os candidatos selecionados que constam do resultado da análise e ainda obedecem ao catálogo e às exclusões. Caches de outros aplicativos e instaladores antigos exigem revisão manual: o local e a idade não provam que um arquivo deixou de ser útil. Antes de mover cada arquivo, o motor verifica caminho, tipo, volume, inode, tamanho, datas e ausência de links físicos adicionais, sem seguir links simbólicos. Cada resultado registra o destino ou o erro. Mover para a Lixeira não é contado como espaço efetivamente liberado.

Em Debug, os arquivos são movidos somente para `.fixtures/sample-home/.Trash`; em Release, usa-se a Lixeira do macOS. A tela da Lixeira lê a `.Trash` principal da home e `.Trashes/<uid>` dos volumes montados acessíveis, mede apenas itens suportados e exige uma confirmação independente para exclusão permanente. Itens inacessíveis ou que mudaram desde a inspeção são ignorados ou reportados como falha. O relatório informa bytes alocados removidos como estimativa, sem prometer espaço livre: clones APFS e outras características do volume podem afetar esse valor. A [limpeza adicional](LIMPEZA_AVANCADA.md) tem regras próprias.

O [Mail para Mac](https://support.apple.com/en-lamr/guide/mail/mlhlp1123/mac) trata downloads de anexos e cópias salvas de formas diferentes; a recuperação de cada arquivo depende da conta e das configurações. A documentação não oferece uma prova por arquivo de que uma cópia local é recuperável e não foi editada. Por isso, anexos do Mail ficam fora do catálogo removível nesta versão. A opção do próprio Mail de remover anexos também pode afetar cópias no servidor em contas IMAP, de acordo com a documentação.

O [guia da Apple sobre a Lixeira](https://support.apple.com/pt-br/guide/mac-help/mchlp1093/26/mac/26) informa que esvaziá-la apaga os itens permanentemente. Por isso a ação tem fluxo e aviso próprios.

## Teste isolado

```sh
swiftc -D DEBUG cleanup-mac/ScanScope.swift cleanup-mac/AnalysisModels.swift cleanup-mac/AnalysisCatalog.swift cleanup-mac/AnalysisExclusions.swift cleanup-mac/AnalysisEngine.swift cleanup-mac/CleanupModels.swift cleanup-mac/CleanupEngine.swift cleanup-mac/TrashEngine.swift tests/CleanupSmoke.swift -o /private/tmp/cleanup-mac-cleanup-smoke
CLEANUP_MAC_FIXTURE_HOME="$PWD/.fixtures/sample-home" /private/tmp/cleanup-mac-cleanup-smoke
```

O teste cria seus próprios arquivos na fixture, verifica seleção exata, mudança após análise, movimento, Lixeira, link simbólico e item alterado, e remove os dados temporários ao final. A [etapa 4](VALIDACAO.md) também cobre permissão negada, bloqueio consultivo, arquivo esparso grande e troca de caminho antes da execução. Ainda não há prova contra uma troca simultânea no instante exato do movimento.
