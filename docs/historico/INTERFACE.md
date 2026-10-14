# Interface — etapas 2 e 3

A tela usa a hierarquia do print fornecido como referência: navegação lateral, mensagem principal e ação de análise em destaque. Paleta, nome e textos foram criados para este projeto. A área inteira de cada botão lateral responde ao clique.

## Fluxo disponível

1. **Analisar agora** inicia a varredura da home definida por `ScanScope`. Em Debug, configure `CLEANUP_MAC_FIXTURE_HOME` com o caminho absoluto de `.fixtures/sample-home` na configuração Run do Xcode.
2. Durante a análise, a tela mostra categoria atual, itens verificados, itens encontrados e tamanho lógico parcial. **Cancelar análise** interrompe a tarefa; **Analisar novamente** cria uma nova leitura.
3. Os resultados separam **Encontrado** de **Selecionado para limpeza**. A revisão mostra caminho, tamanho, data e motivo; há seleção por item e grupo, abertura no Finder e exclusão persistente. A lista de exclusões fica na barra lateral.
4. **Revisar operação** abre uma prévia com quantidade, tamanho lógico estimado e destino planejado. **Confirmar e mover** executa apenas os itens selecionados, revalidados individualmente, e mostra sucessos e falhas.
5. **Limpeza adicional** mostra categorias de sistema, Xcode, Mail Downloads, backups e versões de documentos. Cada item exige seleção e confirmação; a tela avisa que versões são removidas permanentemente.
6. **Lixeira** abre uma inspeção separada da home e dos volumes montados acessíveis. **Revisar esvaziamento** mostra uma confirmação específica da exclusão permanente. Apenas itens medidos e revisados entram nessa operação.
7. **Desempenho** lista apps com interface em execução e mostra a memória residente (RSS) de cada processo principal, atualizada pelo botão **Atualizar lista**. O encerramento normal exige confirmação. A área também solicita a reindexação do Spotlight e o esvaziamento do cache DNS em Release, mostra o resultado dos comandos e abre os painéis do macOS para itens de início, atividade em segundo plano e processos. Em Debug, ações que alteram o estado do Mac ficam desativadas.
8. **Aplicativos** permite analisar apps em `/Applications` e `~/Applications`, selecionar um ou vários, revisar separadamente dados associados e possíveis resíduos, e mover itens confirmados para a Lixeira. A área também mostra instaladores antigos e oferece verificação manual de feeds de atualização compatíveis.
9. **Arquivos grandes** examina Mesa, Documentos, Downloads, Filmes, Música e Imagens para listar arquivos regulares de pelo menos 100 MB, em ordem de tamanho. Mostra tamanho lógico e espaço alocado estimado e permite revelar cada arquivo no Finder. Não percorre atalhos, pacotes de apps, pastas ocultas ou outros volumes; locais inacessíveis são contabilizados. Não remove arquivos.
10. **Organização** examina as mesmas seis pastas pessoais e mostra seus tamanhos lógicos somados, os 100 maiores arquivos de Downloads, arquivos sem alterações há pelo menos 365 dias, grupos de duplicados exatos e pares de imagens potencialmente semelhantes. Os duplicados têm mesmo tamanho e hash SHA-256 do conteúdo; só arquivos de 1 KiB ou mais são comparados. A semelhança visual usa um hash perceptual de 64 bits, aceita até cinco diferenças e proporções próximas; analisa no máximo 500 imagens regulares de até 40 MiB por varredura. Links, pacotes, arquivos ocultos e outros volumes ficam fora. A interface mostra até 100 itens antigos, 100 grupos duplicados e 50 pares semelhantes por vez e permite revelá-los no Finder. Não remove arquivos.
11. **Lupa de Espaço** constrói uma árvore de arquivos e pastas em Mesa, Documentos, Downloads, Filmes, Música e Imagens. Exibe tamanho lógico e barras proporcionais; permite revelar arquivos no Finder ou movê-los individualmente à Lixeira após confirmação em Release. Revalida identidade e caminho antes da ação; a remoção fica desativada em Debug. Links, outros volumes e conteúdo de pacotes ficam fora; uma análise com mais de 200.000 arquivos é marcada como incompleta.
12. **Cuidados Inteligentes** reúne contagens das análises locais de limpeza, limpeza adicional, organização, arquivos grandes e aplicativos. Cada cartão leva à respectiva tela para revisão; a análise conjunta não remove arquivos.

Erros parciais aparecem com o caminho afetado. O volume encontrado e selecionado é tamanho lógico; mover para a Lixeira não é apresentado como espaço liberado. Em Debug, `ScanScope` restringe análise e limpeza à fixture marcada, inclusive sua `.Trash`.

## Verificação funcional

O teste isolado usa a fixture e confere estados, análise, seleção individual e por grupo, totais e nova análise:

```sh
swiftc -D DEBUG cleanup-mac/ScanScope.swift cleanup-mac/AnalysisModels.swift cleanup-mac/AnalysisCatalog.swift cleanup-mac/AnalysisExclusions.swift cleanup-mac/AnalysisEngine.swift cleanup-mac/CleanupModels.swift cleanup-mac/CleanupEngine.swift cleanup-mac/TrashEngine.swift cleanup-mac/AnalysisViewModel.swift tests/AnalysisViewModelSmoke.swift -o /private/tmp/cleanup-mac-ui-smoke
CLEANUP_MAC_FIXTURE_HOME="$PWD/.fixtures/sample-home" /private/tmp/cleanup-mac-ui-smoke
```
