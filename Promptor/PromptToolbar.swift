import SwiftUI

struct PromptToolbar: ToolbarContent {
    @EnvironmentObject var vm: FileAggregator
    @State private var showTemplatePicker: Bool = false

    var body: some ToolbarContent {
        ToolbarItemGroup {
            Button("Template", systemImage: "book.and.wrench") {
                showTemplatePicker = true
            }
            .help("Select Template")
            .popover(isPresented: $showTemplatePicker, content: TemplatePickerSheet.init)
            
            if vm.hasFiles {
                Button("Expand / Collapse All", systemImage: "plus.square.on.square", action: vm.toggleTreeExpansion)
                    .help("Expand or Collapse All Folders")
                
                Button("Refresh Files", systemImage: "arrow.clockwise", action: vm.reloadContents)
                    .help("Force refresh file content")
                
                Button("Remove All", systemImage: "trash", action: vm.removeAll)
                    .tint(.red)
                    .help("Remove all files from list")
            }
        }
    }
} 


extension FileAggregator {
    var hasFiles: Bool {
        rootNode != nil
    }
}
