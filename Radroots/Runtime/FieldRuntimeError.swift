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
        case .Sdk(let report):
            if report.capabilityId?.hasPrefix("signing.") == true {
                .identity
            } else if report.capabilityId?.hasPrefix("transport.") == true {
                .relay
            } else {
                .runtime
            }
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
             .Runtime(let message),
             .Unsupported(let message),
             .Internal(let message):
            message
        case .Sdk(let report):
            report.message
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
