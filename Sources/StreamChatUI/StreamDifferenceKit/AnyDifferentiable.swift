/// A type-erased differentiable value.
///
/// The `AnyDifferentiable` type hides the specific underlying types.
/// Associated type `DifferenceIdentifier` is erased by `AnyHashable`.
/// The comparisons of whether has updated is forwards to an underlying differentiable value.
///
/// You can store mixed-type elements in collection that require `Differentiable` conformance by
/// wrapping mixed-type elements in `AnyDifferentiable`:
///
///     extension String: Differentiable {}
///     extension Int: Differentiable {}
///
///     let source = [
///         AnyDifferentiable("ABC"),
///         AnyDifferentiable(100)
///     ]
///     let target = [
///         AnyDifferentiable("ABC"),
///         AnyDifferentiable(100),
///         AnyDifferentiable(200)
///     ]
///
///     let changeset = StagedChangeset(source: source, target: target)
///     print(changeset.isEmpty)  // prints "false"
struct AnyDifferentiable: Differentiable {
    /// The value wrapped by this instance.
    @inlinable
    var base: Any {
        box.base
    }

    /// A type-erased identifier value for difference calculation.
    @inlinable
    var differenceIdentifier: AnyHashable {
        box.differenceIdentifier
    }

    @usableFromInline
    internal let box: AnyDifferentiableBox

    /// Creates a type-erased differentiable value that wraps the given instance.
    ///
    /// - Parameters:
    ///   - base: A differentiable value to wrap.
    init<D: Differentiable>(_ base: D) {
        if let anyDifferentiable = base as? AnyDifferentiable {
            self = anyDifferentiable
        } else {
            box = DifferentiableBox(base)
        }
    }

    /// Indicate whether the content of `base` is equals to the content of the given source value.
    ///
    /// - Parameters:
    ///   - source: A source value to be compared.
    ///
    /// - Returns: A Boolean value indicating whether the content of `base` is equals
    ///            to the content of `base` of the given source value.
    @inlinable
    func isContentEqual(to source: AnyDifferentiable) -> Bool {
        box.isContentEqual(to: source.box)
    }
}

extension AnyDifferentiable: CustomDebugStringConvertible {
    var debugDescription: String {
        "AnyDifferentiable(\(String(reflecting: base)))"
    }
}

@usableFromInline
internal protocol AnyDifferentiableBox {
    var base: Any { get }
    var differenceIdentifier: AnyHashable { get }

    func isContentEqual(to source: AnyDifferentiableBox) -> Bool
}

@usableFromInline
internal struct DifferentiableBox<Base: Differentiable>: AnyDifferentiableBox {
    @usableFromInline
    internal let baseComponent: Base

    @inlinable
    internal var base: Any {
        baseComponent
    }

    @inlinable
    internal var differenceIdentifier: AnyHashable {
        baseComponent.differenceIdentifier
    }

    @usableFromInline
    internal init(_ base: Base) {
        baseComponent = base
    }

    @inlinable
    internal func isContentEqual(to source: AnyDifferentiableBox) -> Bool {
        guard let sourceBase = source.base as? Base else {
            return false
        }
        return baseComponent.isContentEqual(to: sourceBase)
    }
}
