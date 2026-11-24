import Foundation
import Observation
import TallyCore
#if canImport(LocalAuthentication)
import LocalAuthentication
#endif

// MARK: - Authenticator

/// What the device can use to prove the owner is present.
public enum DeviceAuthKind: Equatable, Sendable {
    case faceID
    case touchID
    case opticID
    /// No biometry enrolled, but a device passcode / password is set.
    case passcode
    /// Neither biometry nor a passcode: nothing can authenticate.
    case none

    /// Whether `authenticate` can succeed at all.
    public var isAvailable: Bool { self != .none }

    /// Setting row title, e.g. "Require Face ID to show salary".
    public func requirementTitle(in language: AppLanguage) -> String {
        switch self {
        case .faceID:
            return L10n.text(language, en: "Require Face ID to show salary", vi: "Yêu cầu Face ID để hiện lương", zh: "显示工资需要 Face ID")
        case .touchID:
            return L10n.text(language, en: "Require Touch ID to show salary", vi: "Yêu cầu Touch ID để hiện lương", zh: "显示工资需要 Touch ID")
        case .opticID:
            return L10n.text(language, en: "Require Optic ID to show salary", vi: "Yêu cầu Optic ID để hiện lương", zh: "显示工资需要 Optic ID")
        case .passcode, .none:
            return L10n.text(language, en: "Require passcode to show salary", vi: "Yêu cầu mật mã để hiện lương", zh: "显示工资需要密码")
        }
    }
}

/// Wraps the system's owner authentication so the gate can be tested with a fake.
public protocol SalaryAuthenticating: Sendable {
    /// What the device can authenticate with right now (re-evaluated on every call).
    func availableKind() -> DeviceAuthKind
    /// Presents the system prompt. `true` only when the owner authenticated; cancellation and any
    /// failure return `false`.
    func authenticate(reason: String) async -> Bool
}

#if canImport(LocalAuthentication)
/// `LAContext` with `.deviceOwnerAuthentication`: biometry with the device passcode / password as
/// fallback.
public struct SystemSalaryAuthenticator: SalaryAuthenticating {
    public init() {}

    public func availableKind() -> DeviceAuthKind {
        let context = LAContext()
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            switch context.biometryType {
            case .faceID: return .faceID
            case .touchID: return .touchID
            case .opticID: return .opticID
            default: break
            }
        }
        var passcodeError: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &passcodeError) ? .passcode : .none
    }

    public func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            return false
        }
    }
}
#endif

/// Localized reasons shown in the system authentication prompt.
public enum SalaryAuthPrompt {
    public static func reveal(in language: AppLanguage) -> String {
        L10n.text(language, en: "Show your salary in Tally", vi: "Hiện lương trong Tally", zh: "在 Tally 中显示工资")
    }

    public static func turnOffRequirement(in language: AppLanguage) -> String {
        L10n.text(
            language,
            en: "Turn off authentication for showing salary in Tally",
            vi: "Tắt xác thực khi hiện lương trong Tally",
            zh: "关闭在 Tally 中显示工资时的身份验证"
        )
    }
}

extension SalaryVisibilityGate.Notice {
    /// Inline explanation shown under the Settings row.
    public func message(in language: AppLanguage) -> String {
        switch self {
        case .passcodeRequired:
            return L10n.text(
                language,
                en: "Set a device passcode (or password) first, then turn this on.",
                vi: "Hãy đặt mật mã (hoặc mật khẩu) cho thiết bị trước, rồi bật mục này.",
                zh: "请先为设备设置密码，然后再开启此项。"
            )
        }
    }
}

// MARK: - Gate

/// Owns whether salary is currently hidden, and (optionally) makes revealing it require owner
/// authentication.
///
/// - Hiding never asks.
/// - With `requiresAuthentication` on: salary starts hidden on every cold launch and is hidden
///   again whenever the app goes to the background; revealing it, and turning the requirement
///   itself off, both need authentication. A failed or cancelled authentication leaves the state
///   unchanged.
/// - With it off: behaves like a plain persisted toggle (the last state is restored on launch).
///
/// `isHidden` is the one "effective" state every screen and the assistant read.
@MainActor
@Observable
public final class SalaryVisibilityGate {
    public enum Notice: Equatable, Sendable {
        /// The device has neither biometry nor a passcode, so the requirement cannot be used.
        case passcodeRequired
    }

    public private(set) var isHidden: Bool
    public private(set) var requiresAuthentication: Bool
    /// `true` while a system prompt is up (a second request is ignored meanwhile).
    public private(set) var isAuthenticating = false
    /// Inline explanation for the Settings pane; cleared by the next successful action.
    public private(set) var notice: Notice?
    /// What the device can authenticate with; refreshed by `refreshAvailability()`.
    public private(set) var authKind: DeviceAuthKind

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let authenticator: SalaryAuthenticating
    /// Bumped on every lock so an authentication that finishes after the app was re-locked cannot
    /// reveal salary.
    @ObservationIgnored private var lockEpoch = 0

