//
//  Date+Extensions.swift
//
//
//  Created by Yauheni Fiadotau on 9.10.23.
//

import Foundation

public extension Date {
    static func date(fromISO8601String dateString: String) -> Date? {
        guard !dateString.isEmpty else { return nil }
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        return formatter.date(from: dateString)
    }
    
    static func date(fromUnixTimestampString unixTimestamp: String) -> Date? {
        guard !unixTimestamp.isEmpty else { return nil }
        
        let parsedString: String
        let validLength = 10
        
        if unixTimestamp.count > validLength {
            parsedString = String(unixTimestamp[..<unixTimestamp.index(unixTimestamp.startIndex, offsetBy: validLength)])
        } else {
            parsedString = unixTimestamp
        }
        
        if let unixTimestampNumber = Double(parsedString) {
            return Date(timeIntervalSince1970: unixTimestampNumber)
        }
        
        return nil
    }
}

public extension String {
    var date: Date? {
        switch dateType {
        case .iso8601: return .date(fromISO8601String: self)
        case .unixTimestamp: return .date(fromUnixTimestampString: self)
        }
    }
}

private extension String {
    var dateType: DateType { contains("-") ? .iso8601 : .unixTimestamp }
}

private enum DateType {
    case iso8601
    case unixTimestamp
}
