import SwiftUI

struct TemplatePickerSheet: View {
    @EnvironmentObject var vm: FileAggregator
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                ForEach(templates, id: \.id) { template in
                    Button(template.name) {
                        vm.currentTemplate = template
                        vm.assemblePrompt()
                        dismiss()
                    }
                    .buttonStyle(TemplateButtonStyle())
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .navigationTitle("Select Template")
        }
        .frame(width: 300)
        .presentationCompactAdaptation(.popover)
    }
} 

fileprivate extension TemplatePickerSheet {
    /// The templates the user can choose from
    var templates: [Template] {
        [
            Template(name: "Default", format: "{{files}}"),
            Template(
                name: "ChatML",
                format: """
                <|im_start|>system
                You are a helpful assistant.<|im_end|>
                <|im_start|>user
                {{files}}
                <|im_end|>
                <|im_start|>assistant
                """
            )
        ]
    }
}

fileprivate struct TemplateButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            Circle()
                .fill(Color.blue)
                .frame(width: 5, height: 5)
            
            configuration.label
                .font(.callout)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 7)
        .opacity(configuration.isPressed ? 0.8 : 1)
        .background(
            configuration.isPressed ? AnyShapeStyle(Color.gray.opacity(0.1)) : AnyShapeStyle(.ultraThickMaterial),
            in: .rect(cornerRadius: 6)
        )
    }
}