    /// Storage keys. `hiddenKey` is the long-standing "hide income" key, kept so the user's
    /// current choice carries over.
    nonisolated static let hiddenKey = "tally.hideIncome"
    nonisolated static let requireKey = "tally.salary.requireAuth"

    public init(defaults: UserDefaults = .standard, authenticator: SalaryAuthenticating) {
        self.defaults = defaults
        self.authenticator = authenticator
        let requires = defaults.object(forKey: Self.requireKey) as? Bool ?? false
        self.requiresAuthentication = requires
        self.authKind = authenticator.availableKind()
        if requires {
            // Cold launch with the requirement on: always start hidden, whatever the last state.
            self.isHidden = true
            defaults.set(true, forKey: Self.hiddenKey)
        } else {
            self.isHidden = defaults.object(forKey: Self.hiddenKey) as? Bool ?? false
        }
    }

    #if canImport(LocalAuthentication)
    public convenience init(defaults: UserDefaults = .standard) {
        self.init(defaults: defaults, authenticator: SystemSalaryAuthenticator())
    }
    #endif

    public func refreshAvailability() {
        authKind = authenticator.availableKind()
    }

    // MARK: Hide / reveal

    /// Hides salary. Never asks for authentication.
    public func hide() {
        lockEpoch += 1
        notice = nil
        setHidden(true)
    }

    /// Shows salary, authenticating first when the requirement is on. Returns `true` when salary
    /// is visible afterwards.
    ///
    /// `alwaysAuthenticate` is for reveals the user did not start with the eye control (the
    /// assistant asking in chat): it authenticates even when the requirement is off. A device with
    /// nothing to authenticate with then reveals without a prompt, as there is nothing to check.
    @discardableResult
    public func reveal(reason: String, alwaysAuthenticate: Bool = false) async -> Bool {
        guard isHidden else { return true }
        guard requiresAuthentication || alwaysAuthenticate else {
            setHidden(false)
            return true
        }
        guard !isAuthenticating else { return false }
        refreshAvailability()
        guard authKind.isAvailable else {
            guard requiresAuthentication else {
                setHidden(false)
                return true
            }
            notice = .passcodeRequired
            return false
        }
        let epoch = lockEpoch
        isAuthenticating = true
        let success = await authenticator.authenticate(reason: reason)
        isAuthenticating = false
        guard success, epoch == lockEpoch else { return false }
        notice = nil
        setHidden(false)
        return true
    }

    /// The eye control: hides when visible, reveals (with authentication if required) when hidden.
    public func toggle(reason: String) async {
        if isHidden {
            await reveal(reason: reason)
        } else {
            hide()
        }
    }

    // MARK: The requirement itself

    /// Turns the authentication requirement on or off. Returns `true` when the requirement now
    /// equals `enabled`.
    ///
    /// - On needs a passcode or biometry on the device (otherwise `notice` explains and nothing
    ///   changes). It does not prompt, and does not hide salary that is already showing.
    /// - Off requires authentication, so someone holding the unlocked phone cannot just switch it
    ///   off. On a device that has nothing to authenticate with there is nothing to protect with,
    ///   so it is switched off without a prompt rather than leaving salary locked for good.
    @discardableResult
    public func setRequiresAuthentication(_ enabled: Bool, reason: String) async -> Bool {
        guard enabled != requiresAuthentication else { return true }
        refreshAvailability()
        if enabled {
            guard authKind.isAvailable else {
                notice = .passcodeRequired
                return false
            }
            notice = nil
            applyRequirement(true)
            return true
        }
        if authKind.isAvailable {
            guard !isAuthenticating else { return false }
            isAuthenticating = true
            let success = await authenticator.authenticate(reason: reason)
            isAuthenticating = false
            guard success else { return false }
        }
        notice = nil
        applyRequirement(false)
        return true
    }

    // MARK: Scene lifecycle

    /// Call when the scene phase becomes `.background` (not `.inactive`, which the Face ID sheet
    /// and Control Centre also cause). Re-locks when the requirement is on.
    public func appDidEnterBackground() {
        guard requiresAuthentication else { return }
        hide()
    }

    // MARK: Private

    private func setHidden(_ hidden: Bool) {
        isHidden = hidden
        defaults.set(hidden, forKey: Self.hiddenKey)
    }

    private func applyRequirement(_ enabled: Bool) {
        requiresAuthentication = enabled
        defaults.set(enabled, forKey: Self.requireKey)
    }
}
