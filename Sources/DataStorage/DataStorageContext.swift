//
//  DataStorageContext.swift
//
//
//  Created by Yauheni Fiadotau on 8.10.23.
//

import CoreData

public enum DataStorageContextError: Error {
    case convertToConcreteTypeFail
    case saveReadOnlyContextFail
    case notFoundObject
}

public extension NSManagedObjectContext {
    struct Holder {
        static var _isReadOnly: Bool = false
        static var _deleteInvalidObjectsOnSave: Bool = false
    }
    
    var isReadOnly: Bool {
        get { Holder._isReadOnly }
        set { Holder._isReadOnly = newValue }
    }
    
    var deleteInvalidObjectsOnSave: Bool {
        get { Holder._deleteInvalidObjectsOnSave }
        set { Holder._deleteInvalidObjectsOnSave = newValue }
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
        guard let objects = try existingObjects(withIds: ids) as? [T] else { throw DataStorageContextError.convertToConcreteTypeFail }
        return objects
    }
    
    func existingObject<T: NSManagedObject>(of type: T.Type, withId id: NSManagedObjectID) throws -> T {
        guard let objects = try existingObjects(withIds: [id]) as? [T] else { throw DataStorageContextError.convertToConcreteTypeFail }
        if let object =  objects.first {
            return object
        } else {
            throw DataStorageContextError.notFoundObject
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
    
    func deleteObjects(_ objects: [NSManagedObject]) {
        objects.forEach { delete($0) }
    }
    
    func saveChanges() throws {
        guard !isReadOnly else { throw DataStorageContextError.saveReadOnlyContextFail }
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
                return [error.userInfo[NSDetailedErrorsKey] as? NSError].compactMap { $0 }
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
