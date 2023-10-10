//
//  NSManagedObject+Extensions.swift
//
//
//  Created by Yauheni Fiadotau on 9.10.23.
//

import CoreData

public extension NSManagedObject {
    func validate() throws {
        if isInserted { try validateForInsert() }
        if isUpdated { try validateForUpdate() }
        if isDeleted { try validateForDelete() }
    }
}
