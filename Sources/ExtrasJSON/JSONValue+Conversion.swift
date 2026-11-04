// Conversions between Swift values and `JSONValue` that work without Codable, so they are available in Embedded Swift.

public enum JSONValueDecodingFailure: Error, Equatable, CustomStringConvertible {
    case typeMismatch(expected: String, path: String)
    case missingMember(path: String)
    case unknownRawValue(path: String)

    public var description: String {
        switch self {
        case .typeMismatch(let expected, let path): "expected \(expected) at \(path)"
        case .missingMember(let path): "missing \(path)"
        case .unknownRawValue(let path): "unknown value at \(path)"
        }
    }

    public func inside(_ component: String) -> JSONValueDecodingFailure {
        switch self {
        case .typeMismatch(let expected, let path): .typeMismatch(expected: expected, path: component + path)
        case .missingMember(let path): .missingMember(path: component + path)
        case .unknownRawValue(let path): .unknownRawValue(path: component + path)
        }
    }
}

public protocol JSONValueEncodable {
    var jsonValue: JSONValue { get }
}

public protocol JSONValueDecodable {
    init(jsonValue: JSONValue) throws(JSONValueDecodingFailure)
}

public typealias JSONValueCodable = JSONValueEncodable & JSONValueDecodable

extension JSONValueDecodable {
    public init(jsonData: some Collection<UInt8>) throws {
        self = try Self(jsonValue: try JSONParser().parse(bytes: jsonData))
    }
}

extension JSONValue {
    public init(_ value: some JSONValueEncodable) {
        self = value.jsonValue
    }

    public subscript(key: String) -> JSONValue? {
        if case .object(let members) = self { members[key] } else { nil }
    }

    public func member<Member: JSONValueDecodable>(
        _ key: String,
        as memberType: Member.Type = Member.self
    ) throws(JSONValueDecodingFailure) -> Member {
        guard case .object(let members) = self else {
            throw .typeMismatch(expected: "an object", path: "")
        }
        guard let member = members[key] else { throw .missingMember(path: "." + key) }
        do {
            return try Member(jsonValue: member)
        } catch {
            throw error.inside("." + key)
        }
    }

    /// `nil` when the member is missing or `null`.
    public func memberIfPresent<Member: JSONValueDecodable>(
        _ key: String,
        as memberType: Member.Type = Member.self
    ) throws(JSONValueDecodingFailure) -> Member? {
        guard case .object(let members) = self else {
            throw .typeMismatch(expected: "an object", path: "")
        }
        guard let member = members[key], member != .null else { return nil }
        do {
            return try Member(jsonValue: member)
        } catch {
            throw error.inside("." + key)
        }
    }

    public var jsonText: String {
        var bytes: [UInt8] = []
        appendBytes(to: &bytes)
        return String(decoding: bytes, as: UTF8.self)
    }
}

extension JSONValue: JSONValueCodable {
    public var jsonValue: JSONValue { self }

    public init(jsonValue: JSONValue) {
        self = jsonValue
    }
}

extension JSONValue: ExpressibleByNilLiteral, ExpressibleByBooleanLiteral,
    ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral,
    ExpressibleByStringLiteral, ExpressibleByArrayLiteral,
    ExpressibleByDictionaryLiteral
{
    public init(nilLiteral: ()) { self = .null }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(integerLiteral value: Int) { self = .number(String(value)) }
    public init(floatLiteral value: Double) { self = value.jsonValue }
    public init(stringLiteral value: String) { self = .string(value) }
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        var members: [String: JSONValue] = [:]
        for (key, value) in elements { members[key] = value }
        self = .object(members)
    }
}

extension Bool: JSONValueCodable {
    public var jsonValue: JSONValue { .bool(self) }

    public init(jsonValue: JSONValue) throws(JSONValueDecodingFailure) {
        guard case .bool(let value) = jsonValue else { throw .typeMismatch(expected: "a boolean", path: "") }
        self = value
    }
}

extension String: JSONValueCodable {
    public var jsonValue: JSONValue { .string(self) }

    public init(jsonValue: JSONValue) throws(JSONValueDecodingFailure) {
        guard case .string(let value) = jsonValue else { throw .typeMismatch(expected: "a string", path: "") }
        self = value
    }
}

extension Double: JSONValueCodable {
    /// JSON has no infinity or NaN.
    public var jsonValue: JSONValue { isFinite ? .number("\(self)") : .null }

    public init(jsonValue: JSONValue) throws(JSONValueDecodingFailure) {
        guard case .number(let text) = jsonValue, let value = Double(text) else {
            throw .typeMismatch(expected: "a number", path: "")
        }
        self = value
    }
}

extension Float: JSONValueCodable {
    public var jsonValue: JSONValue { Double(self).jsonValue }

    public init(jsonValue: JSONValue) throws(JSONValueDecodingFailure) {
        self = Float(try Double(jsonValue: jsonValue))
    }
}

extension JSONValueEncodable where Self: FixedWidthInteger {
    public var jsonValue: JSONValue { .number(String(self)) }
}

extension JSONValueDecodable where Self: FixedWidthInteger {
    public init(jsonValue: JSONValue) throws(JSONValueDecodingFailure) {
        guard let value = Self(exactly: try Double(jsonValue: jsonValue)) else {
            throw .typeMismatch(expected: "an integer", path: "")
        }
        self = value
    }
}

extension Int: JSONValueCodable {}
extension Int8: JSONValueCodable {}
extension Int16: JSONValueCodable {}
extension Int32: JSONValueCodable {}
extension Int64: JSONValueCodable {}
extension UInt: JSONValueCodable {}
extension UInt8: JSONValueCodable {}
extension UInt16: JSONValueCodable {}
extension UInt32: JSONValueCodable {}
extension UInt64: JSONValueCodable {}

extension Optional: JSONValueEncodable where Wrapped: JSONValueEncodable {
    public var jsonValue: JSONValue { self?.jsonValue ?? .null }
}

extension Optional: JSONValueDecodable where Wrapped: JSONValueDecodable {
    public init(jsonValue: JSONValue) throws(JSONValueDecodingFailure) {
        self = jsonValue == .null ? nil : try Wrapped(jsonValue: jsonValue)
    }
}

extension Array: JSONValueEncodable where Element: JSONValueEncodable {
    public var jsonValue: JSONValue { .array(map { $0.jsonValue }) }
}

extension Array: JSONValueDecodable where Element: JSONValueDecodable {
    public init(jsonValue: JSONValue) throws(JSONValueDecodingFailure) {
        guard case .array(let elements) = jsonValue else { throw .typeMismatch(expected: "an array", path: "") }
        var values: [Element] = []
        values.reserveCapacity(elements.count)
        for (index, element) in elements.enumerated() {
            do {
                values.append(try Element(jsonValue: element))
            } catch {
                throw error.inside("[\(index)]")
            }
        }
        self = values
    }
}

extension Set: JSONValueEncodable where Element: JSONValueEncodable {
    public var jsonValue: JSONValue { .array(map { $0.jsonValue }) }
}

extension Set: JSONValueDecodable where Element: JSONValueDecodable {
    public init(jsonValue: JSONValue) throws(JSONValueDecodingFailure) {
        self = Set(try [Element](jsonValue: jsonValue))
    }
}

extension Dictionary: JSONValueEncodable where Key == String, Value: JSONValueEncodable {
    public var jsonValue: JSONValue { .object(mapValues { $0.jsonValue }) }
}

extension Dictionary: JSONValueDecodable where Key == String, Value: JSONValueDecodable {
    public init(jsonValue: JSONValue) throws(JSONValueDecodingFailure) {
        guard case .object(let members) = jsonValue else { throw .typeMismatch(expected: "an object", path: "") }
        var values: [String: Value] = [:]
        for (key, member) in members {
            do {
                values[key] = try Value(jsonValue: member)
            } catch {
                throw error.inside("." + key)
            }
        }
        self = values
    }
}

extension JSONValueEncodable where Self: RawRepresentable, RawValue: JSONValueEncodable {
    public var jsonValue: JSONValue { rawValue.jsonValue }
}

extension JSONValueDecodable where Self: RawRepresentable, RawValue: JSONValueDecodable {
    public init(jsonValue: JSONValue) throws(JSONValueDecodingFailure) {
        guard let value = Self(rawValue: try RawValue(jsonValue: jsonValue)) else {
            throw .unknownRawValue(path: "")
        }
        self = value
    }
}
