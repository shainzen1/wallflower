import Foundation

/// A strict JSON document kept as its bytes plus the byte range of every value, so an edit splices
/// text in or out and leaves every other byte alone (key order, spacing, number spelling). Strict
/// means RFC 8259 and nothing more: no comments, no trailing commas, no byte order mark, no duplicate
/// keys. A file that is not strict is never edited; the installers offer the lines to copy instead.
struct JSONText {
    struct ParseError: Error, Equatable {
        var offset: Int
        var reason: String
    }

    indirect enum Value {
        case object([Member])
        case array([Node])
        case string(String)
        case number
        case bool(Bool)
        case null
    }

    struct Node {
        var value: Value
        /// From the first byte of the value to just past its last.
        var range: Range<Int>

        var members: [Member] {
            if case .object(let members) = value { return members }
            return []
        }

        var elements: [Node] {
            if case .array(let elements) = value { return elements }
            return []
        }

        var isObject: Bool {
            if case .object = value { return true }
            return false
        }

        var isArray: Bool {
            if case .array = value { return true }
            return false
        }

        var string: String? {
            if case .string(let text) = value { return text }
            return nil
        }

        var bool: Bool? {
            if case .bool(let flag) = value { return flag }
            return nil
        }

        /// The member value under `key`, nil when absent or this is no object.
        subscript(key: String) -> Node? {
            members.first { $0.key == key }?.node
        }

        /// Every string anywhere below this node, keys excluded.
        var allStrings: [String] {
            switch value {
            case .string(let text): [text]
            case .object(let members): members.flatMap(\.node.allStrings)
            case .array(let elements): elements.flatMap(\.allStrings)
            case .number, .bool, .null: []
            }
        }
    }

    struct Member {
        var key: String
        /// Where the key's opening quote is: a member spans `keyStart ..< node.range.upperBound`.
        var keyStart: Int
        var node: Node
    }

    let bytes: [UInt8]
    let root: Node

    init(_ data: Data) throws {
        try self.init(bytes: [UInt8](data))
    }

    init(bytes: [UInt8]) throws {
        var parser = Parser(bytes: bytes)
        root = try parser.parseDocument()
        self.bytes = bytes
    }

    var data: Data { Data(bytes) }

    /// The value at a path of object keys from the root, nil when any step is missing.
    func node(at path: [String]) -> Node? {
        var node = root
        for key in path {
            guard let next = node[key] else { return nil }
            node = next
        }
        return node
    }

    // MARK: Edits (each returns the new bytes; parse them again for the next edit)

    /// Appends `"key": value` as the last member of the object `object`.
    func appendingMember(to object: Node, key: String, value: JSONLiteral) -> [UInt8] {
        let keyText = JSONLiteral.string(key).render(indent: "", unit: "", compact: true)
        return appending(to: object, children: object.members.map { ($0.keyStart, $0.node.range.upperBound) }) { indent, compact in
            keyText + ": " + value.render(indent: indent, unit: indentUnit, compact: compact)
        }
    }

    /// Appends `value` as the last element of the array `array`.
    func appendingElement(to array: Node, value: JSONLiteral) -> [UInt8] {
        appending(to: array, children: array.elements.map { ($0.range.lowerBound, $0.range.upperBound) }) { indent, compact in
            value.render(indent: indent, unit: indentUnit, compact: compact)
        }
    }

    /// Removes the member at `index` of `object`, with the comma and the whitespace that joined it.
    func removingMember(of object: Node, at index: Int) -> [UInt8] {
        removing(from: object, children: object.members.map { ($0.keyStart, $0.node.range.upperBound) }, at: index)
    }

    /// Removes the element at `index` of `array`, with the comma and the whitespace that joined it.
    func removingElement(of array: Node, at index: Int) -> [UInt8] {
        removing(from: array, children: array.elements.map { ($0.range.lowerBound, $0.range.upperBound) }, at: index)
    }

