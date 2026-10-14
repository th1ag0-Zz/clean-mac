# Clean Mac

Aplicativo nativo SwiftUI para macOS 15+, reconstruído a partir do levantamento REA do CleanMyMac 5.7.1 instalado neste Mac e dos motores locais do projeto anterior. Interface, código e ícone próprios. Não exige conta, licença, API ou conexão de rede.

## Interface 1.1

A interface foi refeita a partir de observações do CleanMyMac em execução: sete módulos principais, cores por módulo, telas de entrada com ação circular, resumo de resultados, navegação compacta e painéis claros de revisão. Ferramentas secundárias ficam dentro dos módulos. Cuidados Inteligentes inclui auditoria local de proteção e progresso por etapas; Aplicativos e Acúmulos permitem cancelar suas análises. Atividades guarda um histórico local limitado de análises e operações registradas.

O motor local continua independente. A aparência e o fluxo se aproximam da referência, mas não há equivalência comprovada com todos os recursos do CleanMyMac. Veja [comparação e evidências](docs/FIDELIDADE.md).

## Executar

Abra `clean-mac.xcodeproj`, selecione o scheme **clean-mac** e execute no **My Mac**. Debug e Release analisam a home real. Em Ajustes, há um atalho para Acesso Total ao Disco; áreas protegidas permanecem sujeitas às permissões do macOS.

```sh
xcodebuild -project clean-mac.xcodeproj -scheme clean-mac \
  -configuration Release -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/clean-mac-release CODE_SIGNING_ALLOWED=NO build
```

O aplicativo fica em `/private/tmp/clean-mac-release/Build/Products/Release/Clean Mac.app`. Esse build serve para uso local. Distribuição exige configurar Developer ID e notarização.

## Recursos locais

- **Cuidados Inteligentes:** análise conjunta de limpeza, modelos locais, proteção, organização e aplicativos; abre os resultados já calculados para revisão.
- **Limpeza:** caches antigos, logs, relatórios de falha e instaladores.
- **Limpeza → dados do sistema, IA e Mail:** sistema, Xcode, anexos baixados do Mail, backups iOS, versões de documentos, modelos de Ollama/LM Studio/Hugging Face, registros de IA, preferências ilegíveis e arquivos de usuários apagados.
- **Proteção:** monitoramento opcional de alterações em pastas, persistência LaunchAgents/Daemons, permissões TCC acessíveis, Gatekeeper/FileVault/firewall e revisão de rastros dos navegadores. ClamAV instalado com assinaturas locais pode executar varredura offline; o verificador integrado reconhece apenas EICAR.
- **Desempenho:** CPU, RAM, disco, bateria, estado térmico, uptime, apps em execução, encerramento normal confirmado, Spotlight, DNS e inicialização.
- **Aplicativos:** desinstalação individual/em lote, dados associados, possíveis resíduos e instaladores antigos.
- **Acúmulos:** downloads, arquivos antigos, duplicados SHA256 e imagens semelhantes, com busca, seleção e remoção revisada.
- **Fotos locais:** Photos nativo, comparação de originais locais por SHA256/dHash e remoção confirmada para Apagados. Nunca solicita download do iCloud. A remoção pode sincronizar se o Fotos do iCloud estiver ativo.
- **Lupa de Espaço:** mapa de áreas proporcionais reais, navegação, escolha de pasta e remoção de arquivos individuais.
- **Otimizar aplicativos:** inventário de idiomas/binários universais e criação de cópia otimizada, mantendo o original. A cópia recebe assinatura ad hoc e pode ter restrições em atualizações e acesso a credenciais.
- **Ferramentas:** exclusão permanente revisada, DMGs somente leitura, verificação de disco, snapshots locais do Time Machine, compactação do índice Mail com backup, manutenção periódica quando disponível e limpeza de tela.
- **Barra de menus:** saúde do Mac. **Assistente local:** guia determinístico para encontrar ferramentas.

Nenhum arquivo é selecionado automaticamente. A remoção comum usa Lixeira; esvaziamento, versões antigas e exclusão definitiva têm confirmação própria. O mapa e os tamanhos lógicos não prometem espaço recuperável equivalente em APFS.

## Validação

```sh
python3 scripts/test_local.py
```

O runner compila os testes e usa exclusivamente `.fixtures/sample-home`, com marcador validado. Configure `CLEANUP_MAC_FIXTURE_HOME` com essa pasta para executar o app sobre a mesma fixture. Fotos e manutenção do sistema são bloqueadas nesse modo. Testes com NSFileVersion e SwiftUI podem precisar executar fora do sandbox do agente.

Veja [cobertura e diferenças](docs/COBERTURA.md), [validação](docs/VALIDACAO.md), [análise anterior](docs/ANALISE_CLEANMYMAC.md) e [prévia da interface](docs/preview-v1.1.png). O conteúdo de `docs/historico` registra o projeto anterior.
