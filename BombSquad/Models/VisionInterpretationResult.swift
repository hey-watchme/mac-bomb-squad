import Foundation

struct VisionInterpretationResult: Codable, Hashable {
    var modelID: String?
    let summary: String
    let visibleText: [String]
    let interpretation: String
    let suggestedActions: [String]
    let uncertainties: [String]

    enum CodingKeys: String, CodingKey {
        case modelID = "model_id"
        case summary
        case visibleText = "visible_text"
        case interpretation
        case suggestedActions = "suggested_actions"
        case uncertainties
    }

    var copyText: String {
        var parts: [String] = []
        parts.append("要約:\n\(summary)")
        if !visibleText.isEmpty {
            parts.append("読める文字:\n" + visibleText.map { "- \($0)" }.joined(separator: "\n"))
        }
        if !interpretation.isEmpty {
            parts.append("説明:\n\(interpretation)")
        }
        if !suggestedActions.isEmpty {
            parts.append("次にできること:\n" + suggestedActions.map { "- \($0)" }.joined(separator: "\n"))
        }
        if !uncertainties.isEmpty {
            parts.append("不確かな点:\n" + uncertainties.map { "- \($0)" }.joined(separator: "\n"))
        }
        return parts.joined(separator: "\n\n")
    }

    static func decodeFlexible(from data: Data) throws -> VisionInterpretationResult {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.decoding("vision result is not a JSON object")
        }

        return VisionInterpretationResult(
            modelID: stringValue(object, keys: ["model_id", "modelID"]),
            summary: stringValue(object, keys: ["summary", "要約"]) ?? "",
            visibleText: stringListValue(object, keys: ["visible_text", "visibleText", "text", "ocr_text"]),
            interpretation: stringValue(object, keys: ["interpretation", "explanation", "説明"]) ?? "",
            suggestedActions: stringListValue(object, keys: ["suggested_actions", "suggestedActions", "actions", "next_actions"]),
            uncertainties: stringListValue(object, keys: ["uncertainties", "uncertainty", "不確かな点"])
        )
    }

    private static func stringValue(_ object: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = object[key] as? String {
                return value.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let value = object[key] {
                return describe(value)
            }
        }
        return nil
    }

    private static func stringListValue(_ object: [String: Any], keys: [String]) -> [String] {
        for key in keys {
            guard let value = object[key] else { continue }
            if let array = value as? [String] {
                return array.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            }
            if let array = value as? [Any] {
                return array.compactMap { describe($0) }.filter { !$0.isEmpty }
            }
            if let string = value as? String {
                return splitLines(string)
            }
            if let described = describe(value), !described.isEmpty {
                return [described]
            }
        }
        return []
    }

    private static func splitLines(_ string: String) -> [String] {
        string
            .components(separatedBy: .newlines)
            .map {
                $0.trimmingCharacters(in: CharacterSet(charactersIn: " \t-•"))
            }
            .filter { !$0.isEmpty }
    }

    private static func describe(_ value: Any) -> String? {
        if let string = value as? String {
            return string.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return nil
    }
}
