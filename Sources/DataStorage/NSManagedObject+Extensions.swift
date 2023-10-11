//
//  NSManagedObject+Extensions.swift
//
//
//  Created by Yauheni Fiadotau on 9.10.23.
//

import CoreData

public extension NSManagedObject {
    class func createFetchRequest(with config: DataStorageFRConfiguration = .init()) throws -> NSFetchRequest<NSFetchRequestResult> {
        let fetchRequest = fetchRequest()
        fetchRequest.predicate = config.predicate
        fetchRequest.sortDescriptors = config.sortDescriptors
        fetchRequest.fetchLimit = config.limit
        return fetchRequest
    }
    
    class func createDeleteRequest(with config: DataStorageFRConfiguration = .init()) throws -> NSBatchDeleteRequest {
        .init(fetchRequest: try createFetchRequest(with: config))
    }
    
    func validate() throws {
        if isInserted { try validateForInsert() }
        if isUpdated { try validateForUpdate() }
        if isDeleted { try validateForDelete() }
    }
}
