import Foundation

struct SandevistanConfig: Codable, Sendable {
    var ghostCount: Int
    var lifespanMs: Int
    var colors: [String]
    var samplingIntervalMs: Int
    var hotkey: String

    static let `default` = SandevistanConfig(
        ghostCount: 6,
        lifespanMs: 500,
        colors: ["#4bff21", "#00f0ff", "#772289", "#ff3333", "#f8e602"],
        samplingIntervalMs: 30,
        hotkey: "ctrl+shift+s"
    )

    func validated() -> SandevistanConfig {
        var c = self
        c.ghostCount = max(1, min(30, c.ghostCount))
        c.lifespanMs = max(100, min(3000, c.lifespanMs))
        c.samplingIntervalMs = max(10, min(200, c.samplingIntervalMs))
        if c.colors.isEmpty { c.colors = SandevistanConfig.default.colors }
        if c.hotkey.isEmpty { c.hotkey = SandevistanConfig.default.hotkey }
        return c
    }
}

final class ConfigLoader: @unchecked Sendable {
    private let configDir: String
    private let configPath: String
    private var fileDescriptor: Int32 = -1
    private var dispatchSource: DispatchSourceFileSystemObject?
    private(set) var config: SandevistanConfig
    var onChange: ((SandevistanConfig) -> Void)?

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.configDir = "\(home)/.config/sandevistan"
        self.configPath = "\(configDir)/config.json"
        self.config = SandevistanConfig.default
        self.config = loadOrCreate()
        startWatching()
    }

    private func loadOrCreate() -> SandevistanConfig {
        let fm = FileManager.default
        if !fm.fileExists(atPath: configPath) {
            try? fm.createDirectory(atPath: configDir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(SandevistanConfig.default) {
                fm.createFile(atPath: configPath, contents: data)
                print("Sandevistan: created default config at \(configPath)")
            }
            return SandevistanConfig.default
        }
        guard let data = fm.contents(atPath: configPath),
              let parsed = try? JSONDecoder().decode(SandevistanConfig.self, from: data) else {
            print("Sandevistan: invalid config, using defaults")
            return SandevistanConfig.default
        }
        return parsed.validated()
    }

    private func startWatching() {
        fileDescriptor = open(configPath, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let newConfig = self.loadOrCreate()
            if newConfig.ghostCount != self.config.ghostCount ||
               newConfig.lifespanMs != self.config.lifespanMs ||
               newConfig.colors != self.config.colors ||
               newConfig.samplingIntervalMs != self.config.samplingIntervalMs ||
               newConfig.hotkey != self.config.hotkey {
                self.config = newConfig
                print("Sandevistan: config reloaded")
                self.onChange?(newConfig)
            }
        }
        source.setCancelHandler { [fd = fileDescriptor] in close(fd) }
        source.resume()
        dispatchSource = source
    }

    deinit {
        dispatchSource?.cancel()
    }
}
