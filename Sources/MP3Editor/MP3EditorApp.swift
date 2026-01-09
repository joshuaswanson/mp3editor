import SwiftUI
import UniformTypeIdentifiers
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

@main
struct MP3EditorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}

// Helper to run the Python tag script
struct TagHelper {
    static var resourcesDir: URL {
        // Try app bundle first
        if let bundleResources = Bundle.main.resourceURL {
            return bundleResources
        }
        // Fallback: look relative to executable
        let executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        let resourcesPath = executableURL.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources")
        if FileManager.default.fileExists(atPath: resourcesPath.path) {
            return resourcesPath
        }
        // Final fallback for development: source directory
        return URL(fileURLWithPath: #file).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    static var scriptPath: String {
        resourcesDir.appendingPathComponent("mp3tags.py").path
    }

    static var pythonPath: String {
        // Use venv Python if it exists
        let venvPython = resourcesDir.appendingPathComponent("venv/bin/python").path
        if FileManager.default.fileExists(atPath: venvPython) {
            return venvPython
        }
        // Fallback to system Python
        return "/usr/bin/python3"
    }

    struct TagData: Codable {
        var title: String?
        var artist: String?
        var album: String?
        var genre: String?
        var year: String?
        var track: String?
        var disc: String?
        var bpm: String?
        var compilation: Bool?
        var artwork_data: String?
        var artwork_mime: String?
        var artwork_delete: Bool?
        var error: String?
        var success: Bool?
    }

    static func readTags(from path: String) -> TagData {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = [scriptPath, "read", path]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()

            // Read data BEFORE waitUntilExit to avoid pipe buffer deadlock
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            return try JSONDecoder().decode(TagData.self, from: data)
        } catch {
            return TagData(error: error.localizedDescription)
        }
    }

    static func writeTags(to path: String, data: TagData) -> TagData {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = [scriptPath, "write", path]

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()

            let jsonData = try JSONEncoder().encode(data)
            inputPipe.fileHandleForWriting.write(jsonData)
            inputPipe.fileHandleForWriting.closeFile()

            // Read data BEFORE waitUntilExit to avoid pipe buffer deadlock
            let resultData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            return try JSONDecoder().decode(TagData.self, from: resultData)
        } catch {
            return TagData(error: error.localizedDescription)
        }
    }
}

struct ContentView: View {
    @State private var filePath: String? = nil
    @State private var fileName: String = ""
    @State private var title: String = ""
    @State private var artist: String = ""
    @State private var album: String = ""
    @State private var genre: String = ""
    @State private var year: String = ""
    @State private var track: String = ""
    @State private var disc: String = ""
    @State private var bpm: String = ""
    @State private var isCompilation: Bool = false
    @State private var artworkData: Data? = nil
    @State private var artworkMime: String? = nil
    @State private var artworkDeleted: Bool = false
    @State private var isDragging = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var saveAsCopy = true
    @State private var showOverwriteWarning = false
    @State private var showUncheckedWarning = false

    // Original values for restore
    @State private var originalTitle: String = ""
    @State private var originalArtist: String = ""
    @State private var originalAlbum: String = ""
    @State private var originalGenre: String = ""
    @State private var originalYear: String = ""
    @State private var originalTrack: String = ""
    @State private var originalDisc: String = ""
    @State private var originalBpm: String = ""
    @State private var originalIsCompilation: Bool = false
    @State private var originalArtworkData: Data? = nil

    var hasFile: Bool {
        filePath != nil
    }

    var hasChanges: Bool {
        title != originalTitle || artist != originalArtist || album != originalAlbum ||
        genre != originalGenre || year != originalYear || track != originalTrack ||
        disc != originalDisc || bpm != originalBpm || isCompilation != originalIsCompilation ||
        artworkData != originalArtworkData || artworkDeleted
    }

