//
//  NSManagedObject+Extensions.swift
//
//
//  Created by Yauheni Fiadotau on 9.10.23.
//

import CoreData

public extension NSManagedObject {
    class func createFetchRequest(with config: DataStorageFRConfiguration = .init()) -> NSFetchRequest<NSFetchRequestResult> {
        let fetchRequest = fetchRequest()
        fetchRequest.predicate = config.predicate
        fetchRequest.sortDescriptors = config.sortDescriptors
        fetchRequest.fetchLimit = config.limit
        return fetchRequest
    }
    
    class func createDeleteRequest(with config: DataStorageFRConfiguration = .init()) -> NSBatchDeleteRequest {
        .init(fetchRequest: createFetchRequest(with: config))
    }
    
    func validate() throws {
        if isInserted { try validateForInsert() }
        if isUpdated { try validateForUpdate() }
        if isDeleted { try validateForDelete() }
    }
}
