import Foundation
import Network
import Observation

/// Looks for the hub on the home network. It announces itself with Bonjour as `_homebase._tcp`.
@MainActor
@Observable
final class HubFinder {
    struct Found: Identifiable, Hashable {
        let name: String
        let address: String
        var id: String { address }
    }

    private(set) var found: [Found] = []
    private(set) var searching = false
    private var browser: NWBrowser?
    private var resolving: [NWConnection] = []

    func start() {
        guard browser == nil else { return }
        searching = true
        let b = NWBrowser(for: .bonjour(type: "_homebase._tcp", domain: nil), using: .tcp)
        b.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in self?.resolve(results) }
        }
        b.stateUpdateHandler = { [weak self] state in
            if case .failed = state { Task { @MainActor in self?.searching = false } }
        }
        b.start(queue: .main)
        browser = b
    }

    func stop() {
        browser?.cancel()
        browser = nil
        resolving.forEach { $0.cancel() }
        resolving = []
        searching = false
    }

    /// Bonjour gives a service name, not an address. Connect briefly to learn the IPv4 address
    /// and port, which is what the rest of the app stores.
    private func resolve(_ results: Set<NWBrowser.Result>) {
        resolving.forEach { $0.cancel() }
        resolving = []
        found = found.filter { f in results.contains { name(of: $0) == f.name } }

        for result in results {
            let params = NWParameters.tcp
            if let ip = params.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options { ip.version = .v4 }
            let conn = NWConnection(to: result.endpoint, using: params)
            let label = name(of: result)
            conn.stateUpdateHandler = { [weak self, weak conn] state in
                guard case .ready = state, let conn else { return }
                if case .hostPort(let host, let port)? = conn.currentPath?.remoteEndpoint {
                    var text = "\(host)"
                    if let pct = text.firstIndex(of: "%") { text = String(text[..<pct]) }
                    let item = Found(name: label, address: "\(text):\(port.rawValue)")
                    Task { @MainActor in
                        guard let self else { return }
                        self.found.removeAll { $0.name == label }
                        self.found.append(item)
                    }
                }
                conn.cancel()
            }
            conn.start(queue: .main)
            resolving.append(conn)
        }
    }

    private nonisolated func name(of result: NWBrowser.Result) -> String {
        if case .service(let name, _, _, _) = result.endpoint { return name }
        return "Home Base hub"
    }
}
