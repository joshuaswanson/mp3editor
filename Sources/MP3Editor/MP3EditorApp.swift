import SwiftUI
import UniformTypeIdentifiers
import AppKit

extension View {
    @ViewBuilder func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

enum EditTab: String, CaseIterable {
    case metadata = "Metadata"
    case audio = "Audio"
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
        resourcesDir.appendingPathComponent("mp3processor.py").path
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
        var where_from: String?
        var error: String?
        var success: Bool?
    }

    struct WaveformData: Codable {
        var waveform: [Float]?
        var duration: Double?
        var error: String?
    }

    struct ProcessData: Codable {
        var trim_start: Double?
        var trim_end: Double?
        var pitch_shift: Int?
        var speed: Double?
    }

    struct ProcessResult: Codable {
        var success: Bool?
        var error: String?
    }

    static func readTags(from path: String) -> TagData {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = [scriptPath, "read", path]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        var data = Data()
        do {
            try process.run()

            // Read data BEFORE waitUntilExit to avoid pipe buffer deadlock
            data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            return try JSONDecoder().decode(TagData.self, from: data)
        } catch {
            let rawOutput = String(data: data, encoding: .utf8) ?? "(no output)"
            let preview = String(rawOutput.prefix(500))
            return TagData(error: "\(error.localizedDescription)\n\nFirst 500 chars: \(preview)")
        }
    }

    static func writeTags(to path: String, data: TagData) -> TagData {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = [scriptPath, "write", path]

        let inputPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()

            let jsonData = try JSONEncoder().encode(data)
            inputPipe.fileHandleForWriting.write(jsonData)
            inputPipe.fileHandleForWriting.closeFile()

            // Read data BEFORE waitUntilExit to avoid pipe buffer deadlock
            let resultData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            return try JSONDecoder().decode(TagData.self, from: resultData)
        } catch {
            return TagData(error: error.localizedDescription)
        }
    }

    static func getWaveform(from path: String) -> WaveformData {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = [scriptPath, "waveform", path, "200"]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        var data = Data()
        do {
            try process.run()
            data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return try JSONDecoder().decode(WaveformData.self, from: data)
        } catch {
            let rawOutput = String(data: data, encoding: .utf8) ?? "(no output)"
            let preview = String(rawOutput.prefix(500))
            return WaveformData(error: "\(error.localizedDescription)\n\nFirst 500 chars: \(preview)")
        }
    }

    static func processAudio(source: String, dest: String, data: ProcessData) -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = [scriptPath, "process", source, dest]

        let inputPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()

            let jsonData = try JSONEncoder().encode(data)
            inputPipe.fileHandleForWriting.write(jsonData)
            inputPipe.fileHandleForWriting.closeFile()

            let resultData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            return try JSONDecoder().decode(ProcessResult.self, from: resultData)
        } catch {
            return ProcessResult(error: error.localizedDescription)
        }
    }
}

struct ContentView: View {
    @State private var filePath: String? = nil
    @State private var fileName: String = ""
    @State private var selectedTab: EditTab = .metadata

    // Metadata fields
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
    @State private var whereFrom: String? = nil

    // Audio editing state
    @State private var waveformSamples: [Float] = []
    @State private var audioDuration: Double = 0
    @State private var trimStart: Double = 0.0
    @State private var trimEnd: Double = 1.0
    @State private var pitchShift: Int = 0
    @State private var speedMultiplier: Double = 1.0
    @State private var isLoadingWaveform: Bool = false

    // UI state
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
    @State private var originalWhereFrom: String? = nil

    var hasFile: Bool {
        filePath != nil
    }

    var hasMetadataChanges: Bool {
        title != originalTitle || artist != originalArtist || album != originalAlbum ||
        genre != originalGenre || year != originalYear || track != originalTrack ||
        disc != originalDisc || bpm != originalBpm || isCompilation != originalIsCompilation ||
        artworkData != originalArtworkData || artworkDeleted || whereFrom != originalWhereFrom
    }

    var hasAudioChanges: Bool {
        trimStart != 0.0 || trimEnd != 1.0 || pitchShift != 0 || speedMultiplier != 1.0
    }

    var hasChanges: Bool {
        if selectedTab == .metadata {
            return hasMetadataChanges
        } else {
            return hasAudioChanges
        }
    }

