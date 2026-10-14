# Preparação técnica — etapa 0

## Plataforma e distribuição

- Alvo único: macOS 15.0 ou posterior. O projeto não inclui iOS ou visionOS.
- Distribuição pretendida: download direto do aplicativo. Na entrega, configurar identidade Developer ID, assinatura e notarização. O hardened runtime está habilitado no projeto; não há artefato de distribuição nesta etapa.
- App Sandbox desativado. O escopo da V1 exige examinar locais de `~/Library` sem fazer a pessoa selecionar cada pasta. O app continua sujeito às permissões normais e às proteções de privacidade do macOS. Não solicitar acesso total ao disco nem privilégios de administrador nesta etapa.
- A análise e a limpeza devem continuar restritas ao catálogo explícito da V1, com revisão, confirmação e revalidação imediatamente antes da operação. A ausência de sandbox não amplia o catálogo permitido.

## Desenvolvimento sem arquivos reais

1. Execute `python3 scripts/create_fixtures.py` na raiz do repositório. O script cria `.fixtures/sample-home` e falha se a pasta já existir. `.fixtures/` é ignorada pelo Git.
2. Defina `CLEANUP_MAC_FIXTURE_HOME` com o caminho absoluto exibido pelo script na configuração **Run > Arguments > Environment Variables** do esquema do Xcode. Para execução por terminal, use a mesma variável de ambiente.
3. Todo código de análise e limpeza adicionado nas próximas etapas deve obter a home por `ScanScope.homeDirectory()`. Em Debug, a função exige exatamente a pasta `.fixtures/sample-home` deste repositório, sem link simbólico e com o marcador `.cleanup-mac-fixture`; sem ela, a análise deve falhar fechada. Em Release, a função retorna a home do usuário.
4. Nunca usar `FileManager.default.homeDirectoryForCurrentUser`, `NSHomeDirectory()` ou caminhos `~/Library` diretamente no motor. Testes devem injetar a home da fixture e criar cópias próprias para cenários que a alterem.

A fixture inclui logs, caches, relatório de falha, instaladores antigos e recentes, item na Lixeira, documento pessoal e links simbólicos para o documento. As regras atuais estão em [Motor de análise](MOTOR_DE_ANALISE.md). Os testes adicionais de arquivo em uso, permissão negada, troca de caminho, alteração após análise e arquivo esparso grande constam da [matriz de validação](VALIDACAO.md).

## Verificações antes da etapa 1

- O build Debug deve compilar apenas para macOS.
- O gerador de fixtures só escreve em `.fixtures/sample-home` e nunca substitui uma fixture existente.
- O motor já usa `ScanScope.homeDirectory()`. Antes de conectar o botão **Analisar**, a interface deve mostrar o erro se a fixture Debug não estiver configurada.

Referências Apple: [App Sandbox e acesso a arquivos](https://developer.apple.com/documentation/security/app_sandbox) e [preparação para distribuição](https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution).
