import Foundation

enum AppVersion {
    /// The release name, such as "1.0.0-rc.1"; falls back to the marketing
    /// version, or "dev" when running outside an app bundle.
    static var releaseName: String {
        let info = Bundle.main.infoDictionary
        return info?["ClavimoReleaseName"] as? String
            ?? info?["CFBundleShortVersionString"] as? String
            ?? "dev"
    }
}
