//
//  DataStorageContext.swift
//
//
//  Created by Yauheni Fiadotau on 8.10.23.
//

import CoreData

public extension NSManagedObjectContext {
    private struct NSManagedObjectContextAssociatedKeys {
        static var isReadOnly: UInt8 = 0
        static var deleteInvalidObjectsOnSave: UInt8 = 0
    }
    
    var isReadOnly: Bool {
        get { objc_getAssociatedObject(self, &NSManagedObjectContextAssociatedKeys.isReadOnly) as? Bool ?? false }
        set { objc_setAssociatedObject(self, &NSManagedObjectContextAssociatedKeys.isReadOnly, newValue, .OBJC_ASSOCIATION_ASSIGN) }
    }
    
    var deleteInvalidObjectsOnSave: Bool {
        get { objc_getAssociatedObject(self, &NSManagedObjectContextAssociatedKeys.deleteInvalidObjectsOnSave) as? Bool ?? true }
        set { objc_setAssociatedObject(self, &NSManagedObjectContextAssociatedKeys.deleteInvalidObjectsOnSave, newValue, .OBJC_ASSOCIATION_ASSIGN) }
    }
    
    convenience init(concurrencyType: NSManagedObjectContextConcurrencyType, isReadOnly: Bool = false, deleteInvalidObjectsOnSave: Bool = true) {
        self.init(concurrencyType: concurrencyType)
        self.isReadOnly = isReadOnly
        self.deleteInvalidObjectsOnSave = deleteInvalidObjectsOnSave
    }
    
    func performUpdateAndSave<T>(updateBlock: @escaping (_ context: NSManagedObjectContext) throws -> T, completion: @escaping (Result<T, Error>) -> Void) {
        perform {
            do {
                let result = try updateBlock(self)
                try self.save()
                completion(.success(result))
            } catch {
                completion(.failure(error))
            }
        }
    }

    func performUpdateAndWaitAndSave<T>(updateBlock: @escaping (_ context: NSManagedObjectContext) throws -> T, completion: @escaping (Result<T, Error>) -> Void) {
        performAndWait {
            do {
                let result = try updateBlock(self)
                try self.save()
                completion(.success(result))
            } catch {
                completion(.failure(error))
            }
        }
    }
    
    func existingObjects(withIds ids: [NSManagedObjectID]) throws -> [NSManagedObject] {
        try ids.map { try existingObject(with: $0) }
    }
    
    func existingObjects<T: NSManagedObject>(of type: T.Type, withIds ids: [NSManagedObjectID]) throws -> [T] {
        guard let objects = try existingObjects(withIds: ids) as? [T] else {
            throw DataStorageError.convertToConcreteTypeFail
        }
        return objects
    }
    
    func existingObject<T: NSManagedObject>(of type: T.Type, withId id: NSManagedObjectID) throws -> T {
        guard let objects = try existingObjects(withIds: [id]) as? [T] else {
            throw DataStorageError.convertToConcreteTypeFail
        }
        if let object =  objects.first {
            return object
        } else {
            throw DataStorageError.objectNotExist
        }
    }
    
    func existingObjectsT<T: NSManagedObject>(with objectIds: [NSManagedObjectID]) throws -> [T] {
        try existingObjects(of: T.self, withIds: objectIds)
    }
    
    func existingObjectT<T: NSManagedObject>(with objectId: NSManagedObjectID) throws -> T {
        try existingObject(of: T.self, withId: objectId)
    }
    
    func objectOrNil<T: NSManagedObject>(with objectId: NSManagedObjectID?) -> T? {
        guard let objectId else { return nil }
        return try? existingObjectT(with: objectId)
    }
    
    func objectsCount<T: NSManagedObject>(of type: T.Type, for config: DataStorageFRConfiguration = .init()) throws -> Int {
        let fetchRequest = T.createFetchRequest(with: config)
        return try count(for: fetchRequest)
    }
    
    func deleteObjects<T: NSManagedObject>(of type: T.Type, for config: DataStorageFRConfiguration = .init()) throws {
        let deleteRequest = T.createDeleteRequest(with: config)
        try execute(deleteRequest)
    }
    
    func objects<T: NSManagedObject>(of type: T.Type, with value: CVarArg, for key: String, includePendingChanges: Bool = true) throws -> [T] {
        try objectsSatisfying(of: T.self, [key: value], includePendingChanges: includePendingChanges)
    }
    
