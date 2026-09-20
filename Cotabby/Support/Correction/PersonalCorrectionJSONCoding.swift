import Foundation

/// Shared codec for the user-owned correction database. New files encode the exact floating-point
/// bit pattern backing each `Date`; the decoder also accepts Unix numbers and the ISO-8601 strings
/// written by early builds of this feature so an upgrade never strands an existing dictionary.
nonisolated enum PersonalCorrectionJSONCoding {
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            let bits = date.timeIntervalSinceReferenceDate.bitPattern
            try container.encode("reference-bits:\(bits)")
        }
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let seconds = try? container.decode(Double.self) {
                return Date(timeIntervalSince1970: seconds)
            }
            if let value = try? container.decode(String.self) {
                if value.hasPrefix("reference-bits:"),
                   let bits = UInt64(value.dropFirst("reference-bits:".count)) {
                    return Date(timeIntervalSinceReferenceDate: Double(bitPattern: bits))
                }
                if value.hasPrefix("unix-bits:"),
                   let bits = UInt64(value.dropFirst("unix-bits:".count)) {
                    return Date(timeIntervalSince1970: Double(bitPattern: bits))
                }
                let fractional = ISO8601DateFormatter()
                fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = fractional.date(from: value) { return date }

                let legacy = ISO8601DateFormatter()
                legacy.formatOptions = [.withInternetDateTime]
                if let date = legacy.date(from: value) { return date }
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected a Unix timestamp or ISO-8601 date."
            )
        }
        return decoder
    }
}
