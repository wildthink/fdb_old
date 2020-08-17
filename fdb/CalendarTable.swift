//
//  CalendarTable.swift
//  fdb
//
//  Created by Jason Jobe on 7/23/20.
//  Copyright © 2020 Jason Jobe. All rights reserved.
//
import Foundation
import CSQLite
import FeistyDB
import FeistyExtensions

final class CalendarModule: EponymousVirtualTableModule {
    
    var filter_info: FilterInfo = FilterInfo()
    
    enum Column: Int32, Comparable {
        static func < (lhs: CalendarModule.Column, rhs: CalendarModule.Column) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
        // CREATE TABLE x(date, weekday, day, week, month, year, start HIDDEN, stop HIDDEN, step HIDDEN)
        case date, weekday, day, week, month, year, start, stop, step
        var is_hidden: Bool { return self >= .start }
    }
    struct FilterInfo {
        var argv: [FilterArg] = []
        var isDescending: Bool = false
        
        func contains(_ col: Column) -> Bool {
            argv.contains(where: { $0.col_ndx == col} )
        }
    }
    
    struct FilterArg {
        var arg_ndx: Int32
        var col_ndx: Column
        var op: UInt8
    }
    
    var date_fmt: DateFormatter
    
    func destroy() throws {
    }
    
    convenience init(database: Database, arguments: [String]) throws {
        try self.init(database: database, arguments: arguments, create: false)
    }
    
    
    required init(database: Database, arguments: [String], create: Bool) throws {
        
        date_fmt = DateFormatter()
        date_fmt.dateFormat = "yyyy-MM-dd"
    }

    var declaration: String {
        "CREATE TABLE x(date, weekday, day, week, month, year, start HIDDEN, stop HIDDEN, step HIDDEN)"
    }

    var options: Database.VirtualTableModuleOptions {
        return [.innocuous]
    }
    
    func bestIndex(_ indexInfo: inout sqlite3_index_info) -> VirtualTableModuleBestIndexResult {
        filter_info = FilterInfo()
        
        // Inputs
        let constraintCount = Int(indexInfo.nConstraint)
        let constraints = UnsafeBufferPointer<sqlite3_index_constraint>(start: indexInfo.aConstraint, count: constraintCount)
        
        // Outputs
        //        let constraintUsage = UnsafeMutableBufferPointer<sqlite3_index_constraint_usage>(start: indexInfo.aConstraintUsage, count: constraintCount)
        
        var argc: Int32 = 1
        
        for i in 0 ..< constraintCount {
            let constraint = constraints[i]
            guard constraint.usable != 0 else { continue }
            guard let cndx = Column(rawValue: constraint.iColumn) else { return .constraint }
            guard cndx.is_hidden else { continue }
            guard constraint.op == SQLITE_INDEX_CONSTRAINT_EQ else { return .constraint }
            
            let farg = FilterArg(arg_ndx: argc - 1, col_ndx: cndx, op: constraint.op)
            filter_info.argv.append(farg)
            indexInfo.aConstraintUsage[i].argvIndex = argc
            indexInfo.aConstraintUsage[i].omit = 1
            argc += 1
        }
        
        let orderByCount = Int(indexInfo.nOrderBy)
        let orderBy = UnsafeBufferPointer<sqlite3_index_orderby>(start: indexInfo.aOrderBy, count: orderByCount)
        
        if orderByCount == 1 {
            if orderBy[0].desc == 1 {
                filter_info.isDescending = true
            }
            indexInfo.orderByConsumed = 1
        }
        
        if filter_info.contains(.start) && filter_info.contains(.stop) {
            indexInfo.estimatedCost = 2  - (filter_info.contains(.step) ? 1 : 0)
            indexInfo.estimatedRows = 1000
        }
        else {
            indexInfo.estimatedRows = 2147483647
        }
        //        indexInfo.idxNum = queryPlan.rawValue
        return .ok
    }
    
    func openCursor() -> VirtualTableCursor {
        return Cursor(self)
    }
}

private func cal_comp(from arg: String) -> (Int, Calendar.Component) {
    switch arg {
        case "day": return (1, .day)
        case "week": return (1, .weekOfYear)
        case "biweek": return (2, .weekOfYear)
        case "month": return (1, .month)
        case "year": return (1, .year)
        default:
            return (1, .day)
    }
}

private func cal_comp_str(_ count: Int, _ cc: Calendar.Component) -> String {
    switch (count, cc) {
        case (1, .day): return "day"
        case (1, .weekOfYear): return "week"
        case (2, .weekOfYear): return "biweek"
        case (1, .month): return "month"
        case (1, .year): return "year"
        default:
            return "<cal_comp>"
    }
}

extension CalendarModule {
    final class Cursor: VirtualTableCursor {
        
        let table: CalendarModule
        var calendar: Calendar
        var start: Date
        var end: Date
        var current: Date?
        
        var _rowid: Int64 = 0
        
        var stepUnits: Calendar.Component = .day
        var stepValue: Int = 1
        var date_fmt: DateFormatter { table.date_fmt }
        
        public init(_ table: CalendarModule)
        {
            self.table = table

            self.calendar = Calendar.current
            self.start = Date()
            self.end = .distantFuture
            self._rowid = 0
            self.current = start
        }

        func column(_ index: Int32) -> DatabaseValue {
            // "CREATE TABLE x(date, weekday, day, week, month, year, start, stop, step)"

            guard let date = current, let col = Column(rawValue: index) else { return .null }
            switch col {
                case .date:
                    return .text(date_fmt.string(from: date))
                case .weekday:
                    return .integer(Int64(calendar.component(.weekday, from: date)))
                case .day:
                    return .integer(Int64(calendar.component(.day, from: date)))
                case .week:
                    return .integer(Int64(calendar.component(.weekOfYear, from: date)))
                case .month:
                    return .integer(Int64(calendar.component(.month, from: date)))
                case .year:
                    return .integer(Int64(calendar.component(.year, from: date)))
                    
                //  HIDDEN
                case .start:
                    return .text(date_fmt.string(from: start))
                case .stop:
                    return .text(date_fmt.string(from: end))
                case .step:
                    return .text("\(cal_comp_str(stepValue, stepUnits))")
             }
        }
        
        func next() {
            _rowid += 1
            current = calendar.date(byAdding: stepUnits,
                                    value: stepValue,
                                    to: current ?? start,
                                    wrappingComponents: false)
        }
        
        func rowid() -> Int64 {
            _rowid
        }
        
        func filter(_ arguments: [DatabaseValue], indexNumber: Int32, indexName: String?) {
            _rowid = 1
            start = Date()
            end = .distantFuture
            stepValue = 1
            
            for farg in table.filter_info.argv {
                //                Swift.print(farg)
                switch (farg.col_ndx, arguments[Int(farg.arg_ndx)]) {
                    case (.start, let DatabaseValue.text(argv)): start  = date_fmt.date(from: argv) ?? start
                    case (.stop,  let DatabaseValue.text(argv)): end  = date_fmt.date(from: argv) ?? end
                    case (.step,  let DatabaseValue.text(argv)): (stepValue, stepUnits) = cal_comp(from: argv)
                    default:
                        break
                }
            }
            current = table.filter_info.isDescending ? end : start
        }
        
        var eof: Bool {
            // HARD LIMIT of total days for 1000 year span is 365_000
            if let date = current, date > end || _rowid > 365_000 {
                return true
            }
            return false
        }
    }
}
