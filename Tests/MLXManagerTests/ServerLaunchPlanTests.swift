import Testing
@testable import MLXManager

@Suite("ServerLaunchPlan")
struct ServerLaunchPlanTests {

    @Test("disabled managed gateway uses the global server port instead of the preset port")
    func disabledManagedGatewayUsesGlobalServerPort() {
        let config = ServerConfig.fixture(name: "Direct").withPort(9999)
        var settings = AppSettings()
        settings.serverPort = 8088

        let plan = ServerLaunchPlan.plan(for: config, settings: settings)

        guard case let .direct(directConfig) = plan else {
            Issue.record("Expected a direct launch plan")
            return
        }
        #expect(directConfig.port == 8088)
        #expect(directConfig.model == config.model)
    }

    @Test("enabled managed gateway uses the global proxy and server ports")
    func enabledManagedGatewayUsesGlobalProxyAndServerPorts() {
        let config = ServerConfig.fixture(name: "Managed").withPort(9999)
        var settings = AppSettings()
        settings.managedGatewayEnabled = true
        settings.serverPort = 8088
        settings.managedGatewayPort = 8080

        let plan = ServerLaunchPlan.plan(for: config, settings: settings)

        guard case let .managed(routing) = plan else {
            Issue.record("Expected a managed launch plan")
            return
        }
        #expect(routing.publicPort == 8080)
        #expect(routing.backendPort == 8088)
        #expect(routing.backendConfig.port == routing.backendPort)
    }

    @Test("enabled managed gateway falls back to a hidden backend port when the ports match")
    func enabledManagedGatewayFallsBackToHiddenBackendPortWhenPortsMatch() {
        let config = ServerConfig.fixture(name: "Managed")
        var settings = AppSettings()
        settings.managedGatewayEnabled = true
        settings.serverPort = 8080
        settings.managedGatewayPort = 8080

        let plan = ServerLaunchPlan.plan(for: config, settings: settings)

        guard case let .managed(routing) = plan else {
            Issue.record("Expected a managed launch plan")
            return
        }
        #expect(routing.publicPort == 8080)
        #expect(routing.backendPort == 8180)
        #expect(routing.backendConfig.port == 8180)
    }
}
