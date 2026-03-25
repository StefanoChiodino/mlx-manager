import Foundation

/// Describes whether a server launch should be direct or run behind the managed gateway.
public enum ServerLaunchPlan: Equatable {
    case direct(ServerConfig)
    case managed(ManagedGatewayRouting)

    public static func plan(for config: ServerConfig, managedGatewayEnabled: Bool) -> ServerLaunchPlan {
        if managedGatewayEnabled {
            return .managed(ManagedGatewayRouting(config: config))
        }
        return .direct(config)
    }

    public static func plan(for config: ServerConfig, settings: AppSettings) -> ServerLaunchPlan {
        let directConfig = config.withPort(settings.serverPort)
        if settings.managedGatewayEnabled {
            return .managed(
                ManagedGatewayRouting(
                    config: directConfig,
                    publicPort: settings.managedGatewayPort,
                    backendPort: settings.managedGatewayBackendPort
                )
            )
        }
        return .direct(directConfig)
    }
}