    var body: some View {
        VStack(spacing: 18) {
            // Drop zone
            DropZoneView(
                fileName: fileName,
                isDragging: $isDragging,
                onTap: selectFile,
                onClear: clearFile,
                onDrop: handleDrop
            )

            // Fields
            FieldsCard(
                title: $title,
                artist: $artist,
                album: $album,
                genre: $genre,
                year: $year,
                track: $track,
                disc: $disc,
                bpm: $bpm,
                isCompilation: $isCompilation,
                artworkData: $artworkData,
                artworkMime: $artworkMime,
                artworkDeleted: $artworkDeleted,
                isEnabled: hasFile
            )

            // Bottom bar
            HStack {
                Toggle("Save as copy", isOn: Binding(
                    get: { saveAsCopy },
                    set: { newValue in
                        if !newValue {
                            showUncheckedWarning = true
                        } else {
                            saveAsCopy = true
                        }
                    }
                ))
                    .toggleStyle(.checkbox)
                    .disabled(!hasFile)

                Spacer()

                Button("Restore", action: restoreOriginal)
                    .disabled(!hasChanges)

                Button("Save Changes") {
                    if saveAsCopy {
                        saveFile()
                    } else {
                        showOverwriteWarning = true
                    }
                }
                .disabled(!hasFile)
            }
        }
        .padding(25)
        .frame(width: 520, height: 680)
        .contentShape(Rectangle())
        .onTapGesture {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
        .alert("MP3 Editor", isPresented: $showAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
        .alert("Overwrite Original File?", isPresented: $showOverwriteWarning) {
            Button("Cancel", role: .cancel) { }
            Button("Overwrite", role: .destructive) {
                saveFile()
            }
        } message: {
            Text("This will modify the original file. This action cannot be undone.")
        }
        .alert("Disable Save as Copy?", isPresented: $showUncheckedWarning) {
            Button("Cancel", role: .cancel) { }
            Button("Disable", role: .destructive) {
                saveAsCopy = false
            }
        } message: {
            Text("With this option disabled, saving will overwrite the original file.")
        }
    }

    func selectFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.mp3]
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            loadFile(url: url)
        }
    }

    func clearFile() {
        filePath = nil
        fileName = ""
        title = ""
        artist = ""
        album = ""
        genre = ""
        year = ""
        track = ""
        disc = ""
        bpm = ""
        isCompilation = false
        artworkData = nil
        artworkMime = nil
        artworkDeleted = false
        originalTitle = ""
        originalArtist = ""
        originalAlbum = ""
        originalGenre = ""
        originalYear = ""
        originalTrack = ""
        originalDisc = ""
        originalBpm = ""
        originalIsCompilation = false
        originalArtworkData = nil
    }

    func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil),
                  url.pathExtension.lowercased() == "mp3" else { return }

            DispatchQueue.main.async {
                loadFile(url: url)
            }
        }
        return true
    }

    func loadFile(url: URL) {
        let tagData = TagHelper.readTags(from: url.path)

        if let error = tagData.error {
            alertMessage = "Error reading tags: \(error)"
            showAlert = true
            title = ""
            artist = ""
            album = ""
            genre = ""
            year = ""
            track = ""
            disc = ""
            bpm = ""
            isCompilation = false
            artworkData = nil
            artworkMime = nil
            artworkDeleted = false
        } else {
            title = tagData.title ?? ""
            artist = tagData.artist ?? ""
            album = tagData.album ?? ""
            genre = tagData.genre ?? ""
            year = tagData.year ?? ""
            track = tagData.track ?? ""
            disc = tagData.disc ?? ""
            bpm = tagData.bpm ?? ""
            isCompilation = tagData.compilation ?? false

            // Load artwork
            if let base64Data = tagData.artwork_data,
               let data = Data(base64Encoded: base64Data) {
                artworkData = data
                artworkMime = tagData.artwork_mime
            } else {
                artworkData = nil
                artworkMime = nil
            }
            artworkDeleted = false
        }

        // Store original values for restore
        originalTitle = title
        originalArtist = artist
        originalAlbum = album
        originalGenre = genre
        originalYear = year
        originalTrack = track
        originalDisc = disc
        originalBpm = bpm
        originalIsCompilation = isCompilation
        originalArtworkData = artworkData

        filePath = url.path
        fileName = url.lastPathComponent
    }

    func restoreOriginal() {
        title = originalTitle
        artist = originalArtist
        album = originalAlbum
        genre = originalGenre
        year = originalYear
        track = originalTrack
        disc = originalDisc
        bpm = originalBpm
        isCompilation = originalIsCompilation
        artworkData = originalArtworkData
        artworkMime = originalArtworkData != nil ? artworkMime : nil
        artworkDeleted = false
    }

    func saveFile() {
        guard let sourcePath = filePath else {
            alertMessage = "No file loaded"
            showAlert = true
            return
        }

        var targetPath = sourcePath

        if saveAsCopy {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [UTType.mp3]
            panel.nameFieldStringValue = fileName

            if panel.runModal() == .OK, let url = panel.url {
                do {
                    try FileManager.default.copyItem(atPath: sourcePath, toPath: url.path)
                    targetPath = url.path
                } catch {
                    alertMessage = "Error copying file: \(error.localizedDescription)"
                    showAlert = true
                    return
                }
            } else {
                return
            }
        }

        var artworkBase64: String? = nil
        if let data = artworkData {
            artworkBase64 = data.base64EncodedString()
        }

        let tagData = TagHelper.TagData(
            title: title,
            artist: artist,
            album: album,
            genre: genre,
            year: year,
            track: track,
            disc: disc,
            bpm: bpm,
            compilation: isCompilation,
            artwork_data: artworkBase64,
            artwork_mime: artworkMime,
            artwork_delete: artworkDeleted
        )

        let result = TagHelper.writeTags(to: targetPath, data: tagData)

        if let error = result.error {
            alertMessage = "Error: \(error)"
            showAlert = true
        } else {
            alertMessage = "Saved!"
            showAlert = true

            // Update originals after successful save
            originalTitle = title
            originalArtist = artist
            originalAlbum = album
            originalGenre = genre
            originalYear = year
            originalTrack = track
            originalDisc = disc
            originalBpm = bpm
            originalIsCompilation = isCompilation
            originalArtworkData = artworkData
            artworkDeleted = false
        }
    }
}

