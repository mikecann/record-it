import Foundation

struct ProjectDestination: Identifiable, Hashable {
    let id: String
    let displayName: String
    let outputDirectory: URL
    let projectDate: Date?

    static func project(directory: URL, date: Date?) -> ProjectDestination {
        ProjectDestination(
            id: directory.path,
            displayName: directory.lastPathComponent,
            outputDirectory: directory.appendingPathComponent("source", isDirectory: true),
            projectDate: date
        )
    }

    static func noProject(outputDirectory: URL) -> ProjectDestination {
        ProjectDestination(
            id: "no-project",
            displayName: "No Project",
            outputDirectory: outputDirectory,
            projectDate: nil
        )
    }
}

struct ProjectCatalog {
    let projectsRoot: URL
    let fallbackOutputRoot: URL

    func createProject(named requestedName: String) throws -> ProjectDestination {
        let name = requestedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.hasPrefix("."),
              !name.contains("/"), !name.contains(":"),
              name.rangeOfCharacter(from: .controlCharacters) == nil else {
            throw ProjectCreationError.invalidName
        }

        let directory = projectsRoot.appendingPathComponent(name, isDirectory: true)
        // Creating a project must never reuse or modify an existing folder.
        guard !FileManager.default.fileExists(atPath: directory.path) else {
            throw ProjectCreationError.alreadyExists(name)
        }
        try FileManager.default.createDirectory(at: projectsRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let destination = ProjectDestination.project(directory: directory, date: Date())
        try prepareOutputDirectory(for: destination)
        return destination
    }

    func destinations() throws -> [ProjectDestination] {
        guard FileManager.default.fileExists(atPath: projectsRoot.path) else {
            return [.noProject(outputDirectory: fallbackOutputRoot)]
        }
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .creationDateKey]
        let directories = try FileManager.default.contentsOfDirectory(
            at: projectsRoot,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )

        let projects = try directories.compactMap { directory -> ProjectDestination? in
            let values = try directory.resourceValues(forKeys: keys)
            guard values.isDirectory == true else { return nil }
            // Keep IDs rooted in the same path used when creating projects.
            // Directory enumeration can expand aliases such as /var to /private/var.
            let projectDirectory = projectsRoot.appendingPathComponent(directory.lastPathComponent, isDirectory: true)
            return .project(directory: projectDirectory, date: values.creationDate)
        }

        return projects.sorted {
            ($0.projectDate ?? .distantPast) > ($1.projectDate ?? .distantPast)
        } + [.noProject(outputDirectory: fallbackOutputRoot)]
    }

    func initialDestination() throws -> ProjectDestination {
        try destinations().first ?? .noProject(outputDirectory: fallbackOutputRoot)
    }
}

enum ProjectCreationError: LocalizedError {
    case invalidName
    case alreadyExists(String)
    case recordingUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidName:
            "Enter a folder name without /, :, or control characters. It cannot start with a dot."
        case .alreadyExists(let name):
            "A file or folder named \"\(name)\" already exists. Choose another name."
        case .recordingUnavailable:
            "Wait until Record It has finished recording or loading before creating a project."
        }
    }
}

@discardableResult
func prepareOutputDirectory(
    for destination: ProjectDestination,
    fileManager: FileManager = .default
) throws -> URL {
    try fileManager.createDirectory(
        at: destination.outputDirectory,
        withIntermediateDirectories: true
    )
    return destination.outputDirectory
}
