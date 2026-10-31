// OpenUIKitDeviceModel: the one place a host picks the device it renders as.
//
// A device fixes the screen (points and scale) and the window safe area a
// portrait app sees with the status bar shown. `OpenUIKitRuntime
// .configureDevice(_:)` applies all three; nothing reads a device until a
// host configures one, so existing hosts and gates keep their screen and
// their zero window safe area.
//
// Safe areas are Apple's published portrait values (status-bar/sensor
// housing top, home-indicator bottom). The iPhone 16e row is MEASURED:
// iOS 27 simulator, `stupidsim ui-tree` puts the root navigation bar of a
// SwiftUI NavigationStack at y 47 in a 390 x 844 window, and the home
// indicator inset is 34.

public struct OpenUIKitDeviceModel: Equatable, Sendable {
    /// Lower-case identifier hosts select by (`iphone16e`).
    public let identifier: String
    /// Screen size in points, portrait.
    public let screenSize: CGSize
    /// Backing scale (points to pixels).
    public let scale: CGFloat
    /// Portrait window safe area with the status bar shown.
    public let safeAreaInsets: UIEdgeInsets
    /// Status bar layout family: a notch device keeps the time and the
    /// indicators in the two "ears" beside the sensor housing.
    public let statusBarStyle: StatusBarStyle

    public enum StatusBarStyle: Equatable, Sendable {
        /// Notch (iPhone X-class through 16e): 47 pt status bar.
        case notch
        /// Dynamic Island (iPhone 14 Pro and later Pro/16 models).
        case dynamicIsland
        /// Home-button devices: 20 pt status bar.
        case legacy
    }

    public init(identifier: String, screenSize: CGSize, scale: CGFloat,
                safeAreaInsets: UIEdgeInsets, statusBarStyle: StatusBarStyle) {
        self.identifier = identifier
        self.screenSize = screenSize
        self.scale = scale
        self.safeAreaInsets = safeAreaInsets
        self.statusBarStyle = statusBarStyle
    }

    /// iPhone 16e (and the iPhone 12/13/14 point size): 390 x 844 @3x.
    public static let iPhone16e = OpenUIKitDeviceModel(
        identifier: "iphone16e", screenSize: CGSize(width: 390, height: 844), scale: 3,
        safeAreaInsets: UIEdgeInsets(top: 47, left: 0, bottom: 34, right: 0),
        statusBarStyle: .notch)
    /// iPhone 16 / 15 / 15 Pro: 393 x 852 @3x (the headless host's default
    /// screen, `OPENUIKIT_SAFE_AREA` default 59,0,34,0).
    public static let iPhone16 = OpenUIKitDeviceModel(
        identifier: "iphone16", screenSize: CGSize(width: 393, height: 852), scale: 3,
        safeAreaInsets: UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0),
        statusBarStyle: .dynamicIsland)
    /// iPhone 16 Pro: 402 x 874 @3x.
    public static let iPhone16Pro = OpenUIKitDeviceModel(
        identifier: "iphone16pro", screenSize: CGSize(width: 402, height: 874), scale: 3,
        safeAreaInsets: UIEdgeInsets(top: 62, left: 0, bottom: 34, right: 0),
        statusBarStyle: .dynamicIsland)
    /// iPhone 16 Pro Max: 440 x 956 @3x.
    public static let iPhone16ProMax = OpenUIKitDeviceModel(
        identifier: "iphone16promax", screenSize: CGSize(width: 440, height: 956), scale: 3,
        safeAreaInsets: UIEdgeInsets(top: 62, left: 0, bottom: 34, right: 0),
        statusBarStyle: .dynamicIsland)
    /// iPhone SE (3rd generation): 375 x 667 @2x.
    public static let iPhoneSE3 = OpenUIKitDeviceModel(
        identifier: "iphonese3", screenSize: CGSize(width: 375, height: 667), scale: 2,
        safeAreaInsets: UIEdgeInsets(top: 20, left: 0, bottom: 0, right: 0),
        statusBarStyle: .legacy)

    public static let all: [OpenUIKitDeviceModel] = [
        .iPhone16e, .iPhone16, .iPhone16Pro, .iPhone16ProMax, .iPhoneSE3,
    ]

    /// The model with this identifier (case-insensitive), or nil.
    public static func named(_ identifier: String) -> OpenUIKitDeviceModel? {
        let key = identifier.lowercased()
        return all.first { $0.identifier == key }
    }
}

extension OpenUIKitRuntime {
    /// The device a host configured with `configureDevice(_:)`, or nil.
    @MainActor public internal(set) static var device: OpenUIKitDeviceModel?

    /// Render as `device`: `UIScreen.main` takes its size and scale,
    /// `UIImage(named:)` prefers its scale, and every window created for a
    /// scene (`UIWindow(windowScene:)`: the SwiftUI `App` path and the
    /// scene-manifest path) reports its safe area. Call before the app
    /// creates its windows.
    @MainActor public static func configureDevice(_ device: OpenUIKitDeviceModel) {
        self.device = device
        imageScreenScale = device.scale
        UIScreen.main._hostConfigure(bounds: CGRect(origin: .zero, size: device.screenSize),
                                     scale: device.scale)
    }
}
