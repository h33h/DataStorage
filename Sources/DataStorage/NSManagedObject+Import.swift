//
//  NSManagedObject+Import.swift
//
//
//  Created by Yauheni Fiadotau on 11.10.23.
//

import CoreData

public extension NSManagedObject {
    class func updateObjects<T: NSManagedObject>(withArrayOfDictionaries arrayOfDicts: [[String: Any]], inContext context: NSManagedObjectContext) throws -> [T] {
        let entity = T.entity()
        var result = [T]()

        guard let uniqueAttribute = entity.uniqueAttribute else {
            result += try arrayOfDicts.map { dictionary in
                let newObject = T(context: context)
                try newObject.update(withDictionary: dictionary, inContext: context)
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
        let existingObjects = try context.objects(of: T.self, withPossibleValues: values, for: uniqueAttribute.name)
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
                try existingObject.update(withDictionary: dict, inContext: context)
                result.append(existingObject)
            } else {
                let newObject = T(context: context)
                try newObject.update(withDictionary: dict, inContext: context)
                result.append(newObject)
            }
        }

        return result
    }
    
    class func updateObject(withDictionary dict: [String: Any], inContext context: NSManagedObjectContext) throws -> Self {
        try Self.updateObjects(withArrayOfDictionaries: [dict], inContext: context).first!
    }
    
    func update(withDictionary dict: [String: Any], inContext context: NSManagedObjectContext) throws {
        updateAttributes(withDictionary: dict)
        try updateRelationships(withDictionary: dict, inContext: context)
    }
    
    private func updateAttributes(withDictionary dict: [String: Any]) {
        let attributes = entity.attributes
        
        attributes.forEach { attribute in
            if let valueInDictForAttribute = dict[attribute.importName] {
                setValue(Self.transformValue(valueInDictForAttribute, forAttribute: attribute), forKey: attribute.name)
            }
        }
    }
    
    private func updateRelationships(withDictionary dict: [String: Any], inContext context: NSManagedObjectContext) throws {
        let relationships = entity.relationships
        
        try relationships.forEach { relationship in
            guard let destinationEntity = relationship.destinationEntity, let destinationClass = NSClassFromString(destinationEntity.managedObjectClassName) as? NSManagedObject.Type else { throw DataStorageError.relationshipHaveNoDestinationEntity }
            
            if relationship.isToMany {
                if let relationshipDictionaries = dict[relationship.importName] as? [[String: Any]] {
                    if relationship.isOrdered {
                        if let orderedSet = value(forKey: relationship.name) as? NSMutableOrderedSet {
                            if relationship.deleteNotUpdated {
                                let updatedObjects = Set(try destinationClass.updateObjects(withArrayOfDictionaries: relationshipDictionaries, inContext: context))
                                let objectsForRemove = orderedSet.compactMap { $0 as? NSManagedObject }.filter { !updatedObjects.contains($0) }
                                orderedSet.intersectSet(updatedObjects)
                                orderedSet.unionSet(updatedObjects)
                                setValue(orderedSet, forKey: relationship.name)
                                objectsForRemove.forEach { context.delete($0) }
                            } else {
                                orderedSet.unionSet(Set(try destinationClass.updateObjects(withArrayOfDictionaries: relationshipDictionaries, inContext: context)))
                                setValue(orderedSet, forKey: relationship.name)
                            }
                        } else {
                            setValue(NSOrderedSet(array: try destinationClass.updateObjects(withArrayOfDictionaries: relationshipDictionaries, inContext: context)), forKey: relationship.name)
                        }
                    } else {
                        if let set = value(forKey: relationship.name) as? NSMutableSet {
                            if relationship.deleteNotUpdated {
                                let updatedObjects = Set(try destinationClass.updateObjects(withArrayOfDictionaries: relationshipDictionaries, inContext: context))
                                let objectsForRemove = set.compactMap { $0 as? NSManagedObject }.filter { !updatedObjects.contains($0) }
                                set.intersect(updatedObjects)
                                set.union(updatedObjects)
                                setValue(set, forKey: relationship.name)
                                objectsForRemove.forEach { context.delete($0) }
                            } else {
                                set.union(Set(try destinationClass.updateObjects(withArrayOfDictionaries: relationshipDictionaries, inContext: context)))
                                setValue(set, forKey: relationship.name)
                            }
                        } else {
                            setValue(NSSet(array: try destinationClass.updateObjects(withArrayOfDictionaries: relationshipDictionaries, inContext: context)), forKey: relationship.name)
                        }
                    }
                }
            } else {
                if let relationshipDictionary = dict[relationship.importName] as? [String: Any] {
                    setValue(try destinationClass.updateObject(withDictionary: relationshipDictionary, inContext: context), forKey: relationship.name)
                }
            }
        }
    }
}
