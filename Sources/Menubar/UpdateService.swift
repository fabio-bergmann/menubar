import Combine
import Foundation

/// Updates without an Apple Developer licence: the installed app remembers
/// which commit it was built from and where the checkout lives, compares that
/// with `origin/main`, and reruns `scripts/release-local.sh` to rebuild and
/// reinstall itself. See AGENTS.md.
final class UpdateService: ObservableObject {
    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case available(commits: Int)
        case installing
        case failed(String)

        var isFailure: Bool {
            if case .failed = self { return true }
            return false
        }
    }

    @Published private(set) var status: Status = .idle

    /// Baked into Info.plist by scripts/build-app.sh; absent from `swift run`.
    private let buildSHA = Bundle.main.object(forInfoDictionaryKey: "MBBuildSHA") as? String
    private let repository = (Bundle.main.object(forInfoDictionaryKey: "MBRepoPath") as? String)
        .map { URL(fileURLWithPath: $0) }
    private var installer: Process?

    private var script: URL? {
        repository?.appendingPathComponent("scripts/release-local.sh")
    }

    var canCheck: Bool {
        guard buildSHA?.isEmpty == false, let script else { return false }
        return status != .checking && status != .installing && FileManager.default.fileExists(atPath: script.path)
    }

    var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development build"
        guard let buildSHA, !buildSHA.isEmpty else { return version }
        return "Version \(version) (\(buildSHA.prefix(7)))"
    }

    var statusText: String {
        switch status {
        case .idle:
            if buildSHA?.isEmpty != false { return "Not an installed build, so there's nothing to update." }
            if !canCheck { return "The checkout this was built from has moved." }
            return "Builds from main in \(repository?.path ?? "")"
        case .checking: return "Checking…"
        case .upToDate: return "Up to date with main."
        case .available(let commits): return "\(commits) new commit\(commits == 1 ? "" : "s") on main."
        case .installing: return "Building. Menubar restarts when it's done."
        case .failed(let message): return message
        }
    }

    func check() {
        guard canCheck, let repository, let buildSHA else { return }
        status = .checking
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Self.compare(buildSHA: buildSHA, in: repository)
            DispatchQueue.main.async { self.status = result }
        }
    }

    private static func compare(buildSHA: String, in repository: URL) -> Status {
        let fetch = git(["fetch", "--quiet", "origin", "main"], in: repository)
        guard fetch.status == 0 else { return .failed("Couldn't reach GitHub: \(fetch.output)") }
        let ahead = git(["rev-list", "--count", "\(buildSHA)..origin/main"], in: repository)
        guard ahead.status == 0, let commits = Int(ahead.output) else {
            return .failed("Couldn't compare with main: \(ahead.output)")
        }
        return commits == 0 ? .upToDate : .available(commits: commits)
    }

    func install() {
        guard canCheck, let repository, let script else { return }
        let logs = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/Menubar")
        let log = logs.appendingPathComponent("release-local.log")
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: log.path, contents: nil)
        guard let output = try? FileHandle(forWritingTo: log) else {
            status = .failed("Couldn't write \(log.path)")
            return
        }

        // The script quits this app once the build succeeds and then installs
        // the new one, so it has to outlive us: only a failure is ever seen here.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path, "origin/main"]
        process.currentDirectoryURL = repository
        process.environment = Self.environment
        process.standardOutput = output
        process.standardError = output
        process.terminationHandler = { [weak self] process in
            guard process.terminationStatus != 0 else { return }
            let tail = (try? String(contentsOf: log, encoding: .utf8))?
                .split(separator: "\n").suffix(3).joined(separator: "\n") ?? ""
            DispatchQueue.main.async {
                self?.status = .failed("The build failed. \(tail)\nFull log: \(log.path)")
            }
        }
        do {
            try process.run()
            installer = process
            status = .installing
        } catch {
            status = .failed("Couldn't start the build: \(error.localizedDescription)")
        }
    }

    /// Apps launched from Finder get a bare PATH; git's credential helper and
    /// the Swift toolchain need the usual places.
    private static var environment: [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        environment["GIT_TERMINAL_PROMPT"] = "0"
        return environment
    }

    private static func git(_ arguments: [String], in directory: URL) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return (-1, error.localizedDescription)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return (process.terminationStatus, output)
    }
}