    var body: some View {
        VStack(spacing: 18) {
            // Drop zone
            DropZoneView(
                fileName: fileName,
                isDragging: $isDragging,
                onTap: selectFile,
                onClear: clearFile
            )

            // Tab picker
            Picker("", selection: $selectedTab) {
                ForEach(EditTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            // Content based on selected tab
            if selectedTab == .metadata {
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
                    whereFrom: $whereFrom,
                    isEnabled: hasFile
                )
            } else {
                AudioEditCard(
                    waveformSamples: waveformSamples,
                    duration: audioDuration,
                    trimStart: $trimStart,
                    trimEnd: $trimEnd,
                    pitchShift: $pitchShift,
                    speedMultiplier: $speedMultiplier,
                    isLoading: isLoadingWaveform,
                    isEnabled: hasFile
                )
            }

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
                .disabled(!hasChanges)
            }
        }
        .padding(25)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .contentShape(Rectangle())
        .onTapGesture {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
        .if(!hasFile) { view in
            view.onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
                handleDrop(providers: providers)
            }
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
        .alert("Allow overwriting original files?", isPresented: $showUncheckedWarning) {
            Button("Cancel", role: .cancel) { }
            Button("Allow", role: .destructive) {
                saveAsCopy = false
            }
        } message: {
            Text("Unchecking this means Save will modify your original file instead of creating a copy.")
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
        whereFrom = nil
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
        originalWhereFrom = nil
        // Reset audio state
        waveformSamples = []
        audioDuration = 0
        trimStart = 0.0
        trimEnd = 1.0
        pitchShift = 0
        speedMultiplier = 1.0
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
        // Set file info immediately so UI updates
        filePath = url.path
        fileName = url.lastPathComponent

        // Reset audio editing state
        trimStart = 0.0
        trimEnd = 1.0
        pitchShift = 0
        speedMultiplier = 1.0

        // Load tags in background to avoid blocking UI
        DispatchQueue.global(qos: .userInitiated).async {
            let tagData = TagHelper.readTags(from: url.path)

            DispatchQueue.main.async {
                if let error = tagData.error {
                    self.alertMessage = "Error reading tags: \(error)"
                    self.showAlert = true
                    self.title = ""
                    self.artist = ""
                    self.album = ""
                    self.genre = ""
                    self.year = ""
                    self.track = ""
                    self.disc = ""
                    self.bpm = ""
                    self.isCompilation = false
                    self.artworkData = nil
                    self.artworkMime = nil
                    self.artworkDeleted = false
                } else {
                    self.title = tagData.title ?? ""
                    self.artist = tagData.artist ?? ""
                    self.album = tagData.album ?? ""
                    self.genre = tagData.genre ?? ""
                    self.year = tagData.year ?? ""
                    self.track = tagData.track ?? ""
                    self.disc = tagData.disc ?? ""
                    self.bpm = tagData.bpm ?? ""
                    self.isCompilation = tagData.compilation ?? false

                    // Load artwork
                    if let base64Data = tagData.artwork_data,
                       let data = Data(base64Encoded: base64Data) {
                        self.artworkData = data
                        self.artworkMime = tagData.artwork_mime
                    } else {
                        self.artworkData = nil
                        self.artworkMime = nil
                    }
                    self.artworkDeleted = false
                    self.whereFrom = tagData.where_from
                }

                // Store original values for restore
                self.originalTitle = self.title
                self.originalArtist = self.artist
                self.originalAlbum = self.album
                self.originalGenre = self.genre
                self.originalYear = self.year
                self.originalTrack = self.track
                self.originalDisc = self.disc
                self.originalBpm = self.bpm
                self.originalIsCompilation = self.isCompilation
                self.originalArtworkData = self.artworkData
                self.originalWhereFrom = self.whereFrom
            }
        }

        // Load waveform in background
        loadWaveform(from: url.path)
    }

    func loadWaveform(from path: String) {
        isLoadingWaveform = true
        DispatchQueue.global(qos: .userInitiated).async {
            let waveformData = TagHelper.getWaveform(from: path)
            DispatchQueue.main.async {
                self.isLoadingWaveform = false
                if let samples = waveformData.waveform {
                    self.waveformSamples = samples
                    self.audioDuration = waveformData.duration ?? 0
                } else {
                    self.waveformSamples = []
                    self.audioDuration = 0
                }
            }
        }
    }

    func restoreOriginal() {
        if selectedTab == .metadata {
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
            whereFrom = originalWhereFrom
        } else {
            // Reset audio editing values
            trimStart = 0.0
            trimEnd = 1.0
            pitchShift = 0
            speedMultiplier = 1.0
        }
    }

    func saveFile() {
        guard let sourcePath = filePath else {
            alertMessage = "No file loaded"
            showAlert = true
            return
        }

        if selectedTab == .metadata {
            saveMetadata(sourcePath: sourcePath)
        } else {
            saveAudioEdits(sourcePath: sourcePath)
        }
    }

    func saveMetadata(sourcePath: String) {
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
            artwork_delete: artworkDeleted,
            where_from: whereFrom ?? ""
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
            originalWhereFrom = whereFrom
            artworkDeleted = false
        }
    }

    func saveAudioEdits(sourcePath: String) {
        var targetPath = sourcePath

        if saveAsCopy {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [UTType.mp3]
            panel.nameFieldStringValue = fileName

            if panel.runModal() == .OK, let url = panel.url {
                targetPath = url.path
            } else {
                return
            }
        }

        let processData = TagHelper.ProcessData(
            trim_start: trimStart,
            trim_end: trimEnd,
            pitch_shift: pitchShift,
            speed: speedMultiplier
        )

        let result = TagHelper.processAudio(source: sourcePath, dest: targetPath, data: processData)

        if let error = result.error {
            alertMessage = "Error: \(error)"
            showAlert = true
        } else {
            alertMessage = "Saved!"
            showAlert = true

            // Reset audio editing state after successful save
            trimStart = 0.0
            trimEnd = 1.0
            pitchShift = 0
            speedMultiplier = 1.0
        }
    }
}

struct DropZoneView: View {
    let fileName: String
    @Binding var isDragging: Bool
    let onTap: () -> Void
    let onClear: () -> Void
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
                Group {
                    if fileName.isEmpty {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                            .foregroundColor(isHighlighted ? .accentColor : .secondary.opacity(0.5))
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 2)
                    }
                }
            )
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(fileName.isEmpty ? (isHighlighted ? Color.accentColor.opacity(0.05) : Color.clear) : Color.accentColor.opacity(0.08))
            )
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
    @Binding var whereFrom: String?
    var isEnabled: Bool

    private let labelWidth: CGFloat = 55

    private var artworkDimensions: String? {
        guard let data = artworkData, let nsImage = NSImage(data: data) else { return nil }
        let width = Int(nsImage.size.width)
        let height = Int(nsImage.size.height)
        return "\(width) x \(height)"
    }

    var body: some View {
        GlassCard {
            VStack(spacing: 12) {
                HStack(alignment: .center) {
                    Text("Album art")
                        .frame(width: labelWidth, alignment: .leading)

                    VStack {
                        ArtworkView(
                            artworkData: $artworkData,
                            artworkMime: $artworkMime,
                            artworkDeleted: $artworkDeleted,
                            isEnabled: isEnabled
                        )
                    }

                    VStack {
                        Spacer()
                        if let dimensions = artworkDimensions {
                            Text(dimensions)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(height: 120)

                    Spacer()
                }

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

                Divider()
                    .padding(.top, 4)

                HStack {
                    Text("Source")
                        .frame(width: labelWidth, alignment: .leading)
                    TextField("Download URL", text: Binding(
                        get: { whereFrom ?? "" },
                        set: { whereFrom = $0.isEmpty ? nil : $0 }
                    ))
                    .disabled(!isEnabled)
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
                .onChange(of: text) { oldValue, newValue in
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
    @State private var isHovering = false
    @State private var isDragging = false

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
            .if(isEnabled) { view in
                view.onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
                    handleImageDrop(providers: providers)
                }
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

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
            var url: URL?

            if let directURL = item as? URL {
                url = directURL
            } else if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            }

            guard let fileURL = url else { return }

            let ext = fileURL.pathExtension.lowercased()
            guard ["jpg", "jpeg", "png", "gif", "webp", "tiff", "bmp"].contains(ext) else { return }

            if let imageData = try? Data(contentsOf: fileURL) {
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
}

struct AudioEditCard: View {
    let waveformSamples: [Float]
    let duration: Double
    @Binding var trimStart: Double
    @Binding var trimEnd: Double
    @Binding var pitchShift: Int
    @Binding var speedMultiplier: Double
    var isLoading: Bool
    var isEnabled: Bool

    var body: some View {
        GlassCard {
            VStack(spacing: 16) {
                // Waveform with trim handles
                WaveformView(
                    samples: waveformSamples,
                    duration: duration,
                    trimStart: $trimStart,
                    trimEnd: $trimEnd,
                    isLoading: isLoading,
                    isEnabled: isEnabled
                )

                Divider()

                // Pitch control
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Pitch")
                            .frame(width: 50, alignment: .leading)
                        Text(pitchShift == 0 ? "0" : (pitchShift > 0 ? "+\(pitchShift)" : "\(pitchShift)"))
                            .frame(width: 35)
                            .foregroundColor(.secondary)
                        Text("semitones")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    Slider(value: Binding(
                        get: { Double(pitchShift) },
                        set: { pitchShift = Int($0.rounded()) }
                    ), in: -12...12, step: 1)
                    .disabled(!isEnabled)
                }

                // Speed control
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Speed")
                            .frame(width: 50, alignment: .leading)
                        Text(String(format: "%.2fx", speedMultiplier))
                            .frame(width: 50)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    Slider(value: $speedMultiplier, in: 0.5...2.0, step: 0.05)
                        .disabled(!isEnabled)
                }
            }
            .padding(.vertical, 3)
        }
    }
}

struct WaveformView: View {
    let samples: [Float]
    let duration: Double
    @Binding var trimStart: Double
    @Binding var trimEnd: Double
    var isLoading: Bool
    var isEnabled: Bool

    @State private var activeHandle: DragHandle? = nil

    enum DragHandle {
        case start, end
    }

    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private let waveformCornerRadius: CGFloat = 14  // Must match handleWidth for corners to align

    private let waveformAreaHeight: CGFloat = 46
    private let handleWidth: CGFloat = 14

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Trim")
                .padding(.bottom, 6)

            // Waveform area with GeometryReader (needs width for positioning)
            GeometryReader { geometry in
                let width = geometry.size.width
                let height = geometry.size.height

                ZStack(alignment: .leading) {
                    // Background - only spans content area between handles
                    let contentWidth = width - handleWidth * 2
                    RoundedRectangle(cornerRadius: waveformCornerRadius)
                        .fill(Color.secondary.opacity(0.15))
                        .frame(width: contentWidth, height: height)
                        .position(x: handleWidth + contentWidth / 2, y: height / 2)

                    if isLoading {
                        // Loading indicator
                        HStack {
                            Spacer()
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Loading waveform...")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                    } else if samples.isEmpty {
                        // No waveform
                        HStack {
                            Spacer()
                            Text("No audio data")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                    } else {
                        // Waveform bars using Canvas with horizontal padding for handles
                        Canvas { context, size in
                            let horizontalPadding = handleWidth
                            let contentWidth = size.width - (horizontalPadding * 2)
                            let barCount = CGFloat(samples.count)
                            let barSpacing: CGFloat = 1
                            let totalSpacing = barSpacing * (barCount - 1)
                            let barWidth = (contentWidth - totalSpacing) / barCount
                            let verticalPadding: CGFloat = 6
                            let maxBarHeight = size.height - (verticalPadding * 2)

                            for (index, sample) in samples.enumerated() {
                                // Apply x^12 for visual variance
                                let scaledSample = pow(CGFloat(sample), 12)
                                let minHeight: CGFloat = 4
                                let barHeight = minHeight + scaledSample * (maxBarHeight - minHeight)

                                let x = horizontalPadding + CGFloat(index) * (barWidth + barSpacing)
                                let y = (size.height - barHeight) / 2

                                let position = Double(index) / Double(samples.count)
                                let isInTrimRange = position >= trimStart && position <= trimEnd

                                let rect = CGRect(x: x, y: y, width: barWidth, height: barHeight)
                                let path = RoundedRectangle(cornerRadius: 1).path(in: rect)
                                context.fill(path, with: .color(isInTrimRange ? .accentColor : .secondary.opacity(0.3)))
                            }
                        }

                        // Trim overlay - left (before start) - sits inside the handle area
                        let leftOverlayWidth = (width - handleWidth * 2) * CGFloat(trimStart)
                        if leftOverlayWidth > 0 {
                            UnevenRoundedRectangle(topLeadingRadius: waveformCornerRadius, bottomLeadingRadius: waveformCornerRadius, bottomTrailingRadius: 0, topTrailingRadius: 0)
                                .fill(Color.black.opacity(0.35))
                                .frame(width: leftOverlayWidth, height: height)
                                .position(x: handleWidth + leftOverlayWidth / 2, y: height / 2)
                        }

                        // Trim overlay - right (after end) - sits inside the handle area
                        let rightOverlayWidth = (width - handleWidth * 2) * CGFloat(1.0 - trimEnd)
                        if rightOverlayWidth > 0 {
                            UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0, bottomTrailingRadius: waveformCornerRadius, topTrailingRadius: waveformCornerRadius)
                                .fill(Color.black.opacity(0.35))
                                .frame(width: rightOverlayWidth, height: height)
                                .position(x: width - handleWidth - rightOverlayWidth / 2, y: height / 2)
                        }

                        // Selection frame
                        TrimSelectionFrame(
                            trimStart: trimStart,
                            trimEnd: trimEnd,
                            width: width,
                            waveformHeight: height,
                            handleWidth: handleWidth
                        )
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard isEnabled && !samples.isEmpty else { return }
                            // Account for horizontal padding when calculating position
                            let contentWidth = width - (handleWidth * 2)
                            let adjustedX = value.location.x - handleWidth
                            let position = max(0, min(1.0, adjustedX / contentWidth))

                            // On first touch, determine which handle to move based on proximity
                            if activeHandle == nil {
                                let distToStart = abs(position - trimStart)
                                let distToEnd = abs(position - trimEnd)
                                activeHandle = distToStart <= distToEnd ? .start : .end
                            }

                            // Move the active handle with animation
                            withAnimation(.interactiveSpring(response: 0.15, dampingFraction: 0.8)) {
                                if activeHandle == .start {
                                    trimStart = max(0, min(trimEnd - 0.02, position))
                                } else {
                                    trimEnd = max(trimStart + 0.02, min(1.0, position))
                                }
                            }
                        }
                        .onEnded { _ in
                            activeHandle = nil
                        }
                )
            }
            .frame(height: waveformAreaHeight)

            // Time labels outside the waveform box (self-sizing)
            if !samples.isEmpty {
                HStack {
                    Text(formatTime(duration * trimStart))
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(formatTime(duration * trimEnd))
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 4)
            }
        }
    }
}

// Custom shape for handle with convex outside corners and concave inside corners
struct HandleShape: Shape {
    let isLeft: Bool
    let outerRadius: CGFloat
    let innerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let ir = min(innerRadius, w, h / 2) // Clamp inner radius
        let or_ = min(outerRadius, w, h / 2) // Clamp outer radius

        if isLeft {
            // Left handle: convex on left (outside), concave on right (inside)
            path.move(to: CGPoint(x: w, y: 0))
            // Top-right concave: curves inward into the handle
            path.addArc(center: CGPoint(x: w + ir, y: ir),
                       radius: ir,
                       startAngle: .degrees(270),
                       endAngle: .degrees(180),
                       clockwise: true)
            // Line down right side
            path.addLine(to: CGPoint(x: w, y: h - ir))
            // Bottom-right concave: curves inward into the handle
            path.addArc(center: CGPoint(x: w + ir, y: h - ir),
                       radius: ir,
                       startAngle: .degrees(180),
                       endAngle: .degrees(90),
                       clockwise: true)
            // Line to bottom-left
            path.addLine(to: CGPoint(x: or_, y: h))
            // Bottom-left convex: normal outward curve
            path.addArc(center: CGPoint(x: or_, y: h - or_),
                       radius: or_,
                       startAngle: .degrees(90),
                       endAngle: .degrees(180),
                       clockwise: false)
            // Line up left side
            path.addLine(to: CGPoint(x: 0, y: or_))
            // Top-left convex: normal outward curve
            path.addArc(center: CGPoint(x: or_, y: or_),
                       radius: or_,
                       startAngle: .degrees(180),
                       endAngle: .degrees(270),
                       clockwise: false)
            path.closeSubpath()
        } else {
            // Right handle: concave on left (inside), convex on right (outside)
            path.move(to: CGPoint(x: 0, y: 0))
            // Line to top-right
            path.addLine(to: CGPoint(x: w - or_, y: 0))
            // Top-right convex: normal outward curve
            path.addArc(center: CGPoint(x: w - or_, y: or_),
                       radius: or_,
                       startAngle: .degrees(270),
                       endAngle: .degrees(0),
                       clockwise: false)
            // Line down right side
            path.addLine(to: CGPoint(x: w, y: h - or_))
            // Bottom-right convex: normal outward curve
            path.addArc(center: CGPoint(x: w - or_, y: h - or_),
                       radius: or_,
                       startAngle: .degrees(0),
                       endAngle: .degrees(90),
                       clockwise: false)
            // Line to bottom-left
            path.addLine(to: CGPoint(x: 0, y: h))
            // Bottom-left concave: curves inward into the handle
            path.addArc(center: CGPoint(x: -ir, y: h - ir),
                       radius: ir,
                       startAngle: .degrees(90),
                       endAngle: .degrees(0),
                       clockwise: true)
            // Line up left side
            path.addLine(to: CGPoint(x: 0, y: ir))
            // Top-left concave: curves inward into the handle
            path.addArc(center: CGPoint(x: -ir, y: ir),
                       radius: ir,
                       startAngle: .degrees(0),
                       endAngle: .degrees(270),
                       clockwise: true)
            path.closeSubpath()
        }

        return path
    }
}

struct TrimSelectionFrame: View {
    let trimStart: Double
    let trimEnd: Double
    let width: CGFloat
    let waveformHeight: CGFloat
    let handleWidth: CGFloat

    private let edgeHeight: CGFloat = 3
    private let cornerRadius: CGFloat = 14  // Must match handleWidth for corners to align
    private let handleColor = Color.yellow

    var body: some View {
        // Content area is between the handle padding on each side
        let contentWidth = width - (handleWidth * 2)
        let startX = handleWidth + contentWidth * CGFloat(trimStart)
        let endX = handleWidth + contentWidth * CGFloat(trimEnd)
        let frameWidth = endX - startX + handleWidth * 2

        ZStack(alignment: .topLeading) {
            // Main rounded rectangle frame
            // Use cornerRadius + edgeHeight/2 so the inner edge of the stroke
            // (which is centered on the path) aligns with the waveform background
            RoundedRectangle(cornerRadius: cornerRadius + edgeHeight / 2)
                .stroke(handleColor, lineWidth: edgeHeight)
                .frame(width: max(frameWidth, handleWidth * 2), height: waveformHeight)
                .position(x: startX - handleWidth + frameWidth / 2, y: waveformHeight / 2)

            // Left handle - convex outside, concave inside
            HandleShape(isLeft: true, outerRadius: cornerRadius, innerRadius: cornerRadius)
                .fill(handleColor)
                .frame(width: handleWidth, height: waveformHeight)
                .position(x: startX - handleWidth / 2, y: waveformHeight / 2)

            // Left handle grip lines
            HStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 0.5)
                    .fill(Color.black.opacity(0.3))
                    .frame(width: 1.5, height: 16)
                RoundedRectangle(cornerRadius: 0.5)
                    .fill(Color.black.opacity(0.3))
                    .frame(width: 1.5, height: 16)
            }
            .position(x: startX - handleWidth / 2, y: waveformHeight / 2)

            // Right handle - concave inside, convex outside
            HandleShape(isLeft: false, outerRadius: cornerRadius, innerRadius: cornerRadius)
                .fill(handleColor)
                .frame(width: handleWidth, height: waveformHeight)
                .position(x: endX + handleWidth / 2, y: waveformHeight / 2)

            // Right handle grip lines
            HStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 0.5)
                    .fill(Color.black.opacity(0.3))
                    .frame(width: 1.5, height: 16)
                RoundedRectangle(cornerRadius: 0.5)
                    .fill(Color.black.opacity(0.3))
                    .frame(width: 1.5, height: 16)
            }
            .position(x: endX + handleWidth / 2, y: waveformHeight / 2)
        }
    }
}
