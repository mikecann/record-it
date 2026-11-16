import AppKit

/// Telemprompit (mikerosoft-tools/telemprompit) is the teleprompter Mike reads
/// from on the Elgato Prompter while recording. Record It only launches it; the
/// two apps don't share any state.
let teleprompterBundleIdentifier = "com.mikerosoft.telemprompit"

/// Finds Telemprompit by bundle identifier first, then at the path its
/// build-app.sh stages it to, in case Launch Services hasn't registered it yet.
func teleprompterAppURL(
    urlForBundleIdentifier: (String) -> URL?,
    fileExists: (String) -> Bool,
    homeDirectory: URL
) -> URL? {
    if let url = urlForBundleIdentifier(teleprompterBundleIdentifier) {
        return url
    }
    let staged = homeDirectory
        .appendingPathComponent("Applications", isDirectory: true)
        .appendingPathComponent("Telemprompit.app", isDirectory: true)
    return fileExists(staged.path) ? staged : nil
}

@MainActor
final class TeleprompterLauncher: ObservableObject {
    /// True from the click until macOS has launched or activated the app, so
    /// the button can show a spinner and can't be pressed twice.
    @Published private(set) var isOpening = false

    /// Opens Telemprompit, or brings it forward if it's already running.
    /// Returns a message to show when it can't be opened.
    func open() async -> String? {
        guard !isOpening else { return nil }
        isOpening = true
        defer { isOpening = false }

        guard let url = teleprompterAppURL(
            urlForBundleIdentifier: { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) },
            fileExists: { FileManager.default.fileExists(atPath: $0) },
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser
        ) else {
            return "Telemprompit isn't installed. Run setup_mac.sh in mikerosoft-tools/telemprompit to stage it in ~/Applications."
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        do {
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            return nil
        } catch {
            return "Telemprompit could not be opened: \(error.localizedDescription)"
        }
    }
}