    /// The file's indentation step: the whitespace of the first indented line, two spaces by default.
    var indentUnit: String {
        var index = 0
        while index < bytes.count {
            if bytes[index] == UInt8(ascii: "\n") {
                var end = index + 1
                while end < bytes.count, bytes[end] == UInt8(ascii: " ") || bytes[end] == UInt8(ascii: "\t") { end += 1 }
                if end > index + 1, end < bytes.count, bytes[end] != UInt8(ascii: "\n") {
                    return String(decoding: bytes[(index + 1)..<end], as: UTF8.self)
                }
            }
            index += 1
        }
        return "  "
    }

    // MARK: Private

    /// The whitespace at the start of the line that holds `offset`.
    private func lineIndent(at offset: Int) -> String {
        var start = offset
        while start > 0, bytes[start - 1] != UInt8(ascii: "\n") { start -= 1 }
        var end = start
        while end < bytes.count, bytes[end] == UInt8(ascii: " ") || bytes[end] == UInt8(ascii: "\t") { end += 1 }
        return String(decoding: bytes[start..<end], as: UTF8.self)
    }

    private func containsNewline(_ range: Range<Int>) -> Bool {
        bytes[range].contains(UInt8(ascii: "\n"))
    }

    /// Inserts a new last child. A container laid out one child per line gets `,\n<indent>child`
    /// after its last child; a one-line container `, child`; an empty one its child on a line of its own.
    private func appending(
        to container: Node, children: [(start: Int, end: Int)], render: (_ indent: String, _ compact: Bool) -> String
    ) -> [UInt8] {
        let open = container.range.lowerBound
        let close = container.range.upperBound - 1
        var result = bytes
        if let last = children.last, let first = children.first {
            let multiline = containsNewline(open..<first.start)
            let text = multiline
                ? ",\n" + lineIndent(at: first.start) + render(lineIndent(at: first.start), false)
                : ", " + render("", true)
            result.insert(contentsOf: Array(text.utf8), at: last.end)
        } else {
            let outer = lineIndent(at: open)
            let inner = outer + indentUnit
            let text = "\n" + inner + render(inner, false) + "\n" + outer
            result.replaceSubrange((open + 1)..<close, with: Array(text.utf8))
        }
        return result
    }

    private func removing(from container: Node, children: [(start: Int, end: Int)], at index: Int) -> [UInt8] {
        guard children.indices.contains(index) else { return bytes }
        var result = bytes
        if children.count == 1 {
            result.replaceSubrange((container.range.lowerBound + 1)..<(container.range.upperBound - 1), with: [])
        } else if index > 0 {
            result.replaceSubrange(children[index - 1].end..<children[index].end, with: [])
        } else {
            result.replaceSubrange(children[0].start..<children[1].start, with: [])
        }
        return result
    }

    // MARK: Parser

    private struct Parser {
        let bytes: [UInt8]
        var index = 0
        var depth = 0

        init(bytes: [UInt8]) {
            self.bytes = bytes
        }

        mutating func parseDocument() throws -> Node {
            if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { throw ParseError(offset: 0, reason: "byte order mark") }
            skipWhitespace()
            let node = try parseValue()
            skipWhitespace()
            guard index == bytes.count else { throw fail("text after the value") }
            return node
        }

        private func fail(_ reason: String) -> ParseError {
            ParseError(offset: index, reason: reason)
        }

        private mutating func skipWhitespace() {
            while index < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[index]) { index += 1 }
        }

        private mutating func parseValue() throws -> Node {
            guard index < bytes.count else { throw fail("unexpected end") }
            let start = index
            switch bytes[index] {
            case UInt8(ascii: "{"): return try parseObject()
            case UInt8(ascii: "["): return try parseArray()
            case UInt8(ascii: "\""): return Node(value: .string(try parseString()), range: start..<index)
            case UInt8(ascii: "t"): try literal("true"); return Node(value: .bool(true), range: start..<index)
            case UInt8(ascii: "f"): try literal("false"); return Node(value: .bool(false), range: start..<index)
            case UInt8(ascii: "n"): try literal("null"); return Node(value: .null, range: start..<index)
            case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"):
                try parseNumber()
                return Node(value: .number, range: start..<index)
            default: throw fail("unexpected character")
            }
        }

