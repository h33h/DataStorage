//
//  NSRelationshipDescription+Extensions.swift
//
//
//  Created by Yauheni Fiadotau on 11.10.23.
//

import CoreData

extension NSRelationshipDescription {
    var deleteNotUpdated: Bool {
        guard let deleteNotUpdated = (userInfo?[DataStorageKey.deleteNotUpdated.rawValue] as? NSString)?.boolValue else { return destinationEntity?.uniqueName == nil }
        return deleteNotUpdated
    }
}
