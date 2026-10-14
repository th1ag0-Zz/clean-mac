# Interface e fluxo — revisão 1.1

A revisão substitui a organização herdada do app anterior por uma estrutura baseada no CleanMyMac 5.7.1 observado em execução em 14/10/2026. Os motores locais continuam independentes. Não há alegação de equivalência integral com o original.

## Referência observada

Alvo: `/Applications/CleanMyMac_5.app/Contents/MacOS/CleanMyMac_5`, arm64, SHA256 `dd91651f7e204dc79652dc2ef3b9f16a859235d324021f17806cc5fdc90528fd`.

REA capturou a árvore de acessibilidade e screenshots das entradas Cuidados Inteligentes, Limpeza, Proteção, Desempenho, Aplicativos, Acúmulos e Lupa de Espaço. Uma análise de Aplicativos no original foi executada, seguida de abertura de Gerenciar Aplicativos; nenhuma remoção foi executada no original.

Os registros completos de texto, identidades, ações, dimensões e hashes dos screenshots estão em [rea-fidelity-observations.json](rea-fidelity-observations.json). O JSON omite os bytes das imagens para evitar duplicação de arquivos grandes. A sessão preservou Evidence IDs.

| Observação | Implementação 1.1 |
| --- | --- |
| Sete áreas locais principais e ferramentas separadas | Sidebar simplificada; utilitários secundários dentro dos módulos |
| Cores diferentes por módulo | Verde/rosa/laranja/azul/turquesa/roxo |
| Ilustração à esquerda, conteúdo à direita, ação circular abaixo | `ModuleLandingView`, arte vetorial independente e botão Analisar |
| Sidebar reduzida a ícones durante revisão | Estado compacto para análises/resultados dos módulos gerenciados |
| Resumo após análise e gerenciamento detalhado | Aplicativos apresenta resumo e abre gerenciador claro, com busca, ordenação, categorias e seleção |
| Revisão em superfície clara | Aplicativos, Acúmulos e Limpeza usam painéis claros |
| Áreas de Limpeza: sistema, IA, Mail e lixos | Novo `CleanupModuleView` agrega os motores existentes e conserva a revisão de cada ação |

A organização dos resultados dos demais módulos é uma reconstrução: as telas de resultados de todos os módulos do original não foram capturadas. Os efeitos tridimensionais são aproximações vetoriais próprias, e não os assets originais.

## Comportamento melhorado

- Cuidados Inteligentes executa etapas reais, inclui auditoria local de proteção e agrega avisos também de limpeza e aplicativos. Resultados preservados abrem diretamente a revisão.
- Aplicativos e Acúmulos têm cancelamento de análise e identificador de execução para impedir que uma tarefa cancelada substitua resultados mais novos.
- Limpeza agrupa seleção, busca, detalhes, exclusões e confirmações dos motores básico e avançado.
- Desempenho separa manutenção, inicialização e apps em execução. Ferramentas usa catálogo compacto com detalhe individual.
- Lupa de Espaço permite cancelar, navegar pelo caminho e alternar mapa/lista.
- Atividades persiste até 100 registros locais das análises e operações observadas pela tela principal. Não é um log completo de todas as ações do sistema.

## Verificação

- Compilações Debug e Release arm64 aprovadas. O aviso de metadados AppIntents é do Xcode; o app não usa esse framework.
- 17 testes locais aprovados, incluindo o novo `SmartCareSmoke` (etapas, avisos, cancelamento e substituição de análise). Log: `/private/tmp/clean-mac-fidelity-tests.log`.
- Release aberto com `CLEANUP_MAC_FIXTURE_HOME`, análise conjunta concluída, revisão de limpeza aberta, resumo/gerenciador de aplicativos abertos, checkbox selecionado, confirmação de remoção aberta e cancelada. Navegação por Proteção, Desempenho, Acúmulos, Lupa de Espaço, Ferramentas e Atividades conferida pelo REA.
- Evidências: [rea-fidelity-validation.json](rea-fidelity-validation.json). Não se executou remoção de arquivos pessoais reais.
- [Prévia 1.1](preview-v1.1.png).

## Diferenças mantidas

Recursos de nuvem e atualização pela internet ficam fora do escopo. A proteção local não reproduz o Moonlock: usa auditoria e ClamAV local quando disponível; sem ClamAV, o verificador de conteúdo integrado reconhece somente EICAR. Escopos, limites de leitura, permissões e operações de cada motor permanecem descritos em [COBERTURA.md](COBERTURA.md). A Lupa usa treemap, não o mapa de círculos do original. Fotos, idiomas e algumas ferramentas mantêm interfaces próprias. O build é para uso local, sem notarização de distribuição.

## Artefato final

Versão 1.1 (build 2), Release arm64. Executável SHA256: `5a8b29e11d47caeeed11f0325620bec1b566bf64dcbd3141faf2763aa114bdbd`. O ajuste final compacta a lista de categorias da Limpeza e mantém seleção/ação visíveis abaixo da lista. A análise conjunta de limpeza foi repetida na fixture com esse binário; [evidência final](rea-final-cleanup.json) e [screenshot final da limpeza](preview-cleanup-v1.1.png).

`Clean-Mac.dmg` foi atualizado na raiz pelo script de empacotamento, com `hdiutil verify` aprovado. O instalador contém esse Release e o atalho para Aplicativos. O modo fixture é definido apenas na execução de teste, não no app empacotado.
