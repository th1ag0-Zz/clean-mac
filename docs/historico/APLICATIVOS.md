# Aplicativos — V2

**Aplicativos** analisa bundles `.app` diretamente em `/Applications` e `~/Applications`. Apps do macOS, links simbólicos e o próprio Cleanup Mac ficam fora. A remoção individual ou em lote exige seleção e confirmação; cada resultado informa o que foi movido para a Lixeira e o que falhou. Apps em execução são recusados.

Dados associados aparecem separadamente e não são selecionados junto com o app. A correspondência usa o identificador exato do bundle em `~/Library/Application Support`, `Caches`, `Containers`, `HTTPStorages`, `WebKit`, `Preferences/<id>.plist` e `Saved Application State/<id>.savedState`. Se há mais de uma instalação com o mesmo identificador, os dados associados não são sugeridos. Dados selecionados só são movidos se o app correspondente foi movido com sucesso.

**Possíveis resíduos** são itens nesses mesmos locais cujo identificador não foi encontrado nos apps analisados nem no registro de apps do macOS. Essa classificação não prova que os dados estão sem uso: uma instalação fora das pastas analisadas ou outro usuário pode precisar deles. Itens compartilhados, dados sem identificador exato, documentos e extensões do sistema ficam fora. Para apps com desinstalador próprio, prefira o desinstalador fornecido pelo desenvolvedor, que pode remover componentes que esta análise não conhece.

**Instaladores antigos** reaproveita a regra da análise principal: `.dmg` e `.pkg` diretamente em `~/Downloads`, sem alterações há pelo menos 30 dias. A limpeza usa a mesma validação de identidade e exclusões da análise principal.

**Atualizações** abre a App Store para a lista oficial de atualizações dos apps instalados por ela. Para apps com `SUFeedURL` HTTPS no bundle, um botão consulta o appcast Sparkle e compara a versão publicada com `CFBundleVersion`; o resultado é uma indicação de possível atualização. O app não instala versões, não consulta feeds automaticamente e não declara apps sem feed como atualizados. Compatibilidade de sistema, canais beta e regras próprias do atualizador devem ser verificados pelo app de origem.

Em Debug, a análise e a remoção de arquivos usam somente `.fixtures/sample-home`. O teste `tests/ApplicationsSmoke.swift` confirma descoberta, seleção, movimento para a Lixeira, recusa de item alterado e leitura de versão de appcast. Builds Debug e Release também devem ser compilados antes de distribuição.
