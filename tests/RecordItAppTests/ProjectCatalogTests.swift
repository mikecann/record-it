import Foundation
import XCTest
@testable import RecordItApp

final class ProjectCatalogTests: XCTestCase {
    func testCreatingProjectMakesTheNamedFolderAndSourceUnderTheProjectsRoot() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let catalog = ProjectCatalog(
            projectsRoot: root.appendingPathComponent("projects"),
            fallbackOutputRoot: root.appendingPathComponent("fallback")
        )

        let destination = try catalog.createProject(named: "  My new video  \n")

        XCTAssertEqual(destination.displayName, "My new video")
        let project = catalog.projectsRoot.appendingPathComponent("My new video", isDirectory: true)
        XCTAssertEqual(destination.id, project.path)
        XCTAssertEqual(destination.outputDirectory, project.appendingPathComponent("source", isDirectory: true))
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.outputDirectory.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
        let destinations = try catalog.destinations()
        XCTAssertTrue(destinations.contains { $0.id == destination.id }, "Created: \(destination.id), listed: \(destinations.map(\.id))")
    }

    func testCreatingProjectRejectsInvalidOrHiddenFolderNamesWithoutCreatingAnything() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let catalog = ProjectCatalog(projectsRoot: root, fallbackOutputRoot: root.appendingPathComponent("fallback"))

        for name in ["", " \n ", ".", "..", ".hidden", "../escape", "nested/project", "a:b", "a\u{0}b", "line\nbreak"] {
            XCTAssertThrowsError(try catalog.createProject(named: name), name)
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    func testCreatingProjectRejectsExistingFoldersAndFilesWithoutChangingThem() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("existing"), withIntermediateDirectories: true)
        let file = root.appendingPathComponent("notes.txt")
        try Data("keep me".utf8).write(to: file)
        let catalog = ProjectCatalog(projectsRoot: root, fallbackOutputRoot: root.appendingPathComponent("fallback"))

        XCTAssertThrowsError(try catalog.createProject(named: "existing"))
        XCTAssertThrowsError(try catalog.createProject(named: "notes.txt"))

        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("existing/source").path))
        XCTAssertEqual(try String(contentsOf: file), "keep me")
    }

    func testInitialDestinationIsTheNewestProject() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let older = root.appendingPathComponent("older-project", isDirectory: true)
        let newer = root.appendingPathComponent("newer-project", isDirectory: true)
        try FileManager.default.createDirectory(at: older, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: newer, withIntermediateDirectories: true)
        try FileManager.default.setAttributes(
            [.creationDate: Date(timeIntervalSince1970: 1_000)],
            ofItemAtPath: older.path
        )
        try FileManager.default.setAttributes(
            [.creationDate: Date(timeIntervalSince1970: 2_000)],
            ofItemAtPath: newer.path
        )

        let catalog = ProjectCatalog(
            projectsRoot: root,
            fallbackOutputRoot: root.appendingPathComponent("fallback")
        )

        XCTAssertEqual(try catalog.initialDestination().displayName, "newer-project")
    }

    func testPreparingProjectDestinationCreatesItsSourceDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let project = root.appendingPathComponent("ai-tips", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let destination = ProjectDestination.project(directory: project, date: Date())

        let outputDirectory = try prepareOutputDirectory(for: destination)

        XCTAssertEqual(outputDirectory, project.appendingPathComponent("source", isDirectory: true))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputDirectory.path))
    }
}
