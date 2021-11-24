/// A concrete parameter object that can be stored inside a LeafAST, either as an expression/function/block
/// parameter or as a passthrough atomic object at the top level of an AST
///
/// ```
/// // Atomic Invariants
/// case value(LeafData)            // Parameter.literal
/// case keyword(LeafKeyword)       // Parameter.keyword - unvalued
/// case `operator`(LeafOperator)   // Parameter.operator - limited subset
/// // Atomic Symbols
/// case variable(LKVariable)     // Parameter.variable
/// // Expression
/// case expression(LKExpression) // A constrained 2-3 value Expression
/// // Tuple
/// case tuple([LKParameter])     // A 0...n array of LeafParameters
/// // Function - Single exact match function
/// case function(String, LeafFunction, [LKParameter], LKParameter?)
/// // Dynamic - Multiple potential matching overloaded functions (filtered)
/// case dynamic(String, [(LeafFunction, LKTuple?)], [LKParameter], LKParameter?)
///
internal struct LKParameter: LKSymbol {
    // MARK: - Passthrough generators

    /// Generate a `LKParameter` holding concrete `LeafData`
    static func value(_ store: LKData) -> LKParameter { .init(.value(store)) }

    /// Generate a `LKParameter` holding a valid `.variable`
    static func variable(_ store: LKVariable) -> LKParameter { .init(.variable(store)) }

    /// Generate a `LKParameter` holding a validated `LKExpression`
    static func expression(_ store: LKExpression) -> LKParameter { .init(.expression(store)) }

    /// Generate a `LKParameter` holding an available `LeafOperator`
    static func `operator`(_ store: LeafOperator) -> LKParameter {
        if store.parseable { return .init(.operator(store)) }
        __MajorBug("Operator not available")
    }

    /// Generate a `LKParameter` hodling a validated `LeafFunction` and its concrete parameters
    ///
    /// If function call is as a method, `operand` is a non nil-tuple; if it contains a var, method is mutating
    static func function(_ name: String,
                         _ function: LeafFunction?,
                         _ params: LKTuple?,
                         _ operand: LKVariable?? = .none,
                         _ location: SourceLocation) -> LKParameter {
        .init(.function(name, function, params, operand, location)) }

    // MARK: - Auto-reducing generators

    /// Generate a `LKParameter`, auto-reduce to a `.value` or .`.variable` or a non-evaluable`.keyword`
    static func keyword(_ store: LeafKeyword,
                        reduce: Bool = false) -> LKParameter {
        if store == .nil         { return .init(.value(.trueNil)) }
        if !store.isEvaluable
                      || !reduce { return .init(.keyword(store)) }
        if store.isBooleanValued { return .init(.value(.bool(store.bool!))) }
        if store == .`self`      { return .init(.variable(.`self`)) }
        __MajorBug("Unhandled evaluable keyword")
    }

    /// Generate a `LKParameter` holding a tuple of `LeafParameters` - auto-reduce multiple nested parens and decay to trueNil if void
    static func tuple(_ store: LKTuple) -> LKParameter {
        if store.count > 1 || store.collection { return .init(.tuple(store)) }
        var store = store
        while case .tuple(let s) = store[0]?.container, s.count == 1 { store = s }
        return store.isEmpty ? .init(.value(.trueNil)) : store[0]!
    }

    /// `[` is always invalid in a parsed AST and is used as a magic value to avoid needing a nil LKParameter
    static let invalid: LKParameter = .init(.operator(.subOpen))

    // MARK: - Stored Properties
    
    /// Actual storage for the object
    private(set) var container: Container { didSet { setStates() } }

    // MARK: - LKSymbol
    
    private(set) var resolved: Bool
    private(set) var invariant: Bool
    private(set) var symbols: Set<LKVariable>
    
    private(set) var isLiteral: Bool
    
    /// Will always resolve to a new LKParameter
    func resolve(_ symbols: inout LKVarStack) -> Self { isValued ? .init(container.resolve(&symbols)) : self }
    /// Will always evaluate to a .value container, potentially holding trueNil
    func evaluate(_ symbols: inout LKVarStack) -> LKData { container.evaluate(&symbols) }
    
