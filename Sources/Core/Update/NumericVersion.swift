import Foundation

public struct NumericVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    private let components: [UInt]

    public init(_ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawComponents = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard !rawComponents.isEmpty else { throw NumericVersionError.invalid }

        var parsed: [UInt] = []
        parsed.reserveCapacity(rawComponents.count)
        for raw in rawComponents {
            guard !raw.isEmpty,
                  raw.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
                  let component = UInt(raw) else {
                throw NumericVersionError.invalid
            }
            parsed.append(component)
        }
        while parsed.count > 1, parsed.last == 0 {
            parsed.removeLast()
        }
        components = parsed
    }

    public var description: String {
        components.map(String.init).joined(separator: ".")
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }
}

private enum NumericVersionError: Error {
    case invalid
}
