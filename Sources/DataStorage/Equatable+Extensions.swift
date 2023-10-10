//
//  Equatable+Extensions.swift
//
//
//  Created by Yauheni Fiadotau on 10.10.23.
//

import Foundation

extension Equatable {
    fileprivate func isEqual(_ other: any Equatable) -> Bool {
        guard let other = other as? Self else {
            return other.isExactlyEqual(self)
        }
        return self == other
    }
    
    private func isExactlyEqual(_ other: any Equatable) -> Bool {
        guard let other = other as? Self else {
            return false
        }
        return self == other
    }
}

private func areEqual(first: Any, second: Any) -> Bool {
    guard
        let equatableOne = first as? any Equatable,
        let equatableTwo = second as? any Equatable
    else { return false }
    
    return equatableOne.isEqual(equatableTwo)
}

public func ==<L, R>(lhs: L, rhs: R) -> Bool {
    guard
        let equatableLhs = lhs as? any Equatable,
        let equatableRhs = rhs as? any Equatable
    else { return false }
    
    return equatableLhs.isEqual(equatableRhs)
}

public func ==<L, R>(lhs: L?, rhs: R?) -> Bool {
    if let lhs, let rhs {
        return lhs == rhs
    } else if lhs == nil, rhs == nil {
        return true
    } else {
        return false
    }
}

public func !=<L, R>(lhs: L, rhs: R) -> Bool {
    !(lhs == rhs)
}

public func !=<L, R>(lhs: L?, rhs: R?) -> Bool {
    !(lhs == rhs)
}

