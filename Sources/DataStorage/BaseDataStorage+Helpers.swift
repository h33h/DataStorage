//
//  BaseDataStorage+Helpers.swift
//
//
//  Created by Yauheni Fiadotau on 11.10.23.
//

import CoreData

public extension BaseDataStorage {
    func createFetchRequest<T: NSManagedObject>(of type: T.Type, with config: DataStorageFRConfiguration = .init()) throws -> NSFetchRequest<T> {
        let fetchRequest = T.fetchRequest()
        fetchRequest.predicate = config.predicate
        fetchRequest.sortDescriptors = config.sortDescriptors
        fetchRequest.fetchLimit = config.limit
        if let fetchRequest = fetchRequest as? NSFetchRequest<T> {
            return fetchRequest
        } else {
            throw DataStorageError.convertToConcreteTypeFail
        }
    }
    
    func createDeleteRequest<T: NSManagedObject>(of type: T.Type, with config: DataStorageFRConfiguration = .init()) throws -> NSBatchDeleteRequest {
        if let fetchRequest = try createFetchRequest(of: T.self, with: config) as? NSFetchRequest<NSFetchRequestResult> {
            return .init(fetchRequest: fetchRequest)
        } else {
            throw DataStorageError.convertToConcreteTypeFail
        }
    }
    
    func objectsCount<T: NSManagedObject>(of type: T.Type, for config: DataStorageFRConfiguration = .init(), inContext context: NSManagedObjectContext) throws -> Int {
        let fetchRequest = try createFetchRequest(of: T.self, with: config)
        return try context.count(for: fetchRequest)
    }
    
    func deleteObjects<T: NSManagedObject>(of type: T.Type, for config: DataStorageFRConfiguration = .init(), inContext context: NSManagedObjectContext) throws {
        let deleteRequest = try createDeleteRequest(of: T.self, with: config)
        try context.execute(deleteRequest)
    }
    
    func objects<T: NSManagedObject>(of type: T.Type, with value: CVarArg, for key: String, includePendingChanges: Bool = true, inContext context: NSManagedObjectContext) throws -> [T] {
        try objectsSatisfying(of: T.self, [key: value], includePendingChanges: includePendingChanges, inContext: context)
    }
    
    func objects<T: NSManagedObject>(of type: T.Type, withPossibleValues values: [CVarArg], for key: String, includePendingChanges: Bool = true, inContext context: NSManagedObjectContext) throws -> [T] {
        let predicate = NSPredicate(format: "%K IN %@", key, values)
        let fetchRequest = try createFetchRequest(of: T.self, with: .init(predicate: predicate))
        fetchRequest.includesPendingChanges = includePendingChanges
        return try context.fetch(fetchRequest)
    }
    
    func objectsSatisfying<T: NSManagedObject>(of type: T.Type, _ dict: [String: CVarArg], includePendingChanges: Bool = true, inContext context: NSManagedObjectContext) throws -> [T] {
        let predicates = dict.map { NSPredicate(format: "%K == %@", $0.key, $0.value) }
        let fetchRequest = try createFetchRequest(of: type, with: .init(predicate: NSCompoundPredicate(andPredicateWithSubpredicates: predicates)))
        fetchRequest.includesPendingChanges = includePendingChanges
        return try context.fetch(fetchRequest)
    }
    
    func anyObject<T: NSManagedObject>(of type: T.Type, inContext context: NSManagedObjectContext) throws -> T {
        if let object = try context.fetch(createFetchRequest(of: T.self)).first {
            return object
        } else {
            throw DataStorageError.objectNotExist
        }
    }
    
    func copy<T: NSManagedObject>(_ object: T, in context: NSManagedObjectContext) -> T {
        let newObject = T(context: context)
            
        object.entity.attributesByName.forEach { key, _ in
            if let attributeValue = object.value(forKey: key) {
                newObject.setValue(attributeValue, forKey: key)
            }
        }
        
        object.entity.relationshipsByName.forEach { key, _ in
            if let relationshipValue = object.value(forKey: key) as? Set<NSManagedObject> {
                let newRelationshipSet = NSMutableSet()
                for relatedObject in relationshipValue {
                    let relatedCopy = copy(relatedObject, in: context)
                    newRelationshipSet.add(relatedCopy)
                }
                newObject.setValue(newRelationshipSet, forKey: key)
            } else if let relationshipValue = object.value(forKey: key) as? NSManagedObject {
                let relatedCopy = copy(relationshipValue, in: context)
                newObject.setValue(relatedCopy, forKey: key)
            }
        }
        return newObject
    }
    
    func updateObjects<T: NSManagedObject>(of type: T.Type, withArrayOfDictionaries arrayOfDicts: [[String: Any]], inContext context: NSManagedObjectContext) throws -> [T] {
        let entity = type.entity()
        var result = [T]()

        guard let uniqueAttribute = entity.uniqueAttribute else {
            result += try arrayOfDicts.map { dictionary in
                let newObject = type.init(context: context)
                try update(newObject, withDictionary: dictionary, inContext: context)
                return newObject
            }
            return result
        }

        let values = try arrayOfDicts.map { dict in
            if let importUniqueValue = dict[uniqueAttribute.importName] as? CVarArg {
                return importUniqueValue
            } else {
                throw DataStorageError.importUniqueKeyMustBeCVarArg
            }
        }
        let existingObjects = try objects(of: type, withPossibleValues: values, for: uniqueAttribute.name, inContext: context)
        let existingObjectDict = Dictionary(try existingObjects.map { existingObject in
            if let hashableUniqueAttribute = existingObject.value(forKey: uniqueAttribute.name) as? AnyHashable {
                return (hashableUniqueAttribute, existingObject)
            } else {
                throw DataStorageError.uniqueKeyMustBeHashable
            }
            
        }, uniquingKeysWith: { $1 })

        for dict in arrayOfDicts {
            if let value = dict[uniqueAttribute.importName] as? AnyHashable,
               let existingObject = existingObjectDict[value] {
                try update(existingObject, withDictionary: dict, inContext: context)
                result.append(existingObject)
            } else {
                let newObject = type.init(context: context)
                try update(newObject, withDictionary: dict, inContext: context)
                result.append(newObject)
            }
        }

        return result
    }
    
    func updateObject<T: NSManagedObject>(of type: T.Type, withDictionary dict: [String: Any], inContext context: NSManagedObjectContext) throws -> T {
        try updateObjects(of: T.self, withArrayOfDictionaries: [dict], inContext: context).first!
    }
    
    func update<T: NSManagedObject>(_ object: T, withDictionary dict: [String: Any], inContext context: NSManagedObjectContext) throws {
        updateAttributes(for: object, withDictionary: dict)
        try updateRelationships(for: object, withDictionary: dict, inContext: context)
    }
    
    private func updateAttributes<T: NSManagedObject>(for object: T, withDictionary dict: [String: Any]) {
        let attributes = object.entity.attributes
        
        attributes.forEach { attribute in
            if let valueInDictForAttribute = dict[attribute.importName] {
                object.setValue(T.transformValue(valueInDictForAttribute, forAttribute: attribute), forKey: attribute.name)
            }
        }
    }
    
    private func updateRelationships<T: NSManagedObject>(for object: T, withDictionary dict: [String: Any], inContext context: NSManagedObjectContext) throws {
        let relationships = object.entity.relationships
        
        try relationships.forEach { relationship in
            guard let destinationEntity = relationship.destinationEntity, let destinationClass = NSClassFromString(destinationEntity.managedObjectClassName) as? NSManagedObject.Type else { throw DataStorageError.relationshipHaveNoDestinationEntity }
            
            if relationship.isToMany {
                if let relationshipDictionaries = dict[relationship.importName] as? [[String: Any]] {
                    if relationship.isOrdered {
                        if let orderedSet = object.value(forKey: relationship.name) as? NSMutableOrderedSet {
                            if relationship.deleteNotUpdated {
                                let updatedObjects = Set(try updateObjects(of: destinationClass, withArrayOfDictionaries: relationshipDictionaries, inContext: context))
                                let objectsForRemove = orderedSet.compactMap { $0 as? NSManagedObject }.filter { !updatedObjects.contains($0) }
                                orderedSet.intersectSet(updatedObjects)
                                orderedSet.unionSet(updatedObjects)
                                object.setValue(orderedSet, forKey: relationship.name)
                                objectsForRemove.forEach { context.delete($0) }
                            } else {
                                orderedSet.unionSet(Set(try updateObjects(of: destinationClass, withArrayOfDictionaries: relationshipDictionaries, inContext: context)))
                                object.setValue(orderedSet, forKey: relationship.name)
                            }
                        } else {
                            object.setValue(NSOrderedSet(array: try updateObjects(of: destinationClass, withArrayOfDictionaries: relationshipDictionaries, inContext: context)), forKey: relationship.name)
                        }
                    } else {
                        if let set = object.value(forKey: relationship.name) as? NSMutableSet {
                            if relationship.deleteNotUpdated {
                                let updatedObjects = Set(try updateObjects(of: destinationClass, withArrayOfDictionaries: relationshipDictionaries, inContext: context))
                                let objectsForRemove = set.compactMap { $0 as? NSManagedObject }.filter { !updatedObjects.contains($0) }
                                set.intersect(updatedObjects)
                                set.union(updatedObjects)
                                object.setValue(set, forKey: relationship.name)
                                objectsForRemove.forEach { context.delete($0) }
                            } else {
                                set.union(Set(try updateObjects(of: destinationClass.self, withArrayOfDictionaries: relationshipDictionaries, inContext: context)))
                                object.setValue(set, forKey: relationship.name)
                            }
                        } else {
                            object.setValue(NSSet(array: try updateObjects(of: destinationClass, withArrayOfDictionaries: relationshipDictionaries, inContext: context)), forKey: relationship.name)
                        }
                    }
                }
            } else {
                if let relationshipDictionary = dict[relationship.importName] as? [String: Any] {
                    object.setValue(try updateObject(of: destinationClass, withDictionary: relationshipDictionary, inContext: context), forKey: relationship.name)
                }
            }
        }
    }
}
