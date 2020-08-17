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
   
    var start: Date = Date() // now
    var end: Date = .distantFuture
    var stepUnits: Calendar.Component = .day
    var stepValue: Int = 1
    
    var date_fmt: DateFormatter

    func destroy() throws {
    }

    convenience init(database: Database, arguments: [String]) throws {
        try self.init(database: database, arguments: arguments, create: false)
    }
    

    required init(database: Database, arguments: [String], create: Bool) throws {

        date_fmt = DateFormatter()
        date_fmt.dateFormat = "yyyy-MM-dd"
        
        // FIXME: raise w/ bad or missing date values
        for (ndx, arg) in arguments.suffix(from: 3).enumerated() {
            switch ndx {
                case 0: start = date_fmt.date(from: arg) ?? Date()
                case 1: end = date_fmt.date(from: arg) ?? .distantFuture
                case 2: (stepValue, stepUnits) = cal_comp(from: arg) ?? (1, .day)
                default:
                    //  throw SQLiteError("Missing value for stop", code: SQLITE_ERROR)
                    break
            }
//            throw SQLiteError("Missing value for stop", code: SQLITE_ERROR)
        }

    }
    
//    open var columns: [Column] = []
    // "CREATE TABLE x(date, weekday, day, week, month, year, start HIDDEN, stop HIDDEN, step HIDDEN)"
    //    }

    lazy var columns: [Column] = {
        var cols:[Column] = [
            .column("date", .text),
            .column("weekday", .int),
            .column("day", .int),
            .column("week", .int),
            .column("month", .int),
            .column("year", .int),
            .hidden("start", .text),
            .hidden("stop", .text),
            .hidden("step", .text)
        ]
        for ndx in 0..<cols.count {
            cols[ndx].ndx = ndx
        }
        return cols
    }()

    lazy public var declaration: String = {
        var str: String = "CREATE TABLE x("
        for col in columns {
            Swift.print("\t\(col.declaration)", separator: "", terminator: "", to: &str)
            if col != columns.last {
                Swift.print(",\n", separator: "", terminator: "", to: &str)
            }
        }
        Swift.print("\n)", separator: "", terminator: "", to: &str)
        return str
    }()

//    var declaration: String {
//        "CREATE TABLE x(date, weekday, day, week, month, year, start HIDDEN, stop HIDDEN, step HIDDEN)"
//    }
    
    var options: Database.VirtualTableModuleOptions {
        [.innocuous]
    }
    
    func bestIndex(_ indexInfo: inout sqlite3_index_info) -> VirtualTableModuleBestIndexResult {
        // Inputs
        let constraintCount = Int(indexInfo.nConstraint)
        let constraints = UnsafeBufferPointer<sqlite3_index_constraint>(start: indexInfo.aConstraint, count: constraintCount)
        
        // Outputs
        let constraintUsage = UnsafeMutableBufferPointer<sqlite3_index_constraint_usage>(start: indexInfo.aConstraintUsage, count: constraintCount)
        
//        var queryPlan = QueryPlanOption()
//        _ = QueryPlanOption.all // force Info[] population
        
        var argv: [VTabConstraint] = []
        
        var count = 0
        for constraint in constraints where constraint.usable != 0 {
            let col = constraint.iColumn
            let arg = VTabConstraint(col: Int(col), ndx: count, op: constraint.op)
            argv.append(arg)
            count += 1
//            let opt = QueryPlanOption(index: ndx)
//            //            Swift.print("plan union", opt.info)
//            queryPlan = queryPlan.union(opt)
        }
        Swift.print(#line, argv)
        for arg in argv {
            constraintUsage[arg.ndx].argvIndex = Int32(arg.ndx + 1)
        }
//        for (ndx, col) in queryPlan.elements().enumerated() {
//            //            Swift.print("usage", ndx, col.info)
//            constraintUsage[col.index - 1].argvIndex = Int32(ndx + 1)
//        }
        //        Swift.print (#line, queryPlan)
        
//        if queryPlan.contains(.start) && queryPlan.contains(.stop) {
//            // Lower the cost if we also have step
//            indexInfo.estimatedCost = 2  - (queryPlan.contains(.step) ? 1 : 0)
//            indexInfo.estimatedRows = 1000
//
//            // ORDER BY
//            if indexInfo.nOrderBy == 1 {
//                if indexInfo.aOrderBy[0].desc == 1 {
//                    queryPlan = queryPlan.union(.descending)
//                }
                indexInfo.orderByConsumed = 1
//            }
//        }
//        else {
            indexInfo.estimatedRows = 2147483647
//        }
        // Passed to filter()
        //        indexInfo.idxStr =
//        indexInfo.idxNum = queryPlan.rawValue
        
        return .ok
    }
    
    func openCursor() -> VirtualTableCursor {
        Cursor(self, calendar: Calendar.current,
               start: start, end: end, stepUnits: stepUnits, stepValue: stepValue)
    }
}

func cal_comp(from arg: String) -> (Int, Calendar.Component)? {
    switch arg {
        case "day": return (1, .day)
        case "week": return (1, .weekOfYear)
        case "biweek": return (2, .weekOfYear)
        case "month": return (1, .month)
        case "year": return (1, .year)
        default:
            return nil
    }
}

extension CalendarModule {
    final class Cursor: VirtualTableCursor {
        
        let table: CalendarModule
        var calendar: Calendar
        var start: Date
        var end: Date
        var current: Date?
        var stepUnits: Calendar.Component
        var stepValue: Int

        var _rowid: Int64 = 0
        
        var date_fmt: DateFormatter { table.date_fmt }

//        init(_ table: CalendarModule) {
//            self.table = table
//        }
        
        public init(_ table: CalendarModule,
                    calendar: Calendar, start: Date, end: Date,
                    stepUnits: Calendar.Component, stepValue: Int = 1)
        {
            self.table = table

            self.calendar = calendar
            self.start = start
            self.end = end
            self.stepUnits = stepUnits
            self.stepValue = stepValue
            self._rowid = 0
            self.current = start
        }

        func column(_ index: Int32) -> DatabaseValue {
            // "CREATE TABLE x(date, weekday, day, week, month, year, start, stop, step)"

            guard let date = current else { return .null }
            switch index {
                case 0: // date
                    return .text(date_fmt.string(from: date))
                case 1: // weekday
                    return .integer(Int64(calendar.component(.weekday, from: date)))
                case 2: // day
                    return .integer(Int64(calendar.component(.day, from: date)))
                case 3: // week
                    return .integer(Int64(calendar.component(.weekOfYear, from: date)))
                case 4: // month
                    return .integer(Int64(calendar.component(.month, from: date)))
                case 5: // year
                    return .integer(Int64(calendar.component(.year, from: date)))
                    
                //  start, stop, step
                case 6:
                    return .text(date_fmt.string(from: start))
                case 7:
                    return .text(date_fmt.string(from: end))
                case 8:
                    return .text("\(stepUnits)")

                default:
                    return .text(date_fmt.string(from: date))
            }
        }
        
        func next() {
            guard !eof else { return }
            defer { _rowid += 1 }
            guard _rowid != 0 else { return }

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
        }
        
        var eof: Bool {
            // HARD LIMIT of 1000 year span 365_000
            if let date = current, date > end || _rowid > 365_00 {
                return true
            }
            return false
        }
    }
}

struct VTabConstraint {
    let col: Int
    let ndx: Int
    let op: UTF8Char
}