    var description: String { container.description }
    var short: String { isTuple ? container.description : container.short }
    
    // MARK: - Internal Only
    
    var `operator`: LeafOperator? {
        guard case .operator(let o) = container else { return nil }
        return o
    }

    var data: LKData? {
        switch container {
            case .value(let d): return d
            case .keyword(let k) where k.isBooleanValued: return .bool(k.bool)
            default: return nil
        }
    }

    /// Not guaranteed to return a type unless it's entirely knowable from context
    var baseType: LKDType? {
        switch container {
            case .expression(let e)                : return e.baseType
            case .value(let d)                     : return d.storedType
            case .tuple(let t) where t.isEvaluable : return t.baseType
            case .function(_,.some(let f),_,_,_)   :
                return type(of: f).returns.count == 1 ? type(of: f).returns.first : nil
            case .keyword, .operator, .variable,
                 .function, .tuple                 : return nil
        }
    }

    /// Whether the parameter *could* return actual `LeafData` when resolved; may be true but fail to provide value in serialize
    var isValued: Bool {
        switch container {
            case .value, .variable,
                 .function           : return true
            case .operator           : return false
            case .tuple(let t)       : return t.isEvaluable
            case .keyword(let k)     : return k.isEvaluable
            case .expression(let e)  : return e.form.exp != .custom
        }
    }
    
    var isSubscript: Bool {
        if case .expression(let e) = container, e.op == .subScript { return true }
        else { return false }
    }
    
    var isCollection: Bool? {
        switch container {
            case .expression(let e):
                return e.baseType.map { [.dictionary, .array].contains($0) }
            case .function(_,let f,_,_,_):
                return f.map {
                    !type(of: $0).returns.intersection([.dictionary, .array]).isEmpty
                        && Set<LKDType>(arrayLiteral: .dictionary, .array).isSuperset(of: type(of: $0).returns) }
            case .keyword, .operator: return false
            case .tuple(let t): return t.isEvaluable
            case .value(let v): return v.isCollection
            case .variable(let v): return v.isCollection ? true : nil
        }
    }
    
    /// Rough estimate estimate of output size
    var underestimatedSize: UInt32 {
        switch container {
            case .expression, .value,
                 .variable, .function : return 16
            case .operator, .tuple : return 0
            case .keyword(let k)   : return k.isBooleanValued ? 4 : 0
        }
    }

    var errored: Bool { error != nil }
    var error: String? {
        if case .value(let v) = container { return v.error } else { return nil } }
    
    // MARK: - Private Only

    /// Unchecked initializer - do not use directly except through static factories that guard conditions
    private init(_ store: Container) {
        self.container = store
        self.symbols = .init()
        self.resolved = false
        self.invariant = false
        self.isLiteral = false
        setStates()
    }

    /// Cache the stored states for `symbols, resolved, invariant`
    mutating private func setStates() {
        isLiteral = false
        switch container {
            case .operator, .keyword:
                symbols = []
                resolved = true
                invariant = true
            case .value(let v):
                symbols = []
                resolved = true
                invariant = v.container.isLazy ? v.invariant : true
                isLiteral = invariant && !v.errored
            case .variable(let v):
                symbols = v.symbols
                resolved = false
                invariant = true
            case .expression(let e):
                symbols = e.symbols
                resolved = false
                invariant = e.invariant
            case .tuple(let t):
                symbols = t.symbols
                resolved = t.resolved
                invariant = t.invariant
            case .function(_,let f,let p,_,_):
                resolved = p?.resolved ?? true
                symbols = p?.symbols ?? []
                invariant = f?.invariant ?? false && p?.invariant ?? true
        }
    }

    private var isTuple: Bool { if case .tuple = container { return true } else { return false } }
    
    // MARK: - Internal Scoped Type
    
