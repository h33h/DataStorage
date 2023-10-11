//
//  DataStorage.swift
//
//
//  Created by Yauheni Fiadotau on 8.10.23.
//

import CoreData

public enum DataStorageError: String, LocalizedError {
    case dataModelNotFound
    case dataModelLoadFail
    case persistentStoreConnectionFail
    case convertToConcreteTypeFail
    case saveReadOnlyContextFail
    case objectNotExist
    case uniqueKeyMustBeHashable
    case importUniqueKeyMustBeCVarArg
    case relationshipHaveNoDestinationEntity
    
    public var errorDescription: String? { rawValue }
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
        mainContext.performAndWait {
            mainContext.reset()
        }
        writeContext.performAndWait {
            writeContext.reset()
        }
        try persistentStoreCoordinator.destroyPersistentStore(at: storeURL, ofType: storeConfiguration.storeType.storeType)
        try connectPersistentStore(with: storeConfiguration)
    }
    
    public func createNewContext(concurrencyType: NSManagedObjectContextConcurrencyType = .privateQueueConcurrencyType, isReadOnly: Bool = false, deleteInvalidObjectsOnSave: Bool = true) -> NSManagedObjectContext {
        let context = NSManagedObjectContext(concurrencyType: concurrencyType, isReadOnly: isReadOnly, deleteInvalidObjectsOnSave: deleteInvalidObjectsOnSave)
        context.persistentStoreCoordinator = persistentStoreCoordinator
        return context
    }
}
