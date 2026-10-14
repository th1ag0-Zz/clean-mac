> Registro da análise e da implementação anterior em `cleanup-mac`. A identidade do alvo foi reconfirmada em 14/10/2026. A coluna de cobertura abaixo descreve o projeto anterior; consulte [COBERTURA.md](COBERTURA.md) para este projeto.

# CleanMyMac instalado: levantamento de recursos

Alvo examinado: `/Applications/CleanMyMac_5.app`, versão **5.7.1** (`com.macpaw.CleanMyMac5`). O REA identificou o executável arm64 com SHA-256 `dd91651f7e204dc79652dc2ef3b9f16a859235d324021f17806cc5fdc90528fd` e leu o `Info.plist` (Evidence `ev_8c16a0e558079a54e668e5bbf604b20146312713b8ec111559eb3e5fd3f11b36`). A inspeção de artefato do pacote foi concluída pelo REA e retida como Evidence `ev_1ca94764359d2703e8a30d5ecf8204a9a14b5f7f3fde4f42aaf01c7ca3a8f440`; seu resultado completo excedeu o limite de transporte do cliente.

Os nomes abaixo aparecem como chaves `menu_item_view_*` em `Contents/Resources/pt-BR.lproj/Localizable.strings` do aplicativo instalado. Isso confirma seções expostas no pacote, mas **não** comprova detalhes de funcionamento, disponibilidade para esta licença ou equivalência entre implementações.

Após a instalação do Ghidra 12.1.4, o REA analisou uma fatia ARM64 extraída do executável universal: 27.171 procedimentos e 59.302 strings definidos pelo provedor (Evidence `ev_5aef1db0fe2965bf0b2beaea9c2ebc672a69c85977043b4b57ca8930aa192d02`). A busca de procedimentos encontrou referências a builders de Smart Care, Limpeza, Proteção, Organização, Lupa de Espaço e Nuvem (Evidence `ev_32344024954a98d599a0d9f577bfb0c60fecf47f42a9127c9698aa98e0525d1f`). A maioria dessas referências aponta para frameworks externos; os nomes confirmam estrutura e roteamento, não a lógica interna de cada módulo.

O REA observou a janela inicial em execução, com barra lateral para as seções abaixo, fundo roxo, destaque visual central e botão principal “Analisar” (Evidence `ev_93d476d55968f6d5a906247b85494016b3b638cd881aea67d4464408e7e6b557`). O catálogo de assets do pacote contém recursos nomeados para duplicados, fotos semelhantes, nuvem, malware e Lupa de Espaço (Evidence `ev_a9c3aa1148e9811eba0d04eff3d9b4a0e307c9d1f259ae27ce732e859952e563`). Esses nomes, por si, não provam o comportamento dos recursos.

| Seção observada no pacote | Cobertura no Cleanup Mac |
| --- | --- |
| Cuidados Inteligentes | Painel de análise local conjunta para limpeza, acúmulos, arquivos grandes e apps; abre cada área para revisão e ação. Não inclui verificação de malware nem atualização automática. |
| Limpeza | Análise e limpeza confirmada de categorias locais; escopo documentado em `MOTOR_DE_ANALISE.md` e `LIMPEZA_AVANCADA.md`. |
| Proteção | Sem mecanismo antimalware, monitoramento em tempo real ou auditoria de privacidade. |
| Desempenho | Visualização de apps e memória, encerramento confirmado, reindexação do Spotlight, esvaziamento do cache DNS e atalhos para controles do macOS. |
| Aplicativos | Desinstalação revisada, resíduos possíveis, instaladores antigos e consulta manual de atualizações compatíveis. |
| Acúmulos | Arquivos grandes, arquivos sem alterações há 365 dias, duplicados exatos e pares de imagens potencialmente semelhantes. Não percorre a biblioteca do Fotos. |
| Lupa de Espaço | Árvore navegável de seis pastas pessoais, barras proporcionais e remoção de arquivos individuais para a Lixeira após confirmação e revalidação. Não cobre todo o disco nem remove pastas inteiras. |
| Limpeza de Nuvem | Sem conexão com provedores de nuvem. |
| Assistente | Sem assistente contextual. |

Os recursos acrescentados a partir deste levantamento usam uma implementação própria. O agrupamento por hash prova igualdade dos bytes lidos durante a análise, mas não informa qual cópia é segura para remover. Arquivos antigos usam data de **modificação**, não último acesso. A soma de tamanhos não equivale a espaço recuperável no APFS.

As strings dos frameworks `SmartCareModule`, `SpaceLensModule`, `OrganizeModule`, `PerformanceModule` e `ProtectionModule` em `pt-BR.lproj` foram lidas para mapear os fluxos. Elas identificam, entre outros, análise combinada, navegação por pastas, Downloads, manutenção DNS, permissões, privacidade e malware. A presença de textos no pacote não demonstra o algoritmo nem implica que a função esteja implementada neste projeto. O scanner da Lupa limita a análise a 200.000 arquivos e informa quando o resultado está incompleto.

O framework `OrganizeScanning` foi analisado separadamente pelo Ghidra. Procedimentos identificados incluem regras específicas para duplicados e imagens semelhantes, além de `CMImageHashForImage` (Evidence `ev_cc1697e35555135d71b40a538bc10c2e09614949d3ecf9ed3d1531f384fe8755`). A função nativa usa CoreGraphics e vImage para reduzir dados de imagem e produzir um hash visual; o pseudocódigo é uma reconstrução do descompilador e não revela todas as regras de agrupamento do produto (Evidence `ev_1f9a8fca68babd99ba1693627c0efee758c6b25adc1a4ea8ba81bb10b9c36035`). O Cleanup Mac usa um hash perceptual próprio, com limites explícitos e revisão manual. Não afirma resultados idênticos aos do CleanMyMac.

A interface do Cleanup Mac recebeu uma adaptação da hierarquia visual observada: barra lateral com seleção translúcida, fundo em tons de roxo, chamada principal e ilustração própria em SwiftUI. Os textos e destinos da navegação continuam ligados apenas às funções presentes no projeto. Nenhum asset do CleanMyMac foi copiado para o build.
