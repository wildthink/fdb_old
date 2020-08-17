//
//  CalendarVTable.swift
//  fdb
//
//  Created by Jason Jobe on 8/17/20.
//

import Foundation
import CSQLite
import FeistyDB
//import FeistyExtensions


final class SeriesModule: EponymousVirtualTableModule {
    
//    var fargv: [FilterArg] = []
    var filter_info: FilterInfo = FilterInfo()
    
    enum ColumnNdx: Int32 {
        case value, start, stop, step
        var is_hidden: Bool { return self != .value }
    }
    struct FilterInfo {
        var argv: [FilterArg] = []
        var isDescending: Bool = false
    }
    
    struct QueryPlan: OptionSet {
        let rawValue: Int32
        static let start = QueryPlan(rawValue: 1 << 0)
        static let stop = QueryPlan(rawValue: 1 << 1)
        static let step = QueryPlan(rawValue: 1 << 2)
        static let isDescending = QueryPlan(rawValue: 1 << 3)
    }
    
    struct FilterArg {
        var arg_ndx: Int32
        var col_ndx: ColumnNdx
        var op: UInt8
    }
    
    final class Cursor: VirtualTableCursor {
        typealias Value = Int64
        let module: SeriesModule
        var _rowid: Value = 0
        var _value: Value = 0
        var _min: Value = 0
        var _max: Value = 0
        var _step: Value = 0
        var _isDescending = false
        
        init(_ module: SeriesModule) {
            self.module = module
        }

        func column(_ index: Int32) -> DatabaseValue {
            let col = ColumnNdx(rawValue: index)
            switch col {
                case .value: return .integer(_value)
                case .start: return .integer(_min)
                case .stop:  return .integer(_max)
                case .step:  return .integer(_step)
                default:     return nil
            }
        }
        
        func next() {
            _value += (_isDescending ? -_step : _step)
            _rowid += 1
        }
        
        func rowid() -> Int64 {
            return _rowid
        }
        
        func filter(_ arguments: [DatabaseValue], indexNumber: Int32, indexName: String?) {
            _rowid = 1
            _min = 0
            _max = 0xffffffff
            _step = 1
            
            // debug
            for farg in module.filter_info.argv {
//                guard case let DatabaseValue.integer(argv) = arguments[Int(farg.arg_ndx)]
//                else { continue }
                Swift.print(farg)
                switch (farg.col_ndx, arguments[Int(farg.arg_ndx)]) {
                    case (.start, let DatabaseValue.integer(argv)): _min  = argv
                    case (.stop,  let DatabaseValue.integer(argv)): _max  = argv
                    case (.step,  let DatabaseValue.integer(argv)): _step = argv
//                        break
//                    case .start: _min = argv
//                    case .stop: _max = argv
//                    case .step: _step = argv
                    default:
                        break
                }
            }

            let queryPlan = QueryPlan(rawValue: indexNumber)
/*            var argumentNumber = 0
            if queryPlan.contains(.start) {
                if case let .integer(i) = arguments[argumentNumber] {
                    _min = i
                }
                argumentNumber += 1
            }
            
            if queryPlan.contains(.stop) {
                if case let .integer(i) = arguments[argumentNumber] {
                    _max = i
                }
                argumentNumber += 1
            }
            
            if queryPlan.contains(.step) {
                if case let .integer(i) = arguments[argumentNumber] {
                    _step = max(i, 1)
                }
                argumentNumber += 1
            }
            */
            if arguments.contains(where: { return $0 == .null ? true : false }) {
                _min = 1
                _max = 0
            }

            _isDescending = queryPlan.contains(.isDescending)
            _value = _isDescending ? _max : _min
            if _isDescending && _step > 0 {
                _value -= (_max - _min) % _step
            }
        }
        
        var eof: Bool {
            _isDescending ? (_value < _min) : (_value > _max)
        }
    }
    
    required init(database: Database, arguments: [String]) {
    }

    var declaration: String {
        "CREATE TABLE x(value,start hidden,stop hidden,step hidden)"
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
        let constraintUsage = UnsafeMutableBufferPointer<sqlite3_index_constraint_usage>(start: indexInfo.aConstraintUsage, count: constraintCount)
        
        var queryPlan: QueryPlan = []
        
        var filterArgumentCount: Int32 = 1
        
        for i in 0 ..< constraintCount {
            let constraint = constraints[i]
            guard constraint.usable != 0 else { continue }
            guard let cndx = ColumnNdx(rawValue: constraint.iColumn) else { return .constraint }
            guard cndx.is_hidden else { continue }
            guard constraint.op == SQLITE_INDEX_CONSTRAINT_EQ else { return .constraint }

            let farg = FilterArg(arg_ndx: filterArgumentCount - 1, col_ndx: cndx, op: constraint.op)
            filter_info.argv.append(farg)

            switch cndx {
                case .start:
                    queryPlan.insert(.start)
                    constraintUsage[i].argvIndex = filterArgumentCount
                    filterArgumentCount += 1
                    
                case .stop:
                    queryPlan.insert(.stop)
                    constraintUsage[i].argvIndex = filterArgumentCount
                    filterArgumentCount += 1
                    
                case .step:
                    queryPlan.insert(.step)
                    constraintUsage[i].argvIndex = filterArgumentCount
                    filterArgumentCount += 1
                    
                // Appease the compiler but we never should get here w/ is_hidden check
                case .value:
                    break
            }
        }
        
        let orderByCount = Int(indexInfo.nOrderBy)
        let orderBy = UnsafeBufferPointer<sqlite3_index_orderby>(start: indexInfo.aOrderBy, count: orderByCount)
        
        if orderByCount == 1 {
            if orderBy[0].desc == 1 {
                filter_info.isDescending = true
                queryPlan.insert(.isDescending)
            }
            indexInfo.orderByConsumed = 1
        }

        if queryPlan.contains(.start) && queryPlan.contains(.stop) {
            indexInfo.estimatedCost = 2  - (queryPlan.contains(.step) ? 1 : 0)
            indexInfo.estimatedRows = 1000
            
//            let orderByCount = Int(indexInfo.nOrderBy)
//            let orderBy = UnsafeBufferPointer<sqlite3_index_orderby>(start: indexInfo.aOrderBy, count: orderByCount)
//
//            if orderByCount == 1 {
//                if orderBy[0].desc == 1 {
//                    queryPlan.insert(.isDescending)
//                }
//                indexInfo.orderByConsumed = 1
//            }
        }
        else {
            indexInfo.estimatedRows = 2147483647
        }
        
        indexInfo.idxNum = queryPlan.rawValue
        
        return .ok
    }
    
    func openCursor() -> VirtualTableCursor {
        return Cursor(self)
    }
}
