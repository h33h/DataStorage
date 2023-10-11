//
//  NSManagedObject+Export.swift
//
//
//  Created by Yauheni Fiadotau on 11.10.23.
//

import CoreData

public extension NSManagedObject {
    func exportDictionary() -> [String: Any] { exportDictionary(parentEntityDescription: nil) }
    
    private func exportDictionary(parentEntityDescription: NSEntityDescription?) -> [String: Any] {
        var result = exportAttributesDictionary()
        result.merge(exportRelationshipsDictionary(parentEntityDescription: parentEntityDescription)) { (current, _) in current }
        return result
    }

    private func exportAttributesDictionary() -> [String: Any] {
        entity.attributes.reduce(into: [String: Any]()) { result, attribute in
            guard attribute.canExport else { return }
            result[attribute.exportName] = Self.transformExportValue(value(forKey: attribute.name), forAttribute: attribute)
        }
    }

    private func exportRelationshipsDictionary(parentEntityDescription: NSEntityDescription?) -> [String: Any] {
        entity.relationships.reduce(into: [String: Any]()) { result, relationship in
            guard relationship.canExport, relationship.destinationEntity != parentEntityDescription else { return }
            if relationship.isToMany {
                if relationship.isOrdered {
                    if let objects = (value(forKey: relationship.name) as? NSOrderedSet)?.array as? [NSManagedObject] {
                        result[relationship.exportName] = objects.map { $0.exportDictionary(parentEntityDescription: entity) }
                    }
                } else if let objects = (value(forKey: relationship.name) as? NSSet)?.allObjects as? [NSManagedObject] {
                    result[relationship.exportName] = objects.map { $0.exportDictionary(parentEntityDescription: entity) }
                }
            } else if let object = value(forKey: relationship.name) as? NSManagedObject {
                result[relationship.exportName] = object.exportDictionary(parentEntityDescription: entity)
            }
        }
    }
}

