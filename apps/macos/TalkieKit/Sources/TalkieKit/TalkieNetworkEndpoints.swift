import Foundation

/// Constructs local Talkie URLs without scattering endpoint strings through UI code.
public enum TalkieNetworkEndpoints {
    public static var gatewayDisplayAddress: String {
        "localhost:\(TalkieNetworkPorts.gateway)"
    }

    public static func gateway(
        path: String = "",
        queryItems: [URLQueryItem] = []
    ) -> URL {
        loopbackHTTP(
            port: TalkieNetworkPorts.gateway,
            path: path,
            queryItems: queryItems
        )
    }

    public static func gatewayWebSocket(path: String = "") -> URL {
        makeURL(
            scheme: "ws",
            port: TalkieNetworkPorts.gateway,
            path: path,
            queryItems: []
        )
    }

    public static func loopbackHTTP(
        port: Int,
        path: String = "",
        queryItems: [URLQueryItem] = []
    ) -> URL {
        makeURL(scheme: "http", port: port, path: path, queryItems: queryItems)
    }

    private static func makeURL(
        scheme: String,
        port: Int,
        path: String,
        queryItems: [URLQueryItem]
    ) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "127.0.0.1"
        components.port = port
        components.path = path.isEmpty || path.hasPrefix("/") ? path : "/\(path)"
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else {
            preconditionFailure("Talkie could not construct a loopback endpoint.")
        }
        return url
    }
}
