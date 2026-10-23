import Foundation
import WallflowerHookCore

/// Connect and Disconnect for one environment: the helper, the plan, the safe write, the manifest.
/// The Agents tab, the welcome and the tests all go through it.
struct AgentConnector: Sendable {
    let environment: AgentEnvironment
    let helper: HelperInstaller
    var store: IntegrationStore { IntegrationStore(environment: environment) }

    init(environment: AgentEnvironment, helperSource: URL? = HelperInstaller.bundledHelper) {
        self.environment = environment
        helper = HelperInstaller(environment: environment, source: helperSource)
    }

    /// What Connect would write, for the consent sheet. Throws `ManualSetup` when it can't write.
    func plan(_ tool: AgentTool) throws -> ChangePlan {
        guard let integration = AgentCatalog.integration(for: tool) else { return ChangePlan(tool: tool, changes: []) }
        return try integration.connectPlan(in: environment)
    }

    /// Writes `plan` (the one the person agreed to) after putting the helper in place. A drop-in that
    /// needs no helper (OpenCode) skips it.
    func connect(_ plan: ChangePlan) throws {
        if plan.tool != .opencode {
            let created = try helper.install()
            if !created.isEmpty {
                var manifest = store.loadManifest()
                manifest.helperDirectories += created.map(\.path)
                try store.saveManifest(manifest)
            }
        }
        guard !plan.isEmpty else {
            // Already in place (by hand, or a second Connect): still remember it as connected.
            var manifest = store.loadManifest()
            if manifest.tools[plan.tool.rawValue] == nil {
                manifest.tools[plan.tool.rawValue] = IntegrationManifest.ToolRecord(connectedAt: Date(), files: [])
                try store.saveManifest(manifest)
            }
            return
        }
        try store.applyConnect(plan)
    }

    /// Plans and writes Connect in one step.
    func connect(_ tool: AgentTool) throws {
        try connect(plan(tool))
    }

    /// What Disconnect would write.
    func disconnectPlan(_ tool: AgentTool) throws -> ChangePlan {
        guard let integration = AgentCatalog.integration(for: tool) else { return ChangePlan(tool: tool, changes: []) }
        return try integration.disconnectPlan(in: environment, record: store.loadManifest().tools[tool.rawValue])
    }

    /// Removes Wallflower's entries or files for `tool`; with the last tool gone, the helper too.
    func disconnect(_ tool: AgentTool) throws {
        try store.applyDisconnect(disconnectPlan(tool))
        removeHelperIfUnused()
    }

    /// Settings > Agents > Disconnect all: every tool with Wallflower's hooks in place or on record.
    /// Returns the tools it could not disconnect, with the reason.
    @discardableResult
    func disconnectAll() -> [(AgentTool, Error)] {
        var failures: [(AgentTool, Error)] = []
        let recorded = Set(store.loadManifest().tools.keys)
        for tool in AgentTool.allCases {
            guard let integration = AgentCatalog.integration(for: tool) else { continue }
            let state = integration.state(in: environment)
            guard recorded.contains(tool.rawValue) || state == .connected || state == .outdated else { continue }
            do {
                try store.applyDisconnect(disconnectPlan(tool))
            } catch {
                failures.append((tool, error))
            }
        }
        removeHelperIfUnused()
        return failures
    }

    /// The tools on record as connected.
    var connectedTools: Set<AgentTool> {
        Set(store.loadManifest().tools.keys.compactMap(AgentTool.init(rawValue:)))
    }

    private func removeHelperIfUnused() {
        let manifest = store.loadManifest()
        guard manifest.tools.keys.allSatisfy({ $0 == AgentTool.opencode.rawValue }) else { return }
        helper.uninstall(createdDirectories: manifest.helperDirectories)
        var cleared = manifest
        cleared.helperDirectories = []
        try? store.saveManifest(cleared)
    }
}
