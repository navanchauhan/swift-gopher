import Foundation
import GopherProxy
import Logging

/// Serves the proxy's requests for this server straight from the request processor,
/// without a network round trip.
final class LocalGopherFetcher: GopherFetching, @unchecked Sendable {
    // GopherRequestProcessor only holds immutable configuration.
    private let processor: GopherRequestProcessor

    init(processor: GopherRequestProcessor) {
        self.processor = processor
    }

    func fetch(host: String, port: Int, request: String) async throws -> Data {
        processor.process(request + "\r\n").data
    }
}

func makeHTTPProxy(
    logger: Logger,
    gopherdataDir: String,
    gopherdataHost: String,
    gopherdataPort: Int,
    enableSearch: Bool,
    disableGophermap: Bool,
    allowRemoteHosts: Bool,
    allowAllPorts: Bool
) -> GopherHTTPProxy {
    let processor = GopherRequestProcessor(
        logger: logger,
        gopherdataDir: gopherdataDir,
        gopherdataHost: gopherdataHost,
        gopherdataPort: gopherdataPort,
        enableSearch: enableSearch,
        disableGophermap: disableGophermap
    )
    return GopherHTTPProxy(
        policy: ProxyPolicy(
            localHost: gopherdataHost,
            localPort: gopherdataPort,
            allowRemoteHosts: allowRemoteHosts,
            allowAllPorts: allowAllPorts
        ),
        local: LocalGopherFetcher(processor: processor),
        remote: RemoteGopherFetcher(),
        logger: logger
    )
}

/// Seconds a client gets to send its full request before the connection is dropped.
let httpRequestTimeout: TimeInterval = 30
