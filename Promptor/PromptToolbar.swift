import SwiftUI

struct PromptToolbar: ToolbarContent {
    @EnvironmentObject var vm: FileAggregator
    @Binding var showTemplatePicker: Bool

    var body: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                showTemplatePicker = true
            } label: {
                Label("Select Template", systemImage: "bookmark.ribbon")
            }
            .help("Select Template")

            Button {
                vm.toggleTreeExpansion()
            } label: {
                Label("Expand / Collapse All", systemImage: "plus.square.on.square")
            }
            .help("Expand or Collapse All Folders")

            Button { vm.refreshAll() } label: {
                Label("Refresh Files", systemImage: "arrow.clockwise")
            }
            .help("Force refresh file content")

            Button { vm.clearSelections() } label: {
                Label("Unselect All", systemImage: "xmark.rectangle")
            }
            .help("Unselect all files")

            Toggle(isOn: $vm.showRemoveIcons) {
                Label("Show Remove Button", systemImage: "eye.slash")
            }
            .toggleStyle(.button)
            .help("Hide / Show remove file button column")

            Button(role: .destructive) { vm.removeAll() } label: {
                Label("Remove All", systemImage: "trash")
            }
            .help("Remove all files from list")
        }
    }
} 
