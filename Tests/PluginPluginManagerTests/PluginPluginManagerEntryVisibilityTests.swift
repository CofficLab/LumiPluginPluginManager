import Foundation
import KernelCore
import ProviderPluginManaging
import ProviderSettingView
import Testing

@testable import PluginPluginManager

/// 「插件管理」设置入口的可见性策略（`EntryVisibility`）。
///
/// 背景：宿主的插件策略全是 `required` / `alwaysOn` 时（`isConfigurable` 为
/// false），插件管理页必然是一个永远为空的列表 —— 这样的入口对用户没有意义。
/// `.onlyWhenConfigurablePluginsExist` 让这类宿主跳过注册入口。
@MainActor
struct PluginPluginManagerEntryVisibilityTests {

    /// 默认策略是 `.always`：即使宿主没有可配置插件，入口也照常注册。
    ///
    /// 这条守卫盯住「默认行为被改掉」这个坑：Lumi 主项目有大量可配置插件，
    /// 它的 UI 测试硬断言侧边栏存在「Plugin Manager」入口。
    @Test("默认策略下入口始终注册")
    func defaultVisibilityAlwaysRegistersEntry() throws {
        let settings = DefaultSettingViewProviding()
        let kernel = KernelCoreContainer()
        try kernel.registerProvider((any SettingViewProviding).self, settings)
        try kernel.registerProvider(
            (any PluginManaging).self,
            DefaultPluginManager(kernel: kernel)
        )

        // 宿主只有一个 required 插件（插件管理器自身），没有可配置插件。
        let plugin = PluginPluginManager()
        try kernel.start(plugins: [plugin])

        #expect(settings.entries.contains { $0.id == "plugin-manager" })
    }

    /// 宿主没有可配置插件时，`.onlyWhenConfigurablePluginsExist` 不注册入口。
    @Test("宿主无可配置插件时不注册入口")
    func skipsEntryWhenNoConfigurablePluginsExist() throws {
        let settings = DefaultSettingViewProviding()
        let kernel = KernelCoreContainer()
        try kernel.registerProvider((any SettingViewProviding).self, settings)
        try kernel.registerProvider(
            (any PluginManaging).self,
            DefaultPluginManager(kernel: kernel)
        )

        let plugin = PluginPluginManager(
            entryVisibility: .onlyWhenConfigurablePluginsExist
        )
        try kernel.start(plugins: [
            plugin,
            TestPlugin(id: "always-on", policy: .alwaysOn),
            TestPlugin(id: "required", policy: .required),
        ])

        #expect(!settings.entries.contains { $0.id == "plugin-manager" })
    }

    /// 宿主存在可配置插件时，`.onlyWhenConfigurablePluginsExist` 注册入口。
    @Test("宿主存在可配置插件时注册入口")
    func registersEntryWhenConfigurablePluginsExist() throws {
        let settings = DefaultSettingViewProviding()
        let kernel = KernelCoreContainer()
        try kernel.registerProvider((any SettingViewProviding).self, settings)
        try kernel.registerProvider(
            (any PluginManaging).self,
            DefaultPluginManager(kernel: kernel)
        )

        let plugin = PluginPluginManager(
            entryVisibility: .onlyWhenConfigurablePluginsExist
        )
        try kernel.start(plugins: [
            plugin,
            TestPlugin(id: "optional", policy: .enabledByDefault),
        ])

        #expect(settings.entries.contains { $0.id == "plugin-manager" })
    }

    /// 可配置插件的 order 大于插件管理器时，判断仍要看到它。
    ///
    /// 这条守卫盯住「在 `onBoot` 阶段判断」这个坑：`onBoot` 按 order 依次执行，
    /// order 更大的插件此刻还没注册，据此判断会漏掉插件、错误地跳过入口。
    /// 判断必须等到 `onReady`（全部插件已注册）。
    @Test("order 更大的可配置插件也能被判定到")
    func detectsConfigurablePluginRegisteredAfterPluginManager() throws {
        let settings = DefaultSettingViewProviding()
        let kernel = KernelCoreContainer()
        try kernel.registerProvider((any SettingViewProviding).self, settings)
        try kernel.registerProvider(
            (any PluginManaging).self,
            DefaultPluginManager(kernel: kernel)
        )

        let plugin = PluginPluginManager(
            entryVisibility: .onlyWhenConfigurablePluginsExist
        )
        // 插件管理器 order = 90，可配置插件 order = 999（更大 → 更晚 boot）。
        try kernel.start(plugins: [
            plugin,
            TestPlugin(id: "late-optional", policy: .disabledByDefault, order: 999),
        ])

        #expect(settings.entries.contains { $0.id == "plugin-manager" })
    }

    /// `disabled` 策略的插件被内核彻底排除，既不注册也不启动 —— 不是可配置插件。
    @Test("disabled 策略插件不视为可配置插件")
    func disabledPolicyPluginIsNotConfigurable() throws {
        let settings = DefaultSettingViewProviding()
        let kernel = KernelCoreContainer()
        try kernel.registerProvider((any SettingViewProviding).self, settings)
        try kernel.registerProvider(
            (any PluginManaging).self,
            DefaultPluginManager(kernel: kernel)
        )

        let plugin = PluginPluginManager(
            entryVisibility: .onlyWhenConfigurablePluginsExist
        )
        try kernel.start(plugins: [
            plugin,
            TestPlugin(id: "turned-off", policy: .disabled),
        ])

        #expect(!settings.entries.contains { $0.id == "plugin-manager" })
    }
}

@MainActor
private final class TestPlugin: SuperPlugin {
    let id: String
    let order: Int
    let metadata: PluginMetadata

    init(id: String, policy: PluginEnablePolicy, order: Int = 999) {
        self.id = id
        self.order = order
        metadata = PluginMetadata(
            id: id,
            name: id,
            policy: policy
        )
    }
}
