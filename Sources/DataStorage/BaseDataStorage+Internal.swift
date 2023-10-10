//
//  BaseDataStorage+Internal.swift
//
//
//  Created by Yauheni Fiadotau on 11.10.23.
//

import CoreData

extension BaseDataStorage {
    func objectsCount<T: NSManagedObject>(of type: T.Type, for config: DataStorageFRConfiguration = .init(), inContext context: NSManagedObjectContext) throws -> Int {
        let fetchRequest = createFetchRequest(of: type, with: config)
        return try context.count(for: fetchRequest)
    }
    
    func deleteObjects<T: NSManagedObject>(of type: T.Type, for config: DataStorageFRConfiguration = .init(), inContext context: NSManagedObjectContext) throws {
        let deleteRequest = createDeleteRequest(of: type, with: config)
        try context.execute(deleteRequest)
    }
    
    func objects<T: NSManagedObject>(of type: T.Type, with value: CVarArg, for key: String, includePendingChanges: Bool = true, inContext context: NSManagedObjectContext) throws -> [T] {
        try objectsSatisfying(of: type, [key: value], includePendingChanges: includePendingChanges, inContext: context)
    }
    
    func objects<T: NSManagedObject>(of type: T.Type, withPossibleValues values: [CVarArg], for key: String, includePendingChanges: Bool = true, inContext context: NSManagedObjectContext) throws -> [T] {
        let predicate = NSPredicate(format: "%K IN %@", key, values)
        let fetchRequest = createFetchRequest(of: type, with: .init(predicate: predicate))
        fetchRequest.includesPendingChanges = includePendingChanges
        return try context.fetch(fetchRequest)
    }
    
    func objectsSatisfying<T: NSManagedObject>(of type: T.Type, _ dict: [String: CVarArg], includePendingChanges: Bool = true, inContext context: NSManagedObjectContext) throws -> [T] {
        let predicates = dict.map { NSPredicate(format: "%K == %@", $0.key, $0.value) }
        let fetchRequest = createFetchRequest(of: type, with: .init(predicate: NSCompoundPredicate(andPredicateWithSubpredicates: predicates)))
        fetchRequest.includesPendingChanges = includePendingChanges
        return try context.fetch(fetchRequest)
    }
    
    func anyObject<T: NSManagedObject>(of type: T.Type, inContext context: NSManagedObjectContext) throws -> T? {
        try context.fetch(createFetchRequest(of: type)).first
    }
    