    /// Wrapped storage object for the actual value the `LKParameter` holds
    enum Container: LKSymbol {
        /// A concrete `LeafData`
        case value(LKData)
        /// A `LeafKeyword` (may previously have decayed if evaluable to a different state)
        case keyword(LeafKeyword)
        /// A `LeafOperator`
        case `operator`(LeafOperator)
        /// An `LKVariable` key
        case variable(LKVariable)
        /// A constrained 2-3 value `LKExpression`
        case expression(LKExpression)
        /// A 1...n array/dictionary of LeafParameters either all with or without labels
        case tuple(LKTuple)
        /// A `LeafFunction`(s) - tuple is 1...n and may have 0...n labels - nil when empty params
        /// If function is nil, dynamic - too many matches were present at parse time or resolution time
        /// If tuple is nil, original code call had no parameters
        /// If variable is .none, original code call is as function; if .some, method - .some(nil) - nonmutating
        /// SourceLocation gives original template location should dynamic lookup fail
        case function(String, LeafFunction?, LKTuple?, LKVariable??, SourceLocation)

        // MARK: LKSymbol
        
        var description: String {
            switch self {
                case .value(let v)                : return v.description
                case .keyword(let k)              : return "keyword(\(k.description))"
                case .operator(let o)             : return "operator(\(o.description)"
                case .variable(let v)             : return "variable(\(v.description))"
                case .expression(let e)           : return "expression(\(e.description))"
                case .tuple(let t) where t.collection
                                                  : return "\(t.labels.isEmpty ? "array" : "dictionary")\(short)"
                case .tuple                       : return "tuple\(short)"
                case .function(_,.some(let f as Evaluate),_,_,_):
                    return "`\(f.identifier)()"
                case .function(let f,_,let p,_,_) : return "\(f)\(p?.description ?? "()")"
            }
        }
        
        var short: String {
            switch self {
                case .value(let d)                : return d.short
                case .keyword(let k)              : return k.short
                case .operator(let o)             : return o.short
                case .variable(let s)             : return s.short
                case .expression(let e)           : return e.short
                case .tuple(let t)  where t.collection
                                                  : return "\(t.labels.isEmpty ? t.short : t.description)"
                case .tuple(let t)                : return "\(t.short)"
                case .function(let f,_,let p,_,_) : return "\(f)\(p?.short ?? "()")"
            }
        }

        var resolved: Bool {
            switch self {
                case .keyword, .operator             : return true
                case .variable                       : return false
                case .expression(let e)              : return e.resolved
                case .value(let v)                   : return v.resolved
                case .tuple(let t),
                     .function(_,_,.some(let t),_,_) : return t.resolved
                case .function(_,let f,_,_,_)        : return f != nil
            }
        }
        
        var invariant: Bool {
            switch self {
                case .keyword, .operator,
                     .variable          : return true
                case .expression(let e) : return e.invariant
                case .tuple(let t)      : return t.invariant
                case .value(let v)      : return v.invariant
                case .function(_,let f,let p,_,_)
                    : return f?.invariant ?? false && p?.invariant ?? true
            }
        }
        
        var symbols: Set<LKVariable> {
            switch self {
                case .keyword, .operator, .value     : return []
                case .variable(let v)                : return [v]
                case .expression(let e)              : return e.symbols
                case .tuple(let t),
                     .function(_,_,.some(let t),_,_) : return t.symbols
                case .function                       : return []
            }
        }

        func resolve(_ symbols: inout LKVarStack) -> Self {
            if resolved && invariant { return .value(evaluate(&symbols)) }
            switch self {
                case .value, .keyword,
                     .operator          : return self
                case .expression(let e) : return .expression(e.resolve(&symbols))
                case .variable(let v)   : let value = symbols.match(v)
                                          return value.errored ? self : .value(value)
                case .tuple(let t)
                    where t.isEvaluable : return .tuple(t.resolve(&symbols))
                case .function(let n, let f, var p, let m, let l) :
                    if p != nil { p!.values = p!.values.map { $0.resolve(&symbols) } }
                    guard f == nil else  { return .function(n, f, p, m, l) }
                    let result = m != nil ? LKConf.entities.validateMethod(n, p, (m!) != nil)
                                          : LKConf.entities.validateFunction(n, p)
                    switch result {
                        case .failure(let e): return .value(.error(e.description, function: n))
                        case .success(let r) where r.count == 1: return .function(n, r[0].0, r[0].1, m, l)
                        default: return .function(n, nil, p, m, l)
                    }
                case .tuple             : __MajorBug("Unevaluable Tuples should not exist")
            }
        }