        private mutating func literal(_ word: String) throws {
            let expected = Array(word.utf8)
            guard index + expected.count <= bytes.count, Array(bytes[index..<(index + expected.count)]) == expected else {
                throw fail("unknown literal")
            }
            index += expected.count
        }

        private mutating func enter() throws {
            depth += 1
            guard depth <= 64 else { throw fail("nested too deep") }
        }

        private mutating func parseObject() throws -> Node {
            try enter()
            defer { depth -= 1 }
            let start = index
            index += 1
            skipWhitespace()
            var members: [Member] = []
            var keys = Set<String>()
            if index < bytes.count, bytes[index] == UInt8(ascii: "}") {
                index += 1
                return Node(value: .object([]), range: start..<index)
            }
            while true {
                skipWhitespace()
                guard index < bytes.count, bytes[index] == UInt8(ascii: "\"") else { throw fail("expected a key") }
                let keyStart = index
                let key = try parseString()
                guard keys.insert(key).inserted else { throw fail("duplicate key \(key)") }
                skipWhitespace()
                guard index < bytes.count, bytes[index] == UInt8(ascii: ":") else { throw fail("expected ':'") }
                index += 1
                skipWhitespace()
                let value = try parseValue()
                members.append(Member(key: key, keyStart: keyStart, node: value))
                skipWhitespace()
                guard index < bytes.count else { throw fail("unexpected end") }
                if bytes[index] == UInt8(ascii: ",") {
                    index += 1
                    continue
                }
                guard bytes[index] == UInt8(ascii: "}") else { throw fail("expected ',' or '}'") }
                index += 1
                return Node(value: .object(members), range: start..<index)
            }
        }

        private mutating func parseArray() throws -> Node {
            try enter()
            defer { depth -= 1 }
            let start = index
            index += 1
            skipWhitespace()
            var elements: [Node] = []
            if index < bytes.count, bytes[index] == UInt8(ascii: "]") {
                index += 1
                return Node(value: .array([]), range: start..<index)
            }
            while true {
                skipWhitespace()
                elements.append(try parseValue())
                skipWhitespace()
                guard index < bytes.count else { throw fail("unexpected end") }
                if bytes[index] == UInt8(ascii: ",") {
                    index += 1
                    continue
                }
                guard bytes[index] == UInt8(ascii: "]") else { throw fail("expected ',' or ']'") }
                index += 1
                return Node(value: .array(elements), range: start..<index)
            }
        }

        private mutating func parseString() throws -> String {
            index += 1
            var scalars = String.UnicodeScalarView()
            var raw: [UInt8] = []
            func flush() throws {
                guard !raw.isEmpty else { return }
                guard let text = String(validating: raw, as: UTF8.self) else { throw fail("invalid UTF-8") }
                scalars.append(contentsOf: text.unicodeScalars)
                raw.removeAll()
            }
            while index < bytes.count {
                let byte = bytes[index]
                switch byte {
                case UInt8(ascii: "\""):
                    try flush()
                    index += 1
                    return String(scalars)
                case UInt8(ascii: "\\"):
                    try flush()
                    index += 1
                    guard index < bytes.count else { throw fail("unexpected end") }
                    let escape = bytes[index]
                    index += 1
                    switch escape {
                    case UInt8(ascii: "\""): scalars.append("\"")
                    case UInt8(ascii: "\\"): scalars.append("\\")
                    case UInt8(ascii: "/"): scalars.append("/")
                    case UInt8(ascii: "b"): scalars.append("\u{08}")
                    case UInt8(ascii: "f"): scalars.append("\u{0C}")
                    case UInt8(ascii: "n"): scalars.append("\n")
                    case UInt8(ascii: "r"): scalars.append("\r")
                    case UInt8(ascii: "t"): scalars.append("\t")
                    case UInt8(ascii: "u"):
                        var code = try hex4()
                        if (0xD800...0xDBFF).contains(code) {
                            guard index + 1 < bytes.count, bytes[index] == UInt8(ascii: "\\"), bytes[index + 1] == UInt8(ascii: "u") else {
                                throw fail("lone surrogate")
                            }
                            index += 2
                            let low = try hex4()
                            guard (0xDC00...0xDFFF).contains(low) else { throw fail("lone surrogate") }
                            code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
                        }
                        guard let scalar = Unicode.Scalar(code) else { throw fail("invalid escape") }
                        scalars.append(scalar)
                    default: throw fail("invalid escape")
                    }
                case 0x00..<0x20:
                    throw fail("control character in a string")
                default:
                    raw.append(byte)
                    index += 1
                }
            }
            throw fail("unterminated string")
        }

        private mutating func hex4() throws -> UInt32 {
            guard index + 4 <= bytes.count, let text = String(bytes: bytes[index..<(index + 4)], encoding: .ascii),
                  let value = UInt32(text, radix: 16) else { throw fail("invalid \\u escape") }
            index += 4
            return value
        }

        private mutating func parseNumber() throws {
            func digits() -> Int {
                let start = index
                while index < bytes.count, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(bytes[index]) { index += 1 }
                return index - start
            }
            if bytes[index] == UInt8(ascii: "-") { index += 1 }
            guard index < bytes.count else { throw fail("invalid number") }
            if bytes[index] == UInt8(ascii: "0") {
                index += 1
            } else if digits() == 0 {
                throw fail("invalid number")
            }
            if index < bytes.count, bytes[index] == UInt8(ascii: ".") {
                index += 1
                guard digits() > 0 else { throw fail("invalid number") }
            }
            if index < bytes.count, bytes[index] == UInt8(ascii: "e") || bytes[index] == UInt8(ascii: "E") {
                index += 1
                if index < bytes.count, bytes[index] == UInt8(ascii: "+") || bytes[index] == UInt8(ascii: "-") { index += 1 }
                guard digits() > 0 else { throw fail("invalid number") }
            }
        }
    }
}

/// A JSON value Wallflower writes, with its keys in the order given.
indirect enum JSONLiteral: Equatable, Sendable {
    case object([(String, JSONLiteral)])
    case array([JSONLiteral])
    case string(String)
    case int(Int)
    case bool(Bool)

    static func == (lhs: JSONLiteral, rhs: JSONLiteral) -> Bool {
        lhs.render(indent: "", unit: "", compact: true) == rhs.render(indent: "", unit: "", compact: true)
    }

    /// The value as text. Pretty: one member or element per line, `indent` being the indentation of
    /// the line the value starts on. Compact: one line, `{"a": 1, "b": [2]}`.
    func render(indent: String, unit: String, compact: Bool) -> String {
        switch self {
        case .string(let text):
            let data = (try? JSONSerialization.data(withJSONObject: [text], options: [.withoutEscapingSlashes])) ?? Data("[\"\"]".utf8)
            return String(decoding: data.dropFirst().dropLast(), as: UTF8.self)
        case .int(let value): return "\(value)"
        case .bool(let value): return value ? "true" : "false"
        case .array(let elements):
            if elements.isEmpty { return "[]" }
            if compact { return "[" + elements.map { $0.render(indent: "", unit: "", compact: true) }.joined(separator: ", ") + "]" }
            let inner = indent + unit
            return "[\n" + elements.map { inner + $0.render(indent: inner, unit: unit, compact: false) }.joined(separator: ",\n") + "\n" + indent + "]"
        case .object(let members):
            if members.isEmpty { return "{}" }
            if compact {
                return "{" + members.map { JSONLiteral.string($0.0).render(indent: "", unit: "", compact: true) + ": " + $0.1.render(indent: "", unit: "", compact: true) }
                    .joined(separator: ", ") + "}"
            }
            let inner = indent + unit
            return "{\n" + members.map { inner + JSONLiteral.string($0.0).render(indent: "", unit: "", compact: true) + ": " + $0.1.render(indent: inner, unit: unit, compact: false) }
                .joined(separator: ",\n") + "\n" + indent + "}"
        }
    }
}