    func copy<T: NSManagedObject>(_ object: T, in context: NSManagedObjectContext) -> T? {
        guard !object.isDeleted else { return nil }
        
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
                    if let relatedCopy = copy(relatedObject, in: context) {
                        newRelationshipSet.add(relatedCopy)
                    }
                }
                newObject.setValue(newRelationshipSet, forKey: key)
            } else if let relationshipValue = object.value(forKey: key) as? NSManagedObject {
                if let relatedCopy = copy(relationshipValue, in: context) {
                    newObject.setValue(relatedCopy, forKey: key)
                }
            }
        }
        return newObject
    }
    
    func updateObjects<T: NSManagedObject>(of type: T.Type, withArrayOfDictionaries arrayOfDicts: [[String: Any]], inContext context: NSManagedObjectContext) -> [T] {
        let entity = type.entity()
        var result = [T]()

        guard let uniqueAttribute = entity.uniqueAttribute else {
            result += arrayOfDicts.map { dictionary in
                let newObject = T(context: context)
                update(newObject, withDictionary: dictionary, inContext: context)
                return newObject
            }
            return result
        }

        let values = arrayOfDicts.compactMap { $0[uniqueAttribute.importName] as? CVarArg }
        let existingObjects = (try? objects(of: T.self, withPossibleValues: values, for: uniqueAttribute.name, inContext: context)) ?? []
        let existingObjectDict = Dictionary(existingObjects.compactMap { ($0.value(forKey: uniqueAttribute.name) as? AnyHashable, $0) }, uniquingKeysWith: { $1 })

        for dict in arrayOfDicts {
            if let value = dict[uniqueAttribute.importName] as? AnyHashable,
               let existingObject = existingObjectDict[value] {
                update(existingObject, withDictionary: dict, inContext: context)
                result.append(existingObject)
            } else {
                let newObject = T(context: context)
                update(newObject, withDictionary: dict, inContext: context)
                result.append(newObject)
            }
        }

        return result
    }
    
    func updateObject<T: NSManagedObject>(of type: T.Type, withDictionary dict: [String: Any], inContext context: NSManagedObjectContext) -> T {
        updateObjects(of: type, withArrayOfDictionaries: [dict], inContext: context)[.zero]
    }
    
    func update<T: NSManagedObject>(_ object: T, withDictionary dict: [String: Any], inContext context: NSManagedObjectContext) {
        updateAttributes(for: object, withDictionary: dict)
        updateRelationships(for: object, withDictionary: dict, inContext: context)
    }
    
    func updateAttributes<T: NSManagedObject>(for object: T, withDictionary dict: [String: Any]) {
        let attributes = object.entity.attributes
        
        attributes.forEach { attribute in
            if let valueInDictForAttribute = dict[attribute.importName] {
                object.setValue(T.transformValue(valueInDictForAttribute, forAttribute: attribute), forKey: attribute.name)
            }
        }
    }
    
    func updateRelationships<T: NSManagedObject>(for object: T, withDictionary dict: [String: Any], inContext context: NSManagedObjectContext) {
        let relationships = object.entity.relationships
        
        relationships.forEach { relationship in
            guard let destinationEntity = relationship.destinationEntity, let destinationClass = NSClassFromString(destinationEntity.managedObjectClassName) as? NSManagedObject.Type else { return }
            
            if relationship.isToMany {
                if let relationshipDictionaries = dict[relationship.importName] as? [[String: Any]] {
                    if relationship.isOrdered {
                        if let orderedSet = object.value(forKey: relationship.name) as? NSMutableOrderedSet {
                            if relationship.deleteNotUpdated {
                                let updatedObjects = Set(updateObjects(of: destinationClass, withArrayOfDictionaries: relationshipDictionaries, inContext: context))
                                let objectsForRemove = orderedSet.compactMap { $0 as? NSManagedObject }.filter { !updatedObjects.contains($0) }
                                orderedSet.intersectSet(updatedObjects)
                                orderedSet.unionSet(updatedObjects)
                                object.setValue(orderedSet, forKey: relationship.name)
                                objectsForRemove.forEach { context.delete($0) }
                            } else {
                                orderedSet.unionSet(Set(updateObjects(of: destinationClass, withArrayOfDictionaries: relationshipDictionaries, inContext: context)))
                                object.setValue(orderedSet, forKey: relationship.name)
                            }
                        } else {
                            object.setValue(NSOrderedSet(array: updateObjects(of: destinationClass, withArrayOfDictionaries: relationshipDictionaries, inContext: context)), forKey: relationship.name)
                        }
                    } else {
                        if let set = object.value(forKey: relationship.name) as? NSMutableSet {
                            if relationship.deleteNotUpdated {
                                let updatedObjects = Set(updateObjects(of: destinationClass, withArrayOfDictionaries: relationshipDictionaries, inContext: context))
                                let objectsForRemove = set.compactMap { $0 as? NSManagedObject }.filter { !updatedObjects.contains($0) }
                                set.intersect(updatedObjects)
                                set.union(updatedObjects)
                                object.setValue(set, forKey: relationship.name)
                                objectsForRemove.forEach { context.delete($0) }
                            } else {
                                set.union(Set(updateObjects(of: destinationClass, withArrayOfDictionaries: relationshipDictionaries, inContext: context)))
                                object.setValue(set, forKey: relationship.name)
                            }
                        } else {
                            object.setValue(NSSet(array: updateObjects(of: destinationClass, withArrayOfDictionaries: relationshipDictionaries, inContext: context)), forKey: relationship.name)
                        }
                    }
                }
            } else {
                if let relationshipDictionary = dict[relationship.importName] as? [String: Any] {
                    object.setValue(updateObject(of: destinationClass,withDictionary: relationshipDictionary, inContext: context), forKey: relationship.name)
                }
            }
        }
    }
}
