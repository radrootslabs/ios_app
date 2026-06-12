import Foundation

enum AuthSettingsError: LocalizedError {
    case missingAuthApiBaseURL

    var errorDescription: String? {
        switch self {
        case .missingAuthApiBaseURL:
            "No auth API base URL configured. Set 'RADROOTS_FIELD_IOS_AUTH_API_BASE_URL'."
        }
    }
}

enum AuthSettings {
    static func authApiBaseURL() throws -> String {
        guard let value = BuildConfig.string(.authApiBaseUrl) else {
            throw AuthSettingsError.missingAuthApiBaseURL
        }
        return value
    }

    static func accountsApiBaseURL() -> String? {
        BuildConfig.string(.accountsApiBaseUrl)
    }
}
