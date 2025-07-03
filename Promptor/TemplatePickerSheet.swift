import SwiftUI

struct TemplatePickerSheet: View {
    @EnvironmentObject var vm: FileAggregator
    @Environment(\.dismiss) private var dismiss
    
    /// The templates the user can choose from
    private let templates: [Template] = [
        .init(name: "Default", format: "{{files}}"),
        .init(
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
    var body: some View {
        NavigationView {
            List {
                ForEach(templates, id: \.id) { tpl in
                    Button(tpl.name) {
                        vm.currentTemplate = tpl
                        vm.assemblePrompt()
                        dismiss()
                    }
                }
            }
            .navigationTitle("Select Template")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close", action: dismiss.callAsFunction)
                }
            }
        }
        .frame(width: 300, height: 300)
        .presentationCompactAdaptation(.popover)
    }
} 