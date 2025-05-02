import SwiftUI

struct ImportOptionsSheet: View {
    let folderURL: URL
    @State var settings: AppSettings
    var completion: (Bool, AppSettings) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Folder")
                .font(.title3.bold())

            Text("Adding **\(folderURL.lastPathComponent)** to the context list")
                .foregroundStyle(.secondary)

            // ───────── SUB-FOLDER HANDLING ─────────
            Text("Sub-folders Handling")
                .font(.headline)

            Picker("", selection: $settings.includeSubfolders) {
                Text("Include files from sub-folders").tag(true)
                Text("Exclude files from sub-folders").tag(false)
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()

            // ───────── IGNORE SUFFIXES ─────────
            LabeledContent("Ignore file suffixes (comma-separated):") {
                TextField("e.g. .env,.class", text: Binding(
                    get: { settings.ignoreSuffixes.sorted().joined(separator: ",") },
                    set: { settings.ignoreSuffixes = Set($0.split(separator: ",").map{ "." + $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) }) }
                ))
                .textFieldStyle(.roundedBorder)
            }

            // ───────── IGNORE FOLDERS ─────────
            LabeledContent("Ignore folders (comma-separated):") {
                TextField("e.g. build,dist,.next", text: Binding(
                    get: { settings.ignoreFolders.sorted().joined(separator: ",") },
                    set: { settings.ignoreFolders = Set($0.split(separator: ",").map{ $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }) }
                ))
                .textFieldStyle(.roundedBorder)
            }

            Text("Media files, binary files and files larger than **\(settings.maxFileSize/1024) KB** are automatically ignored.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // ───────── ACTIONS ─────────
            HStack {
                Button("Reset to default") { settings = AppSettings() }
                Spacer()
                Button("Cancel")  { completion(false, settings) }
                Button("Confirm") { completion(true,  settings) }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
} 