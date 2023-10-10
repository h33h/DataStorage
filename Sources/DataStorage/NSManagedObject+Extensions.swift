//
//  NSManagedObject+Extensions.swift
//
//
//  Created by Yauheni Fiadotau on 9.10.23.
//

import CoreData

public extension NSManagedObject {
    static func createFetchRequest(with config: DataStorageFRConfiguration = .init()) -> NSFetchRequest<NSFetchRequestResult> {
        let fetchRequest = fetchRequest()
        fetchRequest.predicate = config.predicate
        fetchRequest.sortDescriptors = config.sortDescriptors
        fetchRequest.fetchLimit = config.limit
        return fetchRequest
    }
    
    static func createDeleteRequest(with config: DataStorageFRConfiguration = .init()) -> NSBatchDeleteRequest {
        return .init(fetchRequest: createFetchRequest(with: config))
    }
    
    static func objectsCount(for config: DataStorageFRConfiguration = .init(), inContext context: NSManagedObjectContext) throws -> Int {
        let fetchRequest = createFetchRequest(with: config)
        return try context.count(for: fetchRequest)
    }
    
    static func deleteObjects(for config: DataStorageFRConfiguration = .init(), inContext context: NSManagedObjectContext) throws {
        let deleteRequest = createDeleteRequest(with: config)
        try context.execute(deleteRequest)
    }
    
    static func objects(with value: CVarArg, for key: String, includePendingChanges: Bool = true, inContext context: NSManagedObjectContext) throws -> [NSManagedObject] {
        try objectsSatisfying([key: value], includePendingChanges: includePendingChanges, inContext: context)
    }
    
    static func objects(withPossibleValues values: [CVarArg], for key: String, includePendingChanges: Bool = true, inContext context: NSManagedObjectContext) throws -> [NSManagedObject] {
        let predicate = NSPredicate(format: "%K IN %@", key, values)
        let fetchRequest = createFetchRequest(with: .init(predicate: predicate))
        fetchRequest.includesPendingChanges = includePendingChanges
        return try context.fetch(fetchRequest) as? [NSManagedObject] ?? []
    }
    
    static func objectsSatisfying(_ dict: [String: CVarArg], includePendingChanges: Bool = true, inContext context: NSManagedObjectContext) throws -> [NSManagedObject] {
        let predicates = dict.map { NSPredicate(format: "%K == %@", $0.key, $0.value) }
        let fetchRequest = createFetchRequest(with: .init(predicate: NSCompoundPredicate(andPredicateWithSubpredicates: predicates)))
        fetchRequest.includesPendingChanges = includePendingChanges
        return try context.fetch(fetchRequest) as? [NSManagedObject] ?? []
    }
    
    static func anyObject(inContext context: NSManagedObjectContext) throws -> NSManagedObject? {
        try context.fetch(createFetchRequest()).first as? NSManagedObject
    }
    
    func validate() throws {
        if isInserted { try validateForInsert() }
        if isUpdated { try validateForUpdate() }
        if isDeleted { try validateForDelete() }
    }
    
    func copy(in context: NSManagedObjectContext) -> NSManagedObject? {
        guard !isDeleted, let entityName = entity.name else { return nil }
        
        let newObject = NSEntityDescription.insertNewObject(forEntityName: entityName, into: context)
            
        entity.attributesByName.forEach { key, _ in
            if let attributeValue = value(forKey: key) {
                newObject.setValue(attributeValue, forKey: key)
            }
        }
        
        entity.relationshipsByName.forEach { key, _ in
            if let relationshipValue = value(forKey: key) as? Set<NSManagedObject> {
                let newRelationshipSet = NSMutableSet()
                for relatedObject in relationshipValue {
                    if let relatedCopy = relatedObject.copy(in: context) {
                        newRelationshipSet.add(relatedCopy)
                    }
                }
                newObject.setValue(newRelationshipSet, forKey: key)
            } else if let relationshipValue = value(forKey: key) as? NSManagedObject {
                if let relatedCopy = relationshipValue.copy(in: context) {
                    newObject.setValue(relatedCopy, forKey: key)
                }
            }
        }
        return newObject
    }
}
