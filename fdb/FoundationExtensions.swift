//
//  FoundationExtensions.swift
//  fdb
//
//  Created by Jason Jobe on 8/19/20.
//

import Foundation

public extension Calendar {
    enum Frequency: CaseIterable {
        case daily, weekly, biweekly,
             monthly, bimonthly, quarterly, yearly
        
        public var name: String { "\(self)" }
        public var step: Int { (self == .biweekly ? 2 : 1) }
        
        public static func named(_ name: String) -> Frequency? {
            Frequency.allCases.first(where: { $0.name == name })
        }
        
        public func nextDate(from date: Date?, in cal: Calendar = Calendar.current) -> Date? {
            guard let date = date else { return nil }
            var dateComponent = DateComponents()
            switch self {
//                case .once: return date
                case .daily: dateComponent.day = 1
                case .weekly: dateComponent.weekOfYear = 1
                case .biweekly: dateComponent.weekOfYear = 2
                case .monthly: dateComponent.month = 1
                case .bimonthly: dateComponent.month = 2
                case .quarterly: dateComponent.quarter = 1
                case .yearly: dateComponent.year = 1
            }
            return Calendar.current.date(byAdding: dateComponent, to: date)
        }
    }
}
