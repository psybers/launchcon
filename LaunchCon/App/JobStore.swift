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
        let plistDirectories: [URL]

        var id: String { title }
    }

    static func homeLibrary(_ components: String...) -> URL {
        var url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
        for c in components { url.appendPathComponent(c) }
        return url
    }

    /// Homebrew service plist locations under common prefixes. Usually empty —
    /// `brew services` writes into the standard LaunchAgents/LaunchDaemons
    /// dirs — but included for completeness.
    static let homebrewPlistDirectories: [URL] = [
        URL(fileURLWithPath: "/opt/homebrew/Homebrew/Library/LaunchAgents"),
        URL(fileURLWithPath: "/opt/homebrew/Homebrew/Library/LaunchDaemons"),
        URL(fileURLWithPath: "/usr/local/Homebrew/Library/LaunchAgents"),
        URL(fileURLWithPath: "/usr/local/Homebrew/Library/LaunchDaemons"),
    ]

    static let serverDaemonDirectory = URL(fileURLWithPath:
        "/Applications/Server.app/Contents/ServerRoot/System/Library/LaunchDaemons")

    static let allPlistDirectories: [URL] = [
        homeLibrary("LaunchAgents"),
        URL(fileURLWithPath: "/Library/LaunchAgents"),
        URL(fileURLWithPath: "/Library/LaunchDaemons"),
        URL(fileURLWithPath: "/System/Library/LaunchAgents"),
        URL(fileURLWithPath: "/System/Library/LaunchDaemons"),
        serverDaemonDirectory,
    ] + homebrewPlistDirectories

    /// Service types matching LaunchControl's taxonomy.
    static func defaultGroups() -> [DomainGroup] {
        [
            DomainGroup(
                title: "All",
                launchdDomain: .guiCurrentUser,
                plistDirectories: allPlistDirectories
            ),
            DomainGroup(
                title: "User Agents",
                launchdDomain: .guiCurrentUser,
                plistDirectories: [homeLibrary("LaunchAgents")]
            ),
            DomainGroup(
                title: "Global Agents",
                launchdDomain: .guiCurrentUser,
                plistDirectories: [URL(fileURLWithPath: "/Library/LaunchAgents")]
            ),
            DomainGroup(
                title: "Global Daemons",
                launchdDomain: nil,
                plistDirectories: [URL(fileURLWithPath: "/Library/LaunchDaemons")]
            ),
            DomainGroup(
                title: "System Agents",
                launchdDomain: .guiCurrentUser,
                plistDirectories: [URL(fileURLWithPath: "/System/Library/LaunchAgents")]
            ),
            DomainGroup(
                title: "System Daemons",
                launchdDomain: nil,
                plistDirectories: [URL(fileURLWithPath: "/System/Library/LaunchDaemons")]
            ),
            DomainGroup(
                title: "Server Daemons",
                launchdDomain: nil,
                plistDirectories: [serverDaemonDirectory]
            ),
            DomainGroup(
                title: "Homebrew",
                launchdDomain: nil,
                plistDirectories: homebrewPlistDirectories
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

    /// Sidebar state filters; unchecked filters hide matching jobs.
    enum JobFilter: String, CaseIterable {
        case loaded, unloaded, disabled, enabled, running, stopped

        var title: String {
            switch self {
            case .loaded: return "Loaded"
            case .unloaded: return "Unloaded"
            case .disabled: return "Disabled"
            case .enabled: return "Enabled"
            case .running: return "Running"
            case .stopped: return "Stopped"
            }
        }

        func matches(_ job: Job) -> Bool {
            switch self {
            case .loaded: return job.isLoaded
            case .unloaded: return !job.isLoaded
            case .disabled: return job.isDisabled
            case .enabled: return !job.isDisabled
            case .running: return job.pid != nil
            case .stopped: return job.pid == nil
            }
        }
    }

    var filterText = "" {
        didSet { notifyChange() }
    }

    /// Filters unchecked in the sidebar. A job is hidden when it matches any
    /// filter in this set.
    var disabledFilters: Set<JobFilter> = [] {
        didSet { notifyChange() }
    }

    /// Active column sort from the job table; applied on top of `jobs` and
    /// the text/state filters in `visibleJobs`.
    var sortDescriptors: [NSSortDescriptor] = [] {
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
        var result = jobs
        if !disabledFilters.isEmpty {
            result = result.filter { job in
                !disabledFilters.contains { $0.matches(job) }
            }
        }
        let filter = filterText.trimmingCharacters(in: .whitespaces)
        if !filter.isEmpty {
            result = result.filter { $0.label.localizedCaseInsensitiveContains(filter) }
        }
        if !sortDescriptors.isEmpty {
            result.sort { Self.comesBefore($0, $1, descriptors: sortDescriptors) }
        }
        return result
    }

    /// Orders `a` before `b` per the sort descriptors; ties fall back to label.
    private static func comesBefore(_ a: Job, _ b: Job, descriptors: [NSSortDescriptor]) -> Bool {
        for descriptor in descriptors {
            let ordering = compare(a, b, key: descriptor.key ?? "", ascending: descriptor.ascending)
            if ordering != .orderedSame { return ordering == .orderedAscending }
        }
        return a.label.localizedCaseInsensitiveCompare(b.label) == .orderedAscending
    }

    private static func compare(_ a: Job, _ b: Job, key: String, ascending: Bool) -> ComparisonResult {
        let ordering: ComparisonResult
        switch key {
        case "label":
            ordering = a.label.localizedCaseInsensitiveCompare(b.label)
        case "pid":
            ordering = compareOptional(a.pid, b.pid)
        case "status":
            ordering = a.statusText.localizedCaseInsensitiveCompare(b.statusText)
        case "domain":
            ordering = a.domain.rawValue.localizedCaseInsensitiveCompare(b.domain.rawValue)
        case "path":
            ordering = (a.plistPath ?? "").localizedCaseInsensitiveCompare(b.plistPath ?? "")
        default:
            ordering = .orderedSame
        }
        switch ordering {
        case .orderedSame: return .orderedSame
        case .orderedAscending: return ascending ? .orderedAscending : .orderedDescending
        case .orderedDescending: return ascending ? .orderedDescending : .orderedAscending
        }
    }

    /// nils sort last when ascending.
    private static func compareOptional(_ a: Int?, _ b: Int?) -> ComparisonResult {
        switch (a, b) {
        case let (x?, y?): return x < y ? .orderedAscending : x > y ? .orderedDescending : .orderedSame
        case (_?, nil): return .orderedAscending
        case (nil, _?): return .orderedDescending
        case (nil, nil): return .orderedSame
        }
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

    /// Unloads and re-bootstraps a service so plist changes take effect.
    func reloadService(label: String, domain: LaunchdDomain, plistPath: String) async throws {
        try await Launchctl.unload(label: label, domain: domain)
        try await Launchctl.load(plistPath: plistPath, domain: domain)
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
                domain: LaunchdDomain.bootstrapDomain(forPlistAt: entry.url),
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

        await MainActor.run {[loaded, firstError] in
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
