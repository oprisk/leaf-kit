// MARK: Subject to change prior to 1.0.0 release
// MARK: -

import Foundation

/// `LeafConfiguration` provides global storage of properites that must be consistent across
/// `LeafKit` while running. Alter the global configuration of LeafKit by setting the static properties
/// of the structure prior to calling `LeafRenderer.render()`; any changes subsequently will be ignored.
public struct LeafConfiguration {
    // MARK: - Global-Only Options
    /// The character used to signal tag processing
    @LeafRuntimeGuard public static var tagIndicator: Character = .octothorpe
        
    /// Entities (functions, blocks, raw blocks, types) the LeafKit engine recognizes
    @LeafRuntimeGuard public static var entities: LeafEntities = .leaf4Core
        
    // MARK: - State
    
    /// Convenience to check state of LeafKit
    public static var isRunning: Bool { started }

    // MARK: - Internal Only
    
    /// Convenience for getting running state of LeafKit that will assert with a fault message for soft-failing things
    static func running(fault message: String) -> Bool {
        assert(!started, "\(message) after LeafRenderer has instantiated")
        return started
    }
    
    /// Flag for global write lock after LeafKit has started
    static var started = false
}

/// `LeafRuntimeGuard` secures a value against being changed once a `LeafRenderer` is active
///
/// Attempts to change the value secured by the runtime guard will assert in debug to warn against
/// programmatic changes to a value that needs to be consistent across the running state of LeafKit.
/// Such attempts to change will silently fail in production builds.
@propertyWrapper public struct LeafRuntimeGuard<T> {
    public var wrappedValue: T {
        get { _unsafeValue }
        set { if !LKConf.running(fault: "Cannot configure \(object)") {
                    assert(condition(newValue), "\(object) failed conditional check")
                    _unsafeValue = newValue } }
    }
    
    public var projectedValue: Self { self }
    
    
    /// `condition` may be used to provide an asserting validation closure that will assert if false
    /// when setting; *WILL FATAL IF FAILING AT INITIAL SETTING TIME*
    public init(wrappedValue: T,
                module: String = #file,
                component: String = #function,
                condition: @escaping (T) -> Bool = {_ in true}) {
        precondition(condition(wrappedValue), "\(wrappedValue) failed conditional check")
        let module = String(module.split(separator: "/").last?.split(separator: ".").first ?? "")
        self.object = module.isEmpty ? component : "\(module).\(component)"
        self.condition = condition
        self._unsafeValue = wrappedValue
    }
    
    /// T/F evaluation of condition, and if T is Hashable, nil if the values are the same
    internal func validate(_ other: T) -> Bool? {
        if let a = other as? AnyHashable,
           let b = _unsafeValue as? AnyHashable,
           a == b { return nil }
        return condition(other)
    }
    
    internal var _unsafeValue: T
    internal let condition: (T) -> Bool
    private let object: String
}
