// LocalAuthentication for headless guests: no biometric sensor and no device passcode, as on an
// iOS Simulator with neither enrolled. Nothing can be evaluated, and every answer says why, with
// LocalAuthentication's own error codes; evaluation never invents success.
//
// Focus AuthenticationManager (a2832521 Blockzilla/Utilities/AuthenticationManager.swift:15):
// headless launch must not prompt. canEvaluatePolicy is false and biometry is .none. MEASURED so
// AppDelegate's authenticateWithBiometrics path sets .loggedin via the
// `guard userEnabledBiometrics, canEvaluatePolicy` early return when Settings.biometricLogin is the
// default false.
//
// stupid wallet (LocalAuth.swift, KeychainKeyStore.swift): the callback form of evaluatePolicy,
// LAError codes read back through NSError, invalidate(), interactionNotAllowed and
// touchIDAuthenticationAllowableReuseDuration.

import Foundation
@_exported import Combine
@_exported import UIKit

public let LAErrorDomain = "com.apple.LocalAuthentication"

/// The longest reuse window `touchIDAuthenticationAllowableReuseDuration` honours (5 minutes).
public let LATouchIDAuthenticationMaximumAllowableReuseDuration: TimeInterval = 300

public enum LABiometryType: Int, Sendable {
    case none = 0
    case touchID = 1
    case faceID = 2
    case opticID = 4
}

public enum LAPolicy: Int, Sendable {
    case deviceOwnerAuthenticationWithBiometrics = 1
    case deviceOwnerAuthentication = 2
}

/// LocalAuthentication's error: `LAError.userCancel` and friends are its codes, with the iOS raw
/// values, and an `LAError` bridges to an NSError in `LAErrorDomain` with that code.
public struct LAError: CustomNSError, Hashable, Sendable {
    public enum Code: Int, Sendable {
        case authenticationFailed = -1
        case userCancel = -2
        case userFallback = -3
        case systemCancel = -4
        case passcodeNotSet = -5
        case biometryNotAvailable = -6
        case biometryNotEnrolled = -7
        case biometryLockout = -8
        case appCancel = -9
        case invalidContext = -10
        case companionNotAvailable = -11
        case notInteractive = -1004

        public static var touchIDNotAvailable: Code { .biometryNotAvailable }
        public static var touchIDNotEnrolled: Code { .biometryNotEnrolled }
        public static var touchIDLockout: Code { .biometryLockout }
    }

    public let code: Code

    public init(_ code: Code) {
        self.code = code
    }

    public static var errorDomain: String { LAErrorDomain }
    public var errorCode: Int { code.rawValue }

    public static var authenticationFailed: Code { .authenticationFailed }
    public static var userCancel: Code { .userCancel }
    public static var userFallback: Code { .userFallback }
    public static var systemCancel: Code { .systemCancel }
    public static var passcodeNotSet: Code { .passcodeNotSet }
    public static var biometryNotAvailable: Code { .biometryNotAvailable }
    public static var biometryNotEnrolled: Code { .biometryNotEnrolled }
    public static var biometryLockout: Code { .biometryLockout }
    public static var touchIDNotAvailable: Code { .biometryNotAvailable }
    public static var touchIDNotEnrolled: Code { .biometryNotEnrolled }
    public static var touchIDLockout: Code { .biometryLockout }
    public static var appCancel: Code { .appCancel }
    public static var invalidContext: Code { .invalidContext }
    public static var companionNotAvailable: Code { .companionNotAvailable }
    public static var notInteractive: Code { .notInteractive }
}

public final class LAContext {
    public var biometryType: LABiometryType { .none }
    public var localizedReason: String = ""
    public var localizedCancelTitle: String?
    public var localizedFallbackTitle: String?
    /// Stored as set (iOS does not clamp on assignment); nothing is ever reused here.
    public var touchIDAuthenticationAllowableReuseDuration: TimeInterval = 0
    public var interactionNotAllowed = false
    private var invalidated = false

    public init() {}

    /// Why `policy` cannot be evaluated: no passcode for device-owner authentication, no
    /// biometry for the biometric policy, or this context was invalidated.
    private func unavailability(_ policy: LAPolicy) -> LAError {
        if invalidated { return LAError(.invalidContext) }
        switch policy {
        case .deviceOwnerAuthentication: return LAError(.passcodeNotSet)
        case .deviceOwnerAuthenticationWithBiometrics: return LAError(.biometryNotAvailable)
        }
    }

    public func canEvaluatePolicy(_ policy: LAPolicy, error: UnsafeMutablePointer<NSError?>?) -> Bool {
        error?.pointee = NSError(domain: LAErrorDomain, code: unavailability(policy).code.rawValue)
        return false
    }

    public func evaluatePolicy(
        _ policy: LAPolicy,
        localizedReason: String
    ) async throws -> Bool {
        _ = localizedReason
        throw unavailability(policy)
    }

    /// The reply runs on a private queue, as LocalAuthentication delivers it.
    public func evaluatePolicy(
        _ policy: LAPolicy,
        localizedReason: String,
        reply: @escaping @Sendable (Bool, (any Error)?) -> Void
    ) {
        _ = localizedReason
        let error = unavailability(policy)
        DispatchQueue.global().async { reply(false, error) }
    }

    public func invalidate() {
        invalidated = true
    }
}
