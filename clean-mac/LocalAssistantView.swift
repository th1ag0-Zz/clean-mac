import SwiftUI

/// Offline guide: deterministic keyword routing, no language model or network.
struct LocalAssistantView: View {
    let navigate: (ContentView.Section) -> Void
    @State private var query = ""
    @State private var answer: GuideAnswer?
    struct GuideAnswer {
        let title: String
        let detail: String
        let destination: ContentView.Section
    }
    private let suggestions = ["O disco está cheio", "Meu Mac está lento", "Remover um aplicativo", "Encontrar arquivos duplicados", "Revisar minha privacidade"]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Label("Assistente local", systemImage: "sparkles").font(.system(size: 36, weight: .semibold, design: .rounded))
            Text("Um guia de manutenção que funciona sem internet. Descreva o que você quer fazer e encontre a ferramenta adequada.")
                .foregroundStyle(AppStyle.muted)
            HStack {
                TextField("Como posso cuidar do seu Mac?", text: $query).textFieldStyle(.plain).onSubmit { respond() }
                    .accessibilityIdentifier("assistant.query")
                Button { respond() } label: { Image(systemName: "arrow.up.circle.fill").font(.system(size: 27)) }
                    .buttonStyle(.plain).foregroundStyle(AppStyle.mint).disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Buscar orientação")
            }.padding(18).background(AppStyle.card, in: RoundedRectangle(cornerRadius: 15))
            if let answer {
                VStack(alignment: .leading, spacing: 14) {
                    Label(answer.title, systemImage: answer.destination.icon).font(.title3.bold())
                    Text(answer.detail).foregroundStyle(AppStyle.muted)
                    ActionButton(title: "Abrir \(answer.destination.title)", icon: "arrow.right") { navigate(answer.destination) }
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppStyle.card, in: RoundedRectangle(cornerRadius: 18))
            } else {
                Text("POR ONDE COMEÇAR").font(.system(size: 10, weight: .bold)).tracking(2).foregroundStyle(AppStyle.muted)
                ForEach(suggestions, id: \.self) { suggestion in
                    Button { query = suggestion; respond() } label: {
                        HStack { Text(suggestion); Spacer(); Image(systemName: "arrow.up.left") }
                            .padding(16).background(AppStyle.card, in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain)
                }
            }
            Text("Este guia usa regras locais para orientar a navegação. As ferramentas mostram os dados reais após a análise.")
                .font(.caption).foregroundStyle(AppStyle.muted)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func respond() {
        let text = query.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if ["lento", "ram", "memoria", "cpu", "bateria", "dns", "spotlight", "inicio"].contains(where: text.contains) {
            answer = GuideAnswer(title: "Confira o desempenho", detail: "Veja CPU, memória e aplicativos em execução. Salve seu trabalho antes de encerrar um app. Você também pode revisar tarefas de manutenção e itens de início.", destination: .performance)
        } else if ["privacidade", "virus", "malware", "seguranca", "permiss", "cookie", "historico"].contains(where: text.contains) {
            answer = GuideAnswer(title: "Revise a proteção local", detail: "Confira persistência, permissões e vestígios de navegadores. A auditoria local apresenta os limites da verificação e não certifica que o Mac está livre de ameaças.", destination: .protection)
        } else if ["aplicativo", "app", "desinstal", "residuo"].contains(where: text.contains) {
            answer = GuideAnswer(title: "Remova apps e revise seus dados", detail: "Analise os aplicativos instalados, escolha os apps e confira os arquivos associados antes de mover os itens para a Lixeira.", destination: .applications)
        } else if ["duplic", "foto", "imagem", "antigo", "download", "organiz"].contains(where: text.contains) {
            answer = GuideAnswer(title: "Encontre acúmulos", detail: "Compare duplicados pelo conteúdo, revise imagens semelhantes e veja downloads e arquivos antigos. Mantenha pelo menos uma cópia dos arquivos repetidos.", destination: .organization)
        } else if ["grande", "ocupa", "disco", "espaco", "cheio", "armazenamento"].contains(where: text.contains) {
            answer = GuideAnswer(title: "Veja onde o espaço está", detail: "A Lupa de Espaço mostra o tamanho real dos arquivos em cada pasta. Navegue pelo mapa, revele arquivos no Finder e revise o que pretende remover.", destination: .spaceLens)
        } else if ["ia", "modelo", "xcode", "backup", "mail", "anexo"].contains(where: text.contains) {
            answer = GuideAnswer(title: "Revise a limpeza adicional", detail: "Analise dados gerados pelo Xcode, anexos baixados, backups locais e modelos de IA. Confira se seus projetos ainda dependem dos arquivos antes de remover.", destination: .advanced)
        } else {
            answer = GuideAnswer(title: "Comece pelos Cuidados Inteligentes", detail: "Faça uma análise conjunta das áreas locais e abra cada resultado para revisar. Você também pode procurar por espaço, duplicados, aplicativos, desempenho ou privacidade.", destination: .smartCare)
        }
    }
}
