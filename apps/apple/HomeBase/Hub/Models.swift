import Foundation

/// Any JSON value. The hub's `detail` and command `arg` fields are loosely typed.
enum JSONValue: Codable, Hashable {
    case string(String), number(Double), bool(Bool), object([String: JSONValue]), array([JSONValue]), null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .bool(let b): try c.encode(b)
        case .object(let o): try c.encode(o)
        case .array(let a): try c.encode(a)
        case .null: try c.encodeNil()
        }
    }

    var string: String? { if case .string(let s) = self { return s }; return nil }
    var int: Int? { if case .number(let n) = self { return Int(n) }; return nil }
    var bool: Bool? { if case .bool(let b) = self { return b }; return nil }
    var array: [JSONValue]? { if case .array(let a) = self { return a }; return nil }
    var object: [String: JSONValue]? { if case .object(let o) = self { return o }; return nil }
}

/// A device as the hub describes it. See shared/protocol/README.md.
struct Device: Codable, Identifiable, Hashable {
    struct Option: Codable, Hashable, Identifiable {
        let name: String
        let id: String
    }

    enum Power: String, Codable {
        case on, off, unknown
        init(from decoder: Decoder) throws {
            self = Power(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
        }
    }

    let id: String
    var name: String
    var kind: String
    var actions: [String]
    var apps: [Option]?
    var inputs: [Option]?
    var buttons: [String]?
    var power: Power
    var reachable: Bool
    var needsPairing: Bool
    var detail: [String: JSONValue]
    var updated: Double?

    var isOn: Bool { power == .on }
    var currentApp: String? { detail["app"]?.string }
    var volume: Int? { detail["volume"]?.int }
    var muted: Bool { detail["muted"]?.bool ?? false }
    func can(_ action: String) -> Bool { actions.contains(action) }
}

/// One command any app ran, as the hub broadcasts it.
struct HubEvent: Codable, Hashable {
    let ts: Double
    let device: String
    let action: String
    let arg: JSONValue?
    let source: String
    let ok: Bool
    let error: String?
}

/// Frames the hub sends on /api/live.
struct HubFrame: Decodable {
    let type: String
    let devices: [Device]?
    let device: Device?
    let event: HubEvent?
    let id: String?
    let ok: Bool?
    let error: String?
}

/// A command frame we send.
struct CommandFrame: Encodable {
    let type = "command"
    let id: String
    let device: String
    let action: String
    let arg: JSONValue?
    let source: String
}
