import Foundation

enum FieldRuntimeErrorCategory: String, Sendable {
    case initialization
    case identity
    case secureStore
    case relay
    case runtime
    case unsupported
    case internalFailure
}

extension RadrootsAppError {
    var fieldCategory: FieldRuntimeErrorCategory {
        switch self {
        case .Initialization(_):
            .initialization
        case .Identity(_):
            .identity
        case .SecureStore(_):
            .secureStore
        case .Relay(_):
            .relay
        case .Runtime(_):
            .runtime
        case .Unsupported(_):
            .unsupported
        case .Internal(_):
            .internalFailure
        }
    }

    var fieldMessage: String {
        switch self {
        case .Initialization(let message),
             .Identity(let message),
             .SecureStore(let message),
             .Relay(let message),
             .Runtime(let message),
             .Unsupported(let message),
             .Internal(let message):
            message
        }
    }
}

extension Error {
    var fieldRuntimeErrorCategory: FieldRuntimeErrorCategory? {
        (self as? RadrootsAppError)?.fieldCategory
    }

    var fieldRuntimeMessage: String {
        if let fieldError = self as? RadrootsAppError {
            return fieldError.fieldMessage
        }
        return localizedDescription
    }
}