    func objects<T: NSManagedObject>(of type: T.Type, withPossibleValues values: [CVarArg], for key: String, includePendingChanges: Bool = true) throws -> [T] {
        let predicate = NSPredicate(format: "%K IN %@", key, values)
        let fetchRequest = T.createFetchRequest(with: .init(predicate: predicate))
        fetchRequest.includesPendingChanges = includePendingChanges
        if let objects = try fetch(fetchRequest) as? [T] {
            return objects
        } else {
            throw DataStorageError.convertToConcreteTypeFail
        }
    }
    
    func objectsSatisfying<T: NSManagedObject>(of type: T.Type, _ dict: [String: CVarArg], includePendingChanges: Bool = true) throws -> [T] {
        let predicates = dict.map { NSPredicate(format: "%K == %@", $0.key, $0.value) }
        let fetchRequest = T.createFetchRequest(with: .init(predicate: NSCompoundPredicate(andPredicateWithSubpredicates: predicates)))
        fetchRequest.includesPendingChanges = includePendingChanges
        if let objects = try fetch(fetchRequest) as? [T] {
            return objects
        } else {
            throw DataStorageError.convertToConcreteTypeFail
        }
    }
    
    func anyObject<T: NSManagedObject>(of type: T.Type) throws -> T {
        if let object = try fetch(T.createFetchRequest()).first {
            if let object = object as? T {
                return object
            } else {
                throw DataStorageError.convertToConcreteTypeFail
            }
        } else {
            throw DataStorageError.objectNotExist
        }
    }
    
    func copy<T: NSManagedObject>(_ object: T) -> T {
        let newObject = T(context: self)
            
        object.entity.attributesByName.forEach { key, _ in
            if let attributeValue = object.value(forKey: key) {
                newObject.setValue(attributeValue, forKey: key)
            }
        }
        
        object.entity.relationshipsByName.forEach { key, _ in
            if let relationshipValue = object.value(forKey: key) as? Set<NSManagedObject> {
                let newRelationshipSet = NSMutableSet()
                for relatedObject in relationshipValue {
                    let relatedCopy = copy(relatedObject)
                    newRelationshipSet.add(relatedCopy)
                }
                newObject.setValue(newRelationshipSet, forKey: key)
            } else if let relationshipValue = object.value(forKey: key) as? NSManagedObject {
                let relatedCopy = copy(relationshipValue)
                newObject.setValue(relatedCopy, forKey: key)
            }
        }
        return newObject
    }
    
    func deleteObjects(_ objects: [NSManagedObject]) {
        objects.forEach { delete($0) }
    }
    
    func saveChanges() throws {
        guard !isReadOnly else {
            throw DataStorageError.saveReadOnlyContextFail
        }
        guard hasChanges else { return }
        
        do {
            try save()
        } catch {
            if deleteInvalidObjectsOnSave {
                try deleteInvalidObjects(fromError: error)
                try saveChanges()
            } else {
                throw error
            }
        }
    }
    
    private func deleteInvalidObjects(fromError error: Error) throws {
        let errors = {
            let error = error as NSError
            if error.code == NSValidationMultipleErrorsError {
                return (error.userInfo[NSDetailedErrorsKey] as? [NSError])?.compactMap { $0 } ?? []
            } else {
                return [error]
            }
        }()
        
        try errors.forEach { error in
            switch error.code {
            case
                NSManagedObjectValidationError,
                NSManagedObjectConstraintValidationError,
                NSValidationMissingMandatoryPropertyError,
                NSValidationRelationshipLacksMinimumCountError,
                NSValidationRelationshipExceedsMaximumCountError,
                NSValidationRelationshipDeniedDeleteError,
                NSValidationNumberTooLargeError,
                NSValidationNumberTooSmallError,
                NSValidationDateTooLateError,
                NSValidationDateTooSoonError,
                NSValidationInvalidDateError,
                NSValidationStringTooLongError,
                NSValidationStringTooShortError,
                NSValidationStringPatternMatchingError,
                NSValidationInvalidURIError:
                if let object = error.userInfo[NSValidationObjectErrorKey] as? NSManagedObject, !object.isDeleted {
                    delete(object)
                } else {
                   throw error
                }
            default: throw error
            }
        }
    }
}
