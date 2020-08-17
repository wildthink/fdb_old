//
//  CalendarVTable.swift
//  fdb
//
//  Created by Jason Jobe on 8/17/20.
//

import Foundation
import CSQLite
import FeistyDB


final class SeriesModule: EponymousVirtualTableModule {
    
    var filter_info: FilterInfo = FilterInfo()
    
    enum Column: Int32 {
        case value, start, stop, step
        var is_hidden: Bool { return self != .value }
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

extension SeriesModule {
    final class Cursor: VirtualTableCursor {
        
        let module: SeriesModule
        var _rowid: Int64 = 0
        var _value: Int64 = 0
        var _min: Int64 = 0
        var _max: Int64 = 0
        var _step: Int64 = 0
        var isDescending: Bool { module.filter_info.isDescending }
        
        init(_ module: SeriesModule) {
            self.module = module
        }
        
        func column(_ index: Int32) -> DatabaseValue {
            let col = Column(rawValue: index)
            switch col {
                case .value: return .integer(_value)
                case .start: return .integer(_min)
                case .stop:  return .integer(_max)
                case .step:  return .integer(_step)
                default:     return nil
            }
        }
        
        func next() {
            _value += (isDescending ? -_step : _step)
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
            
            for farg in module.filter_info.argv {
                //                Swift.print(farg)
                switch (farg.col_ndx, arguments[Int(farg.arg_ndx)]) {
                    case (.start, let DatabaseValue.integer(argv)): _min  = argv
                    case (.stop,  let DatabaseValue.integer(argv)): _max  = argv
                    case (.step,  let DatabaseValue.integer(argv)): _step = argv
                    default:
                        break
                }
            }
            
            if arguments.contains(where: { return $0 == .null ? true : false }) {
                _min = 1
                _max = 0
            }
            
            _value = isDescending ? _max : _min
            if isDescending && _step > 0 {
                _value -= (_max - _min) % _step
            }
        }
        
        var eof: Bool {
            isDescending ? (_value < _min) : (_value > _max)
        }
    }
}
