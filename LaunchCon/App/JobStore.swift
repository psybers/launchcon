import Foundation

/// Holds the currently displayed set of jobs for one selected domain group,
/// merging `launchctl` results with plist files discovered on disk.
final class JobStore {

    /// A sidebar entry: jobs may come from a launchd domain, a filesystem
    /// directory of plists, or both.
    struct DomainGroup: Hashable {
        let title: String
        /// Domain queried for live job state, if any.
        let launchdDomain: LaunchdDomain?
        /// Domain used when bootstrapping/loading a plist from this group.
        let bootstrapDomain: LaunchdDomain
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
                bootstrapDomain: .guiCurrentUser,
                plistDirectories: [homeLibrary("LaunchAgents")]
            ),
            DomainGroup(
                title: "LaunchAgents",
                launchdDomain: .guiCurrentUser,
                bootstrapDomain: .guiCurrentUser,
                plistDirectories: [URL(fileURLWithPath: "/Library/LaunchAgents")]
            ),
            DomainGroup(
                title: "LaunchDaemons",
                launchdDomain: nil,
                bootstrapDomain: .system,
                plistDirectories: [URL(fileURLWithPath: "/Library/LaunchDaemons")]
            ),
            DomainGroup(
                title: "System Agents",
                launchdDomain: nil,
                bootstrapDomain: .guiCurrentUser,
                plistDirectories: [URL(fileURLWithPath: "/System/Library/LaunchAgents")]
            ),
            DomainGroup(
                title: "System Daemons",
                launchdDomain: nil,
                bootstrapDomain: .system,
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

    // MARK: - Job actions

    enum JobAction {
        case load, unload, enable, disable, start, stop
    }

    /// Performs a launchctl action on a job, then reloads the list.
    /// Throws `LaunchctlError` on failure; the list is only reloaded on success.
    func perform(_ action: JobAction, on job: Job) async throws {
        switch action {
        case .load:
            guard let plistPath = job.plistPath else {
                throw LaunchctlError.invalidOutput("Job has no plist path")
            }
            try await Launchctl.load(plistPath: plistPath, domain: job.domain)
        case .unload:
            try await Launchctl.unload(label: job.label, domain: job.domain)
        case .enable:
            try await Launchctl.enable(label: job.label, domain: job.domain)
        case .disable:
            try await Launchctl.disable(label: job.label, domain: job.domain)
        case .start:
            try await Launchctl.kickstart(label: job.label, domain: job.domain)
        case .stop:
            try await Launchctl.kill(label: job.label, domain: job.domain)
        }
        await MainActor.run { self.reload() }
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

        // 1. Discover plists in this group's directories, keyed by Label.
        var discovered: [String: (url: URL, dict: [String: Any])] = [:]
        for directory in group.plistDirectories {
            for plistURL in Self.plistFiles(in: directory) {
                guard let dict = Plist.load(plistURL),
                      let label = Plist.label(in: dict)
                else { continue }
                discovered[label] = (plistURL, dict)
            }
        }

        var loaded: [Job] = []
        var disabledLabels = Set<String>()
        var firstError: String?

        // 2. If the group maps to a launchd domain, keep only jobs that
        //    correspond to this group's plists — the domain contains many
        //    unrelated services (e.g. all of Apple's session agents).
        if let domain = group.launchdDomain {
            do {
                disabledLabels = try await Launchctl.printDisabled(domain: domain)
            } catch {
                firstError = firstError ?? "print-disabled: \(error.localizedDescription)"
            }
            do {
                let all = try await Launchctl.list(domain: domain)
                for var job in all where discovered[job.label] != nil {
                    job.domain = domain
                    job.plistPath = discovered[job.label]?.url.path
                    job.plist = discovered[job.label]?.dict
                    job.isLoaded = true
                    loaded.append(job)
                }
            } catch {
                firstError = firstError ?? "list: \(error.localizedDescription)"
            }
        }

        // 3. Add discovered plists that aren't currently loaded.
        let loadedLabels = Set(loaded.map(\.label))
        for (label, entry) in discovered where !loadedLabels.contains(label) {
            loaded.append(Job(
                label: label,
                pid: nil,
                lastExitStatus: nil,
                domain: group.bootstrapDomain,
                plistPath: entry.url.path,
                isLoaded: false,
                isDisabled: false,
                plist: entry.dict
            ))
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