struct DropZoneView: View {
    let fileName: String
    @Binding var isDragging: Bool
    let onTap: () -> Void
    let onClear: () -> Void
    let onDrop: ([NSItemProvider]) -> Bool
    @State private var isHovering = false

    private var isHighlighted: Bool {
        isDragging || (isHovering && fileName.isEmpty)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 8) {
                Image(systemName: fileName.isEmpty ? "arrow.down.doc" : "music.note")
                    .font(.system(size: 28, weight: .light))
                    .frame(width: 32, height: 32)
                Text(fileName.isEmpty ? "Drop MP3 here or click to browse" : fileName)
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundColor(isHighlighted ? .accentColor : (fileName.isEmpty ? .secondary : .primary))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 30)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                    .foregroundColor(isHighlighted ? .accentColor : .secondary.opacity(0.5))
            )
            .background(isHighlighted ? Color.accentColor.opacity(0.05) : Color.clear, in: RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .onHover { hovering in
                isHovering = hovering
            }

            if !fileName.isEmpty {
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .padding(8)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDragging, perform: onDrop)
    }
}

struct FieldsCard: View {
    @Binding var title: String
    @Binding var artist: String
    @Binding var album: String
    @Binding var genre: String
    @Binding var year: String
    @Binding var track: String
    @Binding var disc: String
    @Binding var bpm: String
    @Binding var isCompilation: Bool
    @Binding var artworkData: Data?
    @Binding var artworkMime: String?
    @Binding var artworkDeleted: Bool
    var isEnabled: Bool

    private let labelWidth: CGFloat = 55

    var body: some View {
        GlassCard {
            VStack(spacing: 12) {
                ArtworkView(
                    artworkData: $artworkData,
                    artworkMime: $artworkMime,
                    artworkDeleted: $artworkDeleted,
                    isEnabled: isEnabled
                )

                FieldRow(label: "Title", text: $title, placeholder: "Song title", labelWidth: labelWidth, isEnabled: isEnabled)
                FieldRow(label: "Artist", text: $artist, placeholder: "Artist name", labelWidth: labelWidth, isEnabled: isEnabled)
                FieldRow(label: "Album", text: $album, placeholder: "Album name", labelWidth: labelWidth, isEnabled: isEnabled)
                FieldRow(label: "Genre", text: $genre, placeholder: "Genre", labelWidth: labelWidth, isEnabled: isEnabled)

                HStack(spacing: 12) {
                    FieldRow(label: "Year", text: $year, placeholder: "Year", labelWidth: labelWidth, isEnabled: isEnabled, numericOnly: true)
                    FieldRow(label: "Track", text: $track, placeholder: "Track #", labelWidth: labelWidth, isEnabled: isEnabled, numericOnly: true)
                }

                HStack(spacing: 12) {
                    FieldRow(label: "Disc", text: $disc, placeholder: "Disc #", labelWidth: labelWidth, isEnabled: isEnabled, numericOnly: true)
                    FieldRow(label: "BPM", text: $bpm, placeholder: "BPM", labelWidth: labelWidth, isEnabled: isEnabled, numericOnly: true)
                }

                HStack {
                    Toggle("Compilation", isOn: $isCompilation)
                        .disabled(!isEnabled)
                    Spacer()
                }
            }
            .padding(.vertical, 3)
        }
    }
}

