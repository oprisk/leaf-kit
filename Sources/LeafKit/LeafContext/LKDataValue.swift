/// Wrapper for what is essentially deferred evaluation of `LDR` values to `LeafData` as an intermediate
/// structure to allow general assembly of a contextual database that can be used/reused by `LeafRenderer`
/// in various render calls. Values are either `variable` and can be updated/refreshed to their `LeafData`
/// value, or `literal` and are considered globally fixed; ie, once literal, they can/should not be converted
/// back to `variable` as resolved ASTs will have used the pre-existing literal value.
internal struct LKDataValue: LeafDataRepresentable {
    static func variable(_ value: LeafDataRepresentable) -> Self { .init(value) }
    static func literal(_ value: LeafDataRepresentable) -> Self { .init(value, true) }
    
    init(_ value: LeafDataRepresentable, _ literal: Bool = false) {
        container = literal ? .literal(value.leafData) : .variable(value, .none) }
    
    var isVariable: Bool { container.isVariable }
    var leafData: LeafData { container.leafData }
        
    var cached: Bool {
        if case .variable(_, .none) = container { return false }
        if case .literal(let d) = container, d.isLazy { return false }
        return true
    }
    
    /// Coalesce to a literal
    mutating func flatten() {
        let flat: LKDContainer
        switch container {
            case .variable(let v, let d): flat = d?.container ?? v.leafData.container
            case .literal(let d): flat = d.container
        }
        container = .literal(flat.evaluate)
    }
    
    /// Update stored `LeafData` value for variable values
    mutating func refresh() {
        if case .variable(let t, _) = container { container = .variable(t, t.leafData) } }
        
    /// Uncache stored `LeafData` value for variable values
    mutating func uncache() {
        if case .variable(let t, .some) = container { container = .variable(t, .none) } }
    
    // MARK: - Private Only
    
    private enum Container: LeafDataRepresentable {
        case literal(LeafData)
        case variable(LeafDataRepresentable, Optional<LeafData>)
        
        var isVariable: Bool { if case .variable = self { return true } else { return false } }
        var leafData: LeafData {
            switch self {
                case .variable(_, .some(let v)), .literal(let v) : return v
                case .variable(_, .none) : return .error(internal: "Value was not refreshed")
            }
        }
    }
    
    private var container: Container
}
