//
//  DataStorage.swift
//
//
//  Created by Yauheni Fiadotau on 8.10.23.
//

import CoreData

public enum DataStorageError: Error {
    case dataModelNotFound
    case dataModelLoadFail
    case persistentStoreConnectionFail
}

public struct DataStorageConfiguration {
    public init(
        modelName: String = "Model",
        storeConfiguration: PersistentStoreConfiguration = .init(),
        allowStoreDropOnError: Bool = false
    ) {
        self.modelName = modelName
        self.storeConfiguration = storeConfiguration
        self.allowStoreDropOnError = allowStoreDropOnError
    }
    
    public var modelName: String
    public var storeConfiguration: PersistentStoreConfiguration
    public var allowStoreDropOnError: Bool
}

public struct PersistentStoreConfiguration {
    public enum StoreType {
        case sqlite
        case inMemory
        
        var storeType: String {
            switch self {
            case .sqlite: return NSSQLiteStoreType
            case .inMemory: return NSInMemoryStoreType
            }
        }
    }
    
    public init(
        storeType: StoreType = .sqlite,
        configurationName: String? = nil,
        storeURL: URL? = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).last?.appendingPathComponent("DataStorage.sqlite"),
        options: [String : Any]? = [
            NSMigratePersistentStoresAutomaticallyOption : true,
            NSInferMappingModelAutomaticallyOption : true
        ]
    ) {
        self.storeType = storeType
        self.configurationName = configurationName
        self.storeURL = storeURL
        self.options = options
    }
    
    public var storeType: StoreType
    public var configurationName: String?
    public var storeURL: URL?
    public var options: [String: Any]?
}

public struct DataStorageFRConfiguration {
    public init(
        sortDescriptors: [NSSortDescriptor] = [],
        predicate: NSPredicate? = nil,
        limit: Int = .zero
    ) {
        self.sortDescriptors = sortDescriptors
        self.predicate = predicate
        self.limit = limit
    }
    
    var sortDescriptors: [NSSortDescriptor]
    var predicate: NSPredicate?
    var limit: Int
}

open class BaseDataStorage {
    private let storeConfiguration: PersistentStoreConfiguration
    
    public let persistentStoreCoordinator: NSPersistentStoreCoordinator
    
