//
//  NSPropertyDescription+Extensions.swift
//
//
//  Created by Yauheni Fiadotau on 9.10.23.
//

import CoreData

enum DataStorageKey: String {
    case uniqueKey
    case importKey
    case exportKey
    case nonExportable
    case deleteNotUpdated
}

extension NSPropertyDescription {
    var importName: String {
        guard let importKeyValue = userInfo?[DataStorageKey.importKey] as? String else { return name }
        return importKeyValue
    }
    
    var exportName: String {
        guard let customExportKey = userInfo?[DataStorageKey.exportKey] as? String else { return name }
        return customExportKey
    }
    
    var canExport: Bool {
        guard let nonExportable = (userInfo?[DataStorageKey.nonExportable] as? NSString)?.boolValue else { return true }
        return !nonExportable
    }
}

extension NSRelationshipDescription {
    var deleteNotUpdated: Bool {
        guard let deleteNotUpdated = (userInfo?[DataStorageKey.deleteNotUpdated] as? NSString)?.boolValue else { return false }
        return deleteNotUpdated
    }
}