struct FieldRow: View {
    let label: String
    @Binding var text: String
    let placeholder: String
    var labelWidth: CGFloat = 55
    var isEnabled: Bool = true
    var numericOnly: Bool = false

    var body: some View {
        HStack {
            Text(label)
                .frame(width: labelWidth, alignment: .leading)

            TextField(placeholder, text: $text)
                .disabled(!isEnabled)
                .onChange(of: text) { newValue in
                    if numericOnly {
                        let filtered = newValue.filter { $0.isNumber }
                        if filtered != newValue {
                            text = filtered
                        }
                    }
                }
        }
    }
}

struct GlassCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(22)
            .frame(maxWidth: .infinity)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
            .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
    }
}

struct ArtworkView: View {
    @Binding var artworkData: Data?
    @Binding var artworkMime: String?
    @Binding var artworkDeleted: Bool
    var isEnabled: Bool
    @State private var isDragging = false
    @State private var isHovering = false

    private let size: CGFloat = 120

    private var isHighlighted: Bool {
        isEnabled && (isDragging || (isHovering && artworkData == nil))
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                if let data = artworkData, let nsImage = NSImage(data: data) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size, height: size)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(isDragging ? Color.accentColor : Color.clear, lineWidth: 2)
                        )
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "photo")
                            .font(.system(size: 28, weight: .light))
                        if isEnabled {
                            Text("Drop album art here or click to browse")
                                .font(.system(size: 11))
                                .multilineTextAlignment(.center)
                        } else {
                            Text("Album art")
                                .font(.system(size: 12))
                        }
                    }
                    .padding(.horizontal, 8)
                    .foregroundColor(isHighlighted ? .accentColor : .secondary)
                    .frame(width: size, height: size)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                            .foregroundColor(isHighlighted ? .accentColor : .secondary.opacity(0.5))
                    )
                    .background(isHighlighted ? Color.accentColor.opacity(0.05) : Color.clear, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard isEnabled && artworkData == nil else { return }
                selectImage()
            }
            .onHover { hovering in
                isHovering = hovering
            }
            .onDrop(of: [.image, .fileURL], isTargeted: $isDragging) { providers in
                guard isEnabled else { return false }
                return handleImageDrop(providers: providers)
            }

            if artworkData != nil && isEnabled {
                Button(action: {
                    artworkData = nil
                    artworkMime = nil
                    artworkDeleted = true
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white)
                        .background(Circle().fill(Color.black.opacity(0.5)))
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: -4)
            }
        }
    }

    private func selectImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.image]
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            if let imageData = try? Data(contentsOf: url) {
                let ext = url.pathExtension.lowercased()
                let mime = ext == "png" ? "image/png" : (ext == "gif" ? "image/gif" : "image/jpeg")
                artworkData = imageData
                artworkMime = mime
                artworkDeleted = false
            }
        }
    }

    private func handleImageDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        // Try loading as image data first
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, error in
                if let data = data {
                    DispatchQueue.main.async {
                        self.artworkData = data
                        self.artworkMime = "image/png"
                        self.artworkDeleted = false
                    }
                }
            }
            return true
        }

        // Try loading as file URL
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }

                let ext = url.pathExtension.lowercased()
                guard ["jpg", "jpeg", "png", "gif", "webp"].contains(ext) else { return }

                if let imageData = try? Data(contentsOf: url) {
                    DispatchQueue.main.async {
                        let mime = ext == "png" ? "image/png" : (ext == "gif" ? "image/gif" : "image/jpeg")
                        self.artworkData = imageData
                        self.artworkMime = mime
                        self.artworkDeleted = false
                    }
                }
            }
            return true
        }

        return false
    }
}