        func evaluate(_ symbols: inout LKVarStack) -> LeafData {
            func softError(_ result: LKData) -> LKData {
                !result.errored ? result
                                : symbols.context.missingVariableThrows ? result
                                                                        : .trueNil }
            
            switch self {
                case .value(let v)              : return softError(v.evaluate(&symbols))
                case .variable(let v)           : return softError(symbols.match(v))
                case .expression(let e)         : return softError(e.evaluate(&symbols))
                case .tuple(let t)
                        where t.isEvaluable     : return softError(t.evaluate(&symbols))
                case .function(let n, let f as Evaluate, _, _, let l) :
                    let x = symbols.match(.define(f.identifier))
                    /// `Define` parameter was found - evaluate if non-value, and return
                    if case .evaluate(let x) = x.container { return softError(x.evaluate(&symbols)) }
                    /// Or parameter was literal - return
                    else if !x.errored { return x.container.evaluate }
                    /// Or `Evaluate` had a default - evaluate and return that
                    else if let x = f.defaultValue { return softError(x.evaluate(&symbols)) }
                    return softError(.error(internal: "\(f.identifier) is undefined and has no default value", n, l))
                case .function(let n, var f, let p, let m, let l) :
                    var p = p ?? .init()
                    /// Existing literal parameter is errored and we're throwing - return immediately
                    if symbols.context.missingVariableThrows,
                       let error = p.values.first(where: {$0.errored}) { return error.evaluate(&symbols) }
                    /// Check all non-literal or errored params
                    for i in p.values.indices where !p.values[i].isLiteral || p.values[i].errored {
                        let eval = p.values[i].evaluate(&symbols)
                        /// Return hard errors immediately if we're throwing
                        if eval.errored && symbols.context.missingVariableThrows { return eval }
                        /// If we have a concrete function and it doesn't take optional at this position, cascade void/error now
                        if eval.storedType == .void && !(f?.sig[i].optional ?? true) {
                            return eval.errored ? eval : .error(internal: "\(p.values[i].description) returned void", n, l) }
                        /// Evaluation checks passed but value may be decayable error - convert to truenil
                        p.values[i] = .value(!eval.errored ? eval : .trueNil)
                    }
                    if f == nil {
                        let result = m != nil ? LKConf.entities.validateMethod(n, p, (m!) != nil)
                                              : LKConf.entities.validateFunction(n, p)
                        switch result {
                            case .success(let r) where r.count == 1:
                                f = r.first!.0
                                p = r.first!.1 ?? p
                            case .failure(let e): return softError(.error(internal: e.description, n, l))
                            default:
                                return softError(.error(internal: "Dynamic call had too many matches at evaluation", n, l))
                        }
                    }
                    guard let call = LeafCallValues(f!.sig, p, &symbols) else {
                        return softError(.error(internal: "Couldn't validate parameter types for \(n)\(p.description)", n, l)) }
                    if var unsafeF = f as? LeafUnsafeEntity {
                        unsafeF.unsafeObjects = symbols.context.unsafeObjects
                        f = (unsafeF as LeafFunction)
                    }
                    if case .some(.some(let op)) = m, let f = f as? LeafMutatingMethod {
                        let x = f.mutatingEvaluate(call)
                        if let updated = x.0 { symbols.update(op, updated) }
                        return x.1
                    } else { return softError(f!.evaluate(call)) }
                case .keyword(let k)
                        where k.isEvaluable     : let x = LKParameter.keyword(k, reduce: true)
                                                  return softError(x.container.evaluate(&symbols))
                case .keyword, .operator,
                     .tuple                     : __MajorBug("Unevaluable \(self.short) should not exist")
            }
        }
    }
}
