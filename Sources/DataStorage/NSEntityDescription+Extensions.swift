//
//  NSEntityDescription+Extensions.swift
//
//
//  Created by Yauheni Fiadotau on 9.10.23.
//

import CoreData

extension NSEntityDescription {
    var attributes: [NSAttributeDescription] { attributesByName.map { $0.value } }
    
    var relationships: [NSRelationshipDescription] { relationshipsByName.map { $0.value } }
    
    var uniqueName: String? {
        guard let uniqueKeyValue = userInfo?[DataStorageKey.uniqueKey] as? String else { return nil }
        return uniqueKeyValue
    }
    
    var uniqueAttribute: NSAttributeDescription? {
        guard let uniqueName else { return nil }
        return attributes.first { $0.name == uniqueName }
    }
}
