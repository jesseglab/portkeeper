import Foundation

struct ProjectManifest: Decodable {
    let version: Int
    let project: String
    let services: [ManifestService]
}

struct ManifestService: Decodable {
    let name: String
    let directory: String
    let command: String
    let port: Int?
    let url: String?
}

struct ImportedProject: Identifiable {
    let id = UUID()
    let sourceURL: URL?
    let name: String
    let services: [ServiceConfig]

    static func load(from file: URL) throws -> ImportedProject {
        try parse(data: Data(contentsOf: file), sourceURL: file, baseDirectory: file.deletingLastPathComponent())
    }

    static func paste(_ text: String, baseDirectory: URL? = nil) throws -> ImportedProject {
        var json = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if json.hasPrefix("```") {
            var lines = json.components(separatedBy: "\n")
            guard lines.count >= 3, lines.last?.trimmingCharacters(in: .whitespaces) == "```" else {
                throw ImportError.message("Close the JSON code block, or paste just its contents.")
            }
            lines.removeFirst(); lines.removeLast()
            json = lines.joined(separator: "\n")
        }
        return try parse(data: Data(json.utf8), sourceURL: nil, baseDirectory: baseDirectory)
    }

    private static func parse(data: Data, sourceURL: URL?, baseDirectory: URL?) throws -> ImportedProject {
        guard data.count <= 1_000_000 else { throw ImportError.message("Project JSON must be smaller than 1 MB.") }
        let manifest: ProjectManifest
        do { manifest = try JSONDecoder().decode(ProjectManifest.self, from: data) }
        catch { throw ImportError.invalidJSON(error.localizedDescription) }

        guard manifest.version == 1 else { throw ImportError.message("Unsupported version. Portkeeper expects version 1.") }
        let project = manifest.project.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !project.isEmpty, project.count <= 80 else { throw ImportError.message("Project name must be 1–80 characters.") }
        guard !manifest.services.isEmpty, manifest.services.count <= 30 else {
            throw ImportError.message("Include between 1 and 30 services.")
        }

        var names = Set<String>()
        var ports = Set<Int>()
        var configs: [ServiceConfig] = []
        for service in manifest.services {
            let name = service.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let directory = service.directory.trimmingCharacters(in: .whitespacesAndNewlines)
            let command = service.command.trimmingCharacters(in: .whitespacesAndNewlines)
            let url = (service.url ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name.count <= 80, names.insert(name.lowercased()).inserted else {
                throw ImportError.message("Service names must be unique and 1–80 characters.")
            }
            guard !directory.isEmpty, !command.isEmpty, command.count <= 2_000, !command.contains("\n") else {
                throw ImportError.message("\(name): provide a folder and a single-line command.")
            }
            if let port = service.port {
                guard (1...65_535).contains(port), ports.insert(port).inserted else {
                    throw ImportError.message("\(name): port must be unique and between 1 and 65535.")
                }
            }
            if !url.isEmpty, !["http", "https"].contains(URLComponents(string: url)?.scheme?.lowercased() ?? "") {
                throw ImportError.message("\(name): open URL must use http or https.")
            }
            let path: String
            if directory.hasPrefix("~/") { path = NSString(string: directory).expandingTildeInPath }
            else if directory.hasPrefix("/") { path = directory }
            else {
                guard let baseDirectory else {
                    throw ImportError.message("\(name): choose a project folder for relative paths, or use an absolute directory in the JSON.")
                }
                path = baseDirectory.appendingPathComponent(directory).path
            }
            let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: standardized, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw ImportError.message("\(name): project folder does not exist: \(standardized)")
            }
            configs.append(.init(name: name, group: project, directory: standardized,
                                 command: command, port: service.port, url: url))
        }
        return .init(sourceURL: sourceURL, name: project, services: configs)
    }
}

enum ImportError: LocalizedError {
    case invalidJSON(String)
    case message(String)

    var errorDescription: String? {
        switch self {
        case .invalidJSON(let detail): return "Invalid Portkeeper JSON: \(detail)"
        case .message(let detail): return detail
        }
    }
}
