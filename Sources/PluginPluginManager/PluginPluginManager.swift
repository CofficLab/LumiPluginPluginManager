import KernelCore
import ProviderDocsView
import ProviderPluginManaging
import ProviderPromptSuggestion
import ProviderSettingView
import SwiftUI
import LumiLoggingKit
import os

/// 插件管理插件
@MainActor
public final class PluginPluginManager: SuperPlugin, SuperLog {
    /// 默认插件标识。宿主可在装配时传入自己的 id。
    public static let defaultPluginID = "com.coffic.lumi.plugin.plugin-manager"

    /// 插件唯一标识。宿主可注入自己的品牌 id。
    public let id: String
    public let order = 90

    public let metadata: PluginMetadata

    /// 日志子系统跟随插件 id，便于宿主在系统日志中区分品牌。
    nonisolated let logger: Logger

    private var generatedAboutPluginIDs: [String] = []

    /// `SettingEntryItem` 的稳定 ID，供设置深链和入口注册共同使用。
    static let settingsEntryID = "plugin-manager"

    private var capability: PluginManagementCapabilityAdapter?
    private var viewModel: PluginManagementViewModel?
    private var observer: PluginManagementObserver?

    /// 设置 Provider 的引用。入口在 `onReady` 注册（见 `onBoot` 注释）。
    private var settingsProvider: (any SettingViewProviding)?

    /// 入口可见性策略。
    public enum EntryVisibility: Sendable {
        /// 始终注册「插件管理」入口（默认）。
        ///
        /// 宿主存在可配置插件时这是正确行为：用户在这里启停插件。
        case always
        /// 仅当宿主存在**用户可配置**的插件时才注册入口。
        ///
        /// 宿主的插件策略全是 `required` / `alwaysOn`（`isConfigurable` 为 false）
        /// 时，插件管理页必然是一个永远为空的列表 —— 这样的入口对用户没有意义，
        /// 反而让人以为功能坏了。此时跳过注册。
        ///
        /// - Note: 判断在 `onReady` 阶段进行。`onBoot` 阶段 order 更大的插件
        ///   尚未注册，`kernel.allPlugins` 还不完整，据此判断会漏掉插件。
        case onlyWhenConfigurablePluginsExist
    }

    /// 入口可见性策略。默认 `.always`，保持既有宿主的行为不变。
    public let entryVisibility: EntryVisibility

    /// 创建插件管理插件。
    ///
    /// - Parameters:
    ///   - id: 插件唯一标识，决定 `PluginMetadata.id` 与日志子系统。
    ///   - entryVisibility: 「插件管理」设置入口的可见性策略。
    public init(
        id: String = PluginPluginManager.defaultPluginID,
        entryVisibility: EntryVisibility = .always
    ) {
        self.id = id
        self.entryVisibility = entryVisibility
        self.metadata = PluginMetadata(
            id: id,
            name: pluginLocalization.string("Plugin Manager"),
            description: pluginLocalization.string("Manage all registered plugins."),
            version: "1.0.0",
            category: .system,
            stage: .stable,
            policy: .required
        )
        self.logger = Logger(subsystem: id, category: "PluginManager")
    }

    private var promptSuggestion: PromptSuggestion {
        PromptSuggestion(
            id: "\(id).browse",
            title: pluginLocalization.string("Browse Plugins"),
            order: order * 1000,
            systemImage: "puzzlepiece.extension",
            action: .openSettingsTab(Self.settingsEntryID),
            style: .additive
        )
    }

    private func registerPromptSuggestion(kernel: KernelCoreContainer, requiresEnable: Bool) {
        var suggestion = promptSuggestion
        suggestion.pluginID = id
        suggestion.requiresEnable = requiresEnable
        kernel.resolveProvider((any PromptSuggestionProviding).self)?.register(suggestion)
    }

    public func onRegister(kernel: KernelCoreContainer) throws {
        registerPromptSuggestion(kernel: kernel, requiresEnable: !kernel.isPluginEnabled(id: id))
        kernel.resolveProvider((any DocsViewProviding).self)?.addManual(
            DocsEntry(id: id, name: metadata.name) { PluginManagerManualView() }
        )
    }

