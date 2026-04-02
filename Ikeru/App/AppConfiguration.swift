import Foundation

/// App-wide configuration constants.
/// Values that may change per environment go in .xcconfig files.
enum AppConfiguration {
    static let appGroupIdentifier = "group.com.ikeru.shared"
    static let bundleIdentifier = "com.ikeru.app"
    static let watchBundleIdentifier = "com.ikeru.app.watch"
    static let widgetBundleIdentifier = "com.ikeru.app.widget"
}
