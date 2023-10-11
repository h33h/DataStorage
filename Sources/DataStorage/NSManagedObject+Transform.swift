//
//  NSManagedObject+Transform.swift
//
//
//  Created by Yauheni Fiadotau on 9.10.23.
//

import CoreData

extension NSManagedObject {
    @objc open class func transformImportValue(_ value: Any, forAttribute attribute: NSAttributeDescription) -> Any {
        switch attribute.attributeType {
        case .URIAttributeType:
            if let value = value as? String, let url = NSURL(string: value) {
                return url
            }
        case .dateAttributeType:
            if let value = value as? String, let date = value.date as? NSDate {
                return date
            }
        default: break
        }
        return value
    }
    
    @objc open class func transformExportValue(_ value: Any?, forAttribute attribute: NSAttributeDescription) -> Any {
        switch attribute.attributeType {
        case .dateAttributeType: 
            if let value = value as? Date {
                return value.string
            }
        default: break
        }
        return value ?? NSNull()
    }
}
