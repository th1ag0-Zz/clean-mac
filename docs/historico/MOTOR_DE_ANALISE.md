# Motor de análise — etapa 1

`AnalysisEngine.analyze()` é chamado com `await` por ser isolado em um ator, pode ser chamado novamente para atualizar os resultados e lança `CancellationError` quando a tarefa chamadora é cancelada. O motor não é isolado no ator principal. Em Debug, só aceita a home marcada de `.fixtures/sample-home`.

## Catálogo inicial

| Categoria | Local | Regra | Seleção inicial |
| --- | --- | --- | --- |
| Logs antigos | `~/Library/Logs` e subpastas | Arquivos regulares `.log`, sem alteração há pelo menos 30 dias | Nenhuma |
| Relatórios de falha | `~/Library/Logs/DiagnosticReports` e subpastas | Arquivos `.ips`, `.crash` e `.diag`, sem alteração há pelo menos 30 dias | Nenhuma |
| Caches de aplicativos | `~/Library/Caches` e subpastas | Arquivos regulares, sem alteração há pelo menos 30 dias | Nenhuma |
| Instaladores antigos | Arquivos diretamente em `~/Downloads` | `.dmg` e `.pkg`, sem alteração há pelo menos 30 dias | Nenhuma |

O catálogo trata arquivos em `~/Library/Caches` como caches, mas o usuário deve revisar cada item: alguns aplicativos podem guardar dados úteis ali. Não percorre links simbólicos, arquivos de outro volume, arquivos com múltiplos links físicos nem profundidade superior a 16 subpastas. Arquivos fora dos locais listados não entram nos resultados. Instaladores em subpastas de Downloads ficam de fora.

Cada candidato contém caminho, categoria, tamanhos lógico e alocado, data de modificação, motivo, confiança conservadora, identidade do arquivo e estado de seleção. A soma de espaço encontrado representa bytes lógicos dos candidatos, sem deduplicar espaço compartilhado por mecanismos do sistema de arquivos como clones APFS. Nenhum byte é apresentado como efetivamente liberado nesta etapa.

Erros de acesso, mudanças detectadas durante a análise, arquivos com bloqueio consultivo e falhas de leitura são registrados por caminho como resultados parciais. Um arquivo aberto sem bloqueio consultivo pode aparecer; a limpeza revalida identidade, metadados e elegibilidade imediatamente antes de agir. Um processo que não coopera com bloqueios consultivos ainda pode manter o arquivo aberto.

Exclusões usam caminhos relativos à home em `UserDefaults`. Excluir uma pasta omite também seus descendentes na próxima análise. Repetir `analyze()` refaz a leitura e aplica as exclusões atualizadas.

## Verificação da fixture

Após `python3 scripts/create_fixtures.py` e com a fixture configurada, o teste de fumaça pode ser compilado e executado no terminal:

```sh
swiftc -D DEBUG cleanup-mac/ScanScope.swift cleanup-mac/AnalysisModels.swift cleanup-mac/AnalysisCatalog.swift cleanup-mac/AnalysisExclusions.swift cleanup-mac/AnalysisEngine.swift tests/AnalysisSmoke.swift -o /private/tmp/cleanup-mac-analysis-smoke
CLEANUP_MAC_FIXTURE_HOME="$PWD/.fixtures/sample-home" /private/tmp/cleanup-mac-analysis-smoke
```

O teste verifica o catálogo, a ausência de itens fora das regras e links simbólicos, totais, seleção inicial vazia, exclusões persistentes, nova análise e cancelamento.
