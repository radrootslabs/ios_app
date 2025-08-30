import Foundation

extension Bundle {
  var buildSHA: String? { object(forInfoDictionaryKey: "GIT_SHA") as? String }
  var version: String? { object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String }
  var buildNumber: String? { object(forInfoDictionaryKey: "CFBundleVersion") as? String }
}