    public private(set) lazy var mainContext: NSManagedObjectContext = {
        let mainContext = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType, isReadOnly: true)
        mainContext.persistentStoreCoordinator = persistentStoreCoordinator
        mainContext.automaticallyMergesChangesFromParent = true
        return mainContext
    }()
    
    public private(set) lazy var writeContext: NSManagedObjectContext = {
        let writeContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        writeContext.persistentStoreCoordinator = persistentStoreCoordinator
        writeContext.automaticallyMergesChangesFromParent = true
        return writeContext
    }()
    
    public init(configuration: DataStorageConfiguration) throws {
        guard let modelURL = Bundle.main.url(forResource: configuration.modelName, withExtension: "momd") else {
            throw DataStorageError.dataModelNotFound
        }
        guard let managedObjectModel = NSManagedObjectModel(contentsOf: modelURL) else {
            throw DataStorageError.dataModelLoadFail
        }
        
        storeConfiguration = configuration.storeConfiguration
        persistentStoreCoordinator = .init(managedObjectModel: managedObjectModel)
        
        do {
            try connectPersistentStore(with: configuration.storeConfiguration)
        } catch {
            if configuration.allowStoreDropOnError, let storeURL = configuration.storeConfiguration.storeURL {
                try FileManager.default.removeItem(at: storeURL)
                try connectPersistentStore(with: storeConfiguration)
            } else {
                throw DataStorageError.persistentStoreConnectionFail
            }
        }
    }
    
    private func connectPersistentStore(with configuration: PersistentStoreConfiguration) throws {
        try persistentStoreCoordinator.addPersistentStore(
            ofType: configuration.storeType.storeType,
            configurationName: configuration.configurationName,
            at: configuration.storeURL,
            options: configuration.options)
    }
    
    public func deleteAllData() throws {
        guard let storeURL = storeConfiguration.storeURL else { return }
        try persistentStoreCoordinator.destroyPersistentStore(at: storeURL, ofType: storeConfiguration.storeType.storeType)
        mainContext.reset()
        writeContext.reset()
        try connectPersistentStore(with: storeConfiguration)
    }
    
    public func createNewContext(concurrencyType: NSManagedObjectContextConcurrencyType = .privateQueueConcurrencyType, isReadOnly: Bool = false, deleteInvalidObjectsOnSave: Bool = true) -> NSManagedObjectContext {
        let context = NSManagedObjectContext(concurrencyType: concurrencyType, isReadOnly: isReadOnly, deleteInvalidObjectsOnSave: deleteInvalidObjectsOnSave)
        context.persistentStoreCoordinator = persistentStoreCoordinator
        return context
    }
    
    public func createFetchRequest<T: NSManagedObject>(of type: T.Type, with config: DataStorageFRConfiguration = .init()) -> NSFetchRequest<T> {
        let fetchRequest = T.fetchRequest()
        fetchRequest.predicate = config.predicate
        fetchRequest.sortDescriptors = config.sortDescriptors
        fetchRequest.fetchLimit = config.limit
        return fetchRequest as! NSFetchRequest<T>
    }
    
    public func createDeleteRequest<T: NSManagedObject>(of type: T.Type, with config: DataStorageFRConfiguration = .init()) -> NSBatchDeleteRequest {
        .init(fetchRequest: createFetchRequest(of: type, with: config) as! NSFetchRequest<NSFetchRequestResult>)
    }
    
    public func objectsCount<T: NSManagedObject>(of type: T.Type, for config: DataStorageFRConfiguration = .init(), inContext context: NSManagedObjectContext, completion: @escaping (Result<Int, Error>) -> Void) {
        context.perform {
            do {
                completion(.success(try self.objectsCount(of: type, for: config, inContext: context)))
            } catch {
                completion(.failure(error))
            }
        }
    }
    
    public func deleteObjects<T: NSManagedObject>(of type: T.Type, for config: DataStorageFRConfiguration = .init(), inContext context: NSManagedObjectContext, completion: @escaping (Result<Void, Error>) -> Void) {
        context.performUpdateAndSave(updateBlock: { context in
            do {
                completion(.success(try self.deleteObjects(of: type, for: config, inContext: context)))
            } catch {
                completion(.failure(error))
            }
        }, completion: completion)
    }
    
    public func objects<T: NSManagedObject>(of type: T.Type, with value: CVarArg, for key: String, includePendingChanges: Bool = true, inContext context: NSManagedObjectContext, completion: @escaping (Result<[T], Error>) -> Void) {
        context.perform {
            do {
                completion(.success(try self.objects(of: type, with: value, for: key, includePendingChanges: includePendingChanges, inContext: context)))
            } catch {
                completion(.failure(error))
            }
        }
    }
    
    public func objects<T: NSManagedObject>(of type: T.Type, withPossibleValues values: [CVarArg], for key: String, includePendingChanges: Bool = true, inContext context: NSManagedObjectContext, completion: @escaping (Result<[T], Error>) -> Void) {
        context.perform {
            do {
                completion(.success(try self.objects(of: type, withPossibleValues: values, for: key, includePendingChanges: includePendingChanges, inContext: context)))
            } catch {
                completion(.failure(error))
            }
        }
    }
    
    public func objectsSatisfying<T: NSManagedObject>(of type: T.Type, _ dict: [String: CVarArg], includePendingChanges: Bool = true, inContext context: NSManagedObjectContext, completion: @escaping (Result<[T], Error>) -> Void) {
        context.perform {
            do {
                completion(.success(try self.objectsSatisfying(of: type, dict, includePendingChanges: includePendingChanges, inContext: context)))
            } catch {
                completion(.failure(error))
            }
        }
    }
    
    public func anyObject<T: NSManagedObject>(of type: T.Type, inContext context: NSManagedObjectContext, completion: @escaping (Result<T?, Error>) -> Void) {
        context.perform {
            do {
                completion(.success(try self.anyObject(of: type, inContext: context)))
            } catch {
                completion(.failure(error))
            }
        }
    }
    
    public func copy<T: NSManagedObject>(_ object: T, in context: NSManagedObjectContext, completion: @escaping (T?) -> Void) {
        context.perform {
            completion(self.copy(object, in: context))
        }
    }
    
    public func updateObjects<T: NSManagedObject>(of type: T.Type, withArrayOfDictionaries arrayOfDicts: [[String: Any]], inContext context: NSManagedObjectContext, completion: @escaping ([T]) -> Void) {
        context.perform {
            completion(self.updateObjects(of: type, withArrayOfDictionaries: arrayOfDicts, inContext: context))
        }
    }
    
    public func updateObject<T: NSManagedObject>(of type: T.Type, withDictionary dict: [String: Any], inContext context: NSManagedObjectContext, completion: @escaping (T) -> Void) {
        context.perform {
            completion(self.updateObject(of: type, withDictionary: dict, inContext: context))
        }
    }
    
    public func update<T: NSManagedObject>(_ object: T, withDictionary dict: [String: Any], inContext context: NSManagedObjectContext, completion: @escaping () -> Void) {
        context.perform {
            self.update(object, withDictionary: dict, inContext: context)
            completion()
        }
    }
}
