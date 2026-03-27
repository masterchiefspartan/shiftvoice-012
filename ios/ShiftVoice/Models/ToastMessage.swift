import Foundation

struct ToastMessage: Equatable {
    let id: String
    let text: String
    let isError: Bool
    let timestamp: Date

    init(text: String, isError: Bool = false) {
        self.id = UUID().uuidString
        self.text = text
        self.isError = isError
        self.timestamp = Date()
    }

    static func == (lhs: ToastMessage, rhs: ToastMessage) -> Bool {
        lhs.id == rhs.id
    }
}
