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

public class DataStorageContext: NSManagedObjectContext {
    public let isReadOnly: Bool
    public let deleteInvalidObjectsOnSave: Bool
    
    public init(concurrencyType: NSManagedObjectContextConcurrencyType, isReadOnly: Bool = false, deleteInvalidObjectsOnSave: Bool = true) {
        self.isReadOnly = isReadOnly
        self.deleteInvalidObjectsOnSave = deleteInvalidObjectsOnSave
        super.init(concurrencyType: concurrencyType)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func performUpdateAndSave<T>(updateBlock: @escaping (_ context: NSManagedObjectContext) throws -> T, completion: @escaping (Result<T, Error>) -> Void) {
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

    public func performUpdateAndWaitAndSave<T>(updateBlock: @escaping (_ context: NSManagedObjectContext) throws -> T, completion: @escaping (Result<T, Error>) -> Void) {
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
    
    public func existingObjects(withIds ids: [NSManagedObjectID]) throws -> [NSManagedObject] {
        try ids.map { try existingObject(with: $0) }
    }
    
    public func existingObjects<T: NSManagedObject>(of type: T.Type, withIds ids: [NSManagedObjectID]) throws -> [T] {
        guard let objects = try existingObjects(withIds: ids) as? [T] else { throw DataStorageContextError.convertToConcreteTypeFail }
        return objects
    }
    
    public func existingObject<T: NSManagedObject>(of type: T.Type, withId id: NSManagedObjectID) throws -> T {
        guard let objects = try existingObjects(withIds: [id]) as? [T] else { throw DataStorageContextError.convertToConcreteTypeFail }
        if let object =  objects.first {
            return object
        } else {
            throw DataStorageContextError.notFoundObject
        }
    }
    
    public func deleteObjects(_ objects: [NSManagedObject]) {
        objects.forEach { delete($0) }
    }
    
    public override func save() throws {
        guard !isReadOnly else { throw DataStorageContextError.saveReadOnlyContextFail }
        guard hasChanges else { return }
        
        do {
            try super.save()
        } catch {
            if deleteInvalidObjectsOnSave {
                try deleteInvalidObjects(fromError: error)
                try save()
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
