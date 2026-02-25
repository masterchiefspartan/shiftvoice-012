import Foundation

nonisolated enum InputValidator: Sendable {

    nonisolated struct ValidationResult: Sendable {
        let isValid: Bool
        let errors: [String: String]

        static let valid = ValidationResult(isValid: true, errors: [:])

        static func invalid(_ errors: [String: String]) -> ValidationResult {
            ValidationResult(isValid: false, errors: errors)
        }
    }

    static func validateEmail(_ email: String) -> String? {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "Email is required" }
        let regex = /^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$/
        if trimmed.wholeMatch(of: regex) == nil { return "Enter a valid email address" }
        return nil
    }

    static func validatePassword(_ password: String) -> String? {
        if password.isEmpty { return "Password is required" }
        if password.count < 8 { return "Must be at least 8 characters" }
        if !password.contains(where: \.isLetter) { return "Must contain at least one letter" }
        if !password.contains(where: \.isNumber) { return "Must contain at least one number" }
        return nil
    }

    static func validateName(_ name: String, fieldName: String = "Name") -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "\(fieldName) is required" }
        if trimmed.count < 2 { return "Must be at least 2 characters" }
        if trimmed.count > 100 { return "Must be under 100 characters" }
        return nil
    }

    static func validateNonEmpty(_ value: String, fieldName: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "\(fieldName) is required" }
        return nil
    }

    static func validateLocationName(_ name: String, terminology: String = "location") -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Give your \(terminology) a name to continue" }
        if trimmed.count < 2 { return "Name must be at least 2 characters" }
        if trimmed.count > 100 { return "Name must be under 100 characters" }
        return nil
    }

    static func validateShiftNote(
        summary: String,
        rawTranscript: String,
        locationId: String,
        authorId: String
    ) -> ValidationResult {
        var errors: [String: String] = [:]

        if summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
           rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors["summary"] = "Add a summary or ensure the transcript is not empty"
        }

        if locationId.isEmpty {
            errors["location"] = "No location selected"
        }

        if authorId.isEmpty {
            errors["author"] = "Not signed in"
        }

        if errors.isEmpty { return .valid }
        return .invalid(errors)
    }

    static func validateActionItemTask(_ task: String) -> String? {
        let trimmed = task.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Task description is required" }
        if trimmed.count > 500 { return "Task must be under 500 characters" }
        return nil
    }

    static func sanitizeString(_ input: String, maxLength: Int = 10000) -> String {
        String(input.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxLength))
    }
}