    public func onBoot(kernel: KernelCoreContainer) throws {
        guard let settings = kernel.resolveProvider((any SettingViewProviding).self) else {
            logger.error("\(Self.t) SettingViewProviding not found")
            return
        }

        guard let manager = kernel.resolveProvider((any PluginManaging).self) else {
            logger.error("\(Self.t) PluginManaging not found")
            return
        }

        // 捕获 docs/provider 引用，供插件管理详情面板展示各插件的 about 视图。
        let docsProvider = kernel.resolveProvider((any DocsViewProviding).self)
        if docsProvider == nil {
            logger.error("\(Self.t) DocsViewProviding not found")
        }

        let capability = PluginManagementCapabilityAdapter(manager: manager)
        let viewModel = PluginManagementViewModel(
            capability: capability,
            docsCapability: PluginManagerDocsCapabilityAdapter(docs: docsProvider)
        )
        observer?.cancel()
        observer = PluginManagementObserver(
            capability: capability,
            viewModel: viewModel,
            subsystem: id
        )
        self.capability = capability
        self.viewModel = viewModel

        // 「插件管理」入口在 `onReady` 注册，而不是这里：`entryVisibility`
        // 需要依据**全部**插件的策略判断，而 `onBoot` 阶段 order 更大的插件
        // 尚未注册（见 `KernelCoreContainer.start` —— 先全部注册，再逐个 onBoot）。
        // 这里只把设置 Provider 的解析结果留到 onReady 使用。
        self.settingsProvider = settings
    }

    public func onReady(kernel: KernelCoreContainer) throws {
        // `onBoot` runs in plugin order. Plugins with a later order may not have
        // been registered when the settings ViewModel first snapshots the list.
        // Refresh after every plugin has completed Boot so the settings page
        // sees the complete registry, matching the old live Provider lookup.
        viewModel?.refresh()

        registerPromptSuggestion(kernel: kernel, requiresEnable: false)

        // 按可见性策略决定是否注册「插件管理」入口。
        //
        // `.onlyWhenConfigurablePluginsExist` 时，若宿主没有用户可配置的插件，
        // 这个页面必然是空的 —— 不注册入口，避免设置里出现一个点进去什么都没有
        // 的死路。此处是唯一可靠的判断时机：此刻全部插件已注册完毕。
        if let viewModel {
            if shouldRegisterSettingsEntry(kernel: kernel) {
                let entry = SettingEntryItem(
                    id: Self.settingsEntryID,
                    title: pluginLocalization.string("Plugin Manager"),
                    systemImage: "puzzlepiece.extension",
                    order: 3
                ) { [viewModel] in
                    PluginManagementView(viewModel: viewModel)
                }
                settingsProvider?.addEntries([entry])
            } else {
                logger.info(
                    "\(Self.t) skip plugin manager settings entry: host has no user-configurable plugins"
                )
            }
        }

        // 确保每个已启动插件都有 AboutView。插件自己的品牌化页面优先，
        // 这里只为尚未贡献页面的插件补充统一的详细元信息页。
        guard let docs = kernel.resolveProvider((any DocsViewProviding).self) else { return }
        for plugin in kernel.allPlugins where !docs.aboutEntries.contains(where: { $0.id == plugin.id }) {
            let metadata = plugin.metadata
            let isEnabled = kernel.isPluginEnabled(id: plugin.id)
            docs.addAbout(DocsEntry(id: plugin.id, name: metadata.name) {
                PluginDefaultAboutView(metadata: metadata, isEnabled: isEnabled)
            })
            generatedAboutPluginIDs.append(plugin.id)
        }
    }

    /// 是否应注册「插件管理」设置入口。
    private func shouldRegisterSettingsEntry(kernel: KernelCoreContainer) -> Bool {
        switch entryVisibility {
        case .always:
            return true
        case .onlyWhenConfigurablePluginsExist:
            return kernel.allPlugins.contains { $0.metadata.policy.isConfigurable }
        }
    }

    public func onEnable(kernel: KernelCoreContainer) async throws {
        registerPromptSuggestion(kernel: kernel, requiresEnable: false)
    }

    public func onShutdown(kernel: KernelCoreContainer) throws {
        observer?.cancel()
        observer = nil
        viewModel = nil
        capability = nil
        settingsProvider = nil
        kernel.resolveProvider((any SettingViewProviding).self)?
            .removeEntries(ids: [Self.settingsEntryID])

        if let docs = kernel.resolveProvider((any DocsViewProviding).self) {
            // DocsViewProviding predates Kernel contribution ownership, so
            // most plugins add their entries directly and do not have a
            // token for KernelCore to revoke. At this point the kernel is
            // stopping all plugins; clear the complete plugin-owned snapshot
            // so a stopped kernel cannot expose stale About/Manual entries.
            docs.replaceAboutEntries([])
            docs.replaceManualEntries([])
        }
        generatedAboutPluginIDs.removeAll()
    }

    public func onDisable(kernel: KernelCoreContainer) async throws {
        registerPromptSuggestion(kernel: kernel, requiresEnable: true)
    }

    public func onUnregister(kernel: KernelCoreContainer) throws {
        kernel.resolveProvider((any PromptSuggestionProviding).self)?.unregister(id: promptSuggestion.id)
        kernel.resolveProvider((any DocsViewProviding).self)?.removeEntries(id: id)
    }
}
