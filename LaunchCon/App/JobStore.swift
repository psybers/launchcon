import Foundation

/// Holds the currently displayed set of jobs for one selected domain group,
/// merging `launchctl` results with plist files discovered on disk.
final class JobStore {

    /// A sidebar entry: jobs may come from a launchd domain, a filesystem
    /// directory of plists, or both.
    struct DomainGroup: Hashable {
        let title: String
        let launchdDomain: LaunchdDomain?
        let plistDirectories: [URL]

        var id: String { title }
    }

    static func homeLibrary(_ components: String...) -> URL {
        var url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
        for c in components { url.appendPathComponent(c) }
        return url
    }

    static func defaultGroups() -> [DomainGroup] {
        [
            DomainGroup(
                title: "User Agents",
                launchdDomain: .guiCurrentUser,
                plistDirectories: [homeLibrary("LaunchAgents")]
            ),
            DomainGroup(
                title: "LaunchAgents",
                launchdDomain: nil,
                plistDirectories: [URL(fileURLWithPath: "/Library/LaunchAgents")]
            ),
            DomainGroup(
                title: "LaunchDaemons",
                launchdDomain: nil,
                plistDirectories: [URL(fileURLWithPath: "/Library/LaunchDaemons")]
            ),
            DomainGroup(
                title: "System Agents",
                launchdDomain: nil,
                plistDirectories: [URL(fileURLWithPath: "/System/Library/LaunchAgents")]
            ),
            DomainGroup(
                title: "System Daemons",
                launchdDomain: nil,
                plistDirectories: [URL(fileURLWithPath: "/System/Library/LaunchDaemons")]
            ),
        ]
    }

    let groups: [DomainGroup]

    private(set) var jobs: [Job] = []
    private(set) var isLoading = false
    /// Description of the last load failure, if any.
    private(set) var loadError: String?

    var selectedGroup: DomainGroup? {
        didSet { reload() }
    }

    var filterText = "" {
        didSet { notifyChange() }
    }

    /// Called on the main thread whenever `jobs`, `isLoading`, or the filter
    /// changes. Views should reload their data in response.
    var onChange: (() -> Void)?

    init(groups: [DomainGroup] = JobStore.defaultGroups()) {
        self.groups = groups
        self.selectedGroup = groups.first
    }

    var visibleJobs: [Job] {
        let filter = filterText.trimmingCharacters(in: .whitespaces)
        guard !filter.isEmpty else { return jobs }
        return jobs.filter { $0.label.localizedCaseInsensitiveContains(filter) }
    }

    func reload() {
        Task { await load() }
    }

    private func load() async {
        guard let group = selectedGroup else {
            await MainActor.run {
                self.jobs = []
                self.isLoading = false
                self.notifyChange()
            }
            return
        }

        await MainActor.run {
            self.isLoading = true
            self.notifyChange()
        }

        var loaded: [Job] = []
        var disabledLabels = Set<String>()
        var firstError: String?

        if let domain = group.launchdDomain {
            do {
                disabledLabels = try await Launchctl.printDisabled(domain: domain)
            } catch {
                firstError = firstError ?? "print-disabled: \(error.localizedDescription)"
            }
            do {
                loaded = try await Launchctl.list(domain: domain)
            } catch {
                firstError = firstError ?? "list: \(error.localizedDescription)"
            }
        }

        // Merge in plist files that aren't currently loaded.
        var knownLabels = Set(loaded.map(\.label))
        for directory in group.plistDirectories {
            for plistURL in Self.plistFiles(in: directory) {
                guard let dict = Plist.load(plistURL),
                      let label = Plist.label(in: dict),
                      !knownLabels.contains(label)
                else { continue }
                knownLabels.insert(label)

                let domain = group.launchdDomain
                    ?? LaunchdDomain(rawValue: directory.path)
                loaded.append(Job(
                    label: label,
                    pid: nil,
                    lastExitStatus: nil,
                    domain: domain,
                    plistPath: plistURL.path,
                    isLoaded: false,
                    isDisabled: false,
                    plist: dict
                ))
            }
        }

        for index in loaded.indices where disabledLabels.contains(loaded[index].label) {
            loaded[index].isDisabled = true
        }

        loaded.sort { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }

        await MainActor.run {
            self.jobs = loaded
            self.isLoading = false
            self.loadError = firstError
            self.notifyChange()
        }
    }

    private static func plistFiles(in directory: URL) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        return contents.filter { $0.pathExtension == "plist" }
    }

    private func notifyChange() {
        onChange?()
    }
}
