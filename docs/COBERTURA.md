# Cobertura local e evidências

## Identidade e origem

Em 14/10/2026, REA abriu `/Applications/CleanMyMac_5.app/Contents/MacOS/CleanMyMac_5`: arm64, SHA256 `dd91651f7e204dc79652dc2ef3b9f16a859235d324021f17806cc5fdc90528fd`, idêntico ao alvo da análise anterior. A leitura do plist confirmou versão 5.7.1, bundle `com.macpaw.CleanMyMac5`.

- Plist: `ev_8c16a0e558079a54e668e5bbf604b20146312713b8ec111559eb3e5fd3f11b36`.
- Mach-O/dependências: `ev_82f8ee46c186f690dac2d9875b71e1ff775dd2afe623b763b39f72464015797f`.
- Observações completas: [rea-original-observations.json](rea-original-observations.json).
- Hierarquia visual e algoritmos nativos anteriormente examinados: [ANALISE_CLEANMYMAC.md](ANALISE_CLEANMYMAC.md), com os IDs históricos. O servidor atual não conservava a sessão anterior; esses IDs são referências do relatório histórico.

O REA atual não tem Ghidra/Hopper/IDA configurados. O levantamento anterior do mesmo binário foi reaproveitado; não se afirma nova descompilação completa. Strings portuguesas dos frameworks locais também foram lidas como dados do pacote. Elas comprovam rótulos e recursos declarados, sem provar algoritmos ou execução.

## Implementação

| Área observada | Implementação neste projeto | Limite material |
| --- | --- | --- |
| Smart Care | Agrega análises locais e reaproveita resultados nas telas | Não inclui automaticamente Photos ou varredura antimalware |
| Detritos | Catálogo de caches/logs/instaladores e áreas adicionais | Regras conservadoras de idade; permissões do sistema respeitadas |
| IA local | Modelos e caches em caminhos conhecidos | Remoção de diretórios revisada; nenhum modelo baixado |
| Mail | Downloads de anexos e compactação do índice com backup SQLite | Não remove anexos diretamente do banco de mensagens |
| Lixeiras | Home e volumes acessíveis; revisão antes de apagar | Esvaziamento é permanente; volumes sem acesso são reportados |
| Aplicativos | Apps, dados associados por bundle ID, resíduos possíveis | Identificação conservadora; não promete localizar todo arquivo criado por cada app |
| Idiomas/binários universais | Otimização de uma cópia do aplicativo | Assinatura ad hoc pode afetar comportamento e atualizações; original preservado |
| Duplicados | SHA256 dos arquivos, seleção e revalidação de cópia preservada | Hash prova bytes iguais, não qual cópia o usuário deve conservar |
| Imagens semelhantes | dHash próprio, revisão visual | Comparação aproximada, até 500 arquivos de 40 MB nas pastas pessoais |
| Photos | API nativa, originais locais SHA256/dHash | Até 300 fotos recentes, 16 MB/foto e 256 MB/rodada; Live Photo vídeo e edições não comparados |
| Space Lens | Treemap proporcional e árvore navegável, pasta escolhida | Até 200 mil entradas; links, pacotes e locais cloud omitidos; Trash individual |
| Segurança | Monitoramento opcional FSEvents, persistência, controles macOS, TCC e rastros dos navegadores | Auditoria não é certificação antimalware; ClamAV requer programa/base local |
| Privacidade | Bancos de histórico/cookies revisados por navegador fechado | TCC pode exigir FDA; histórico Firefox preservado porque compartilha favoritos |
| Saúde/desempenho | Métricas Darwin/IOKit e tarefas nativas | RAM dos apps usa processo principal; não promete purga ou espaço recuperado |
| Manutenção | Spotlight, DNS, Time Machine, Mail, verificação de volume, scripts existentes | Reparação antiga de permissões de disco não é suportada pelo macOS atual |
| Ferramentas | Apagar arquivos, DMG readonly, tela preta | SSD/APFS impedem garantia de sobrescrita segura; tela não bloqueia teclado/trackpad |
| Assistente | Guia de navegação por regras locais | Sem modelo generativo ou equivalência ao assistente cloud |

Não foram integrados Drive/Dropbox/Gmail/OneDrive, contas, licenciamento, atualizações por feed, telemetria, dicas cloud ou APIs de IA. Não há código de rede no app. O motor proprietário Moonlock e seu catálogo de ameaças não foram copiados: auditoria local e integração opcional ClamAV são alternativas explicitamente identificadas.

Esta é uma reconstrução funcional independente. Os testes validam a implementação própria; não demonstram paridade integral com o produto proprietário.

## Segurança das operações

Os motores revalidam caminho, identidade e metadados antes de mover itens. A remoção de duplicados revalida o hash de uma cópia mantida. Links e pacotes são rejeitados nos fluxos de arquivos pessoais. O modo fixture usa a pasta marcada deste projeto, independente de Debug/Release. Mudanças em documentos, Photos e preferências do sistema usam as APIs do macOS e continuam sujeitas à autorização do usuário.

O build tem sandbox de aplicativo desativado para a distribuição direta planejada. Isso é necessário para análise ampla do Mac; não concede Acesso Total ao Disco nem direitos administrativos automaticamente. Comandos administrativos fixos usam a autorização nativa do macOS após confirmação na interface.
