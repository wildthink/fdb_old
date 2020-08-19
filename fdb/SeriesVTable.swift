//
//  CalendarVTable.swift
//  fdb
//
//  Created by Jason Jobe on 8/17/20.
//

import Foundation
import CSQLite
import FeistyDB


final class SeriesModule: VirtualTableModule {

    enum Column: Int32, ColumnIndex, CaseIterable {
        case value, start, stop, step
    }

    init(database: Database, arguments: [String], create: Bool) throws {
        Swift.print (#function, arguments)
    }

    var filters: [FilterInfo] = []
    
    func add(_ filter: inout FilterInfo) -> Int32 {
        filter.key = Int32(filters.count)
        filters.append(filter)
        return filter.key
    }
    func clearFilters() {
        filters.removeAll()
    }

    required init(database: Database, arguments: [String]) {
        Swift.print (#function, arguments)
    }

    var declaration: String {
        "CREATE TABLE x(value,start hidden,stop hidden,step hidden)"
    }
    
    var options: Database.VirtualTableModuleOptions {
        return [.innocuous]
    }
    
    func bestIndex(_ indexInfo: inout sqlite3_index_info) -> VirtualTableModuleBestIndexResult {
        
        guard var info = FilterInfo(&indexInfo) else { return .constraint }
        if info.contains(.start) && info.contains(.stop) {
            indexInfo.estimatedCost = 2  - (info.contains(.step) ? 1 : 0)
            indexInfo.estimatedRows = 1000
        }
        else {
            indexInfo.estimatedRows = 2147483647
        }
        
        indexInfo.idxNum = add(&info)
        return .ok
    }
    
    func openCursor() -> VirtualTableCursor {
        return Cursor(self, filter: filters.last)
    }
}

extension SeriesModule {
    final class Cursor: VirtualTableCursor {
        
        let module: SeriesModule
        let filterInfo: FilterInfo?
        let max_rows = 10_000 // Safety Net b/c default max is TOO BIG
        
        var _rowid: Int64 = 0
        var _value: Int64 = 0
        var _min: Int64 = 0
        var _max: Int64 = 0
        var _step: Int64 = 0
        var isDescending: Bool { filterInfo?.isDescending ?? false }
        
        init(_ module: SeriesModule, filter: FilterInfo?) {
            self.module = module
            self.filterInfo = filter
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
            defer { module.clearFilters() }
            guard let filterInfo = filterInfo ?? module.filters[Int(indexNumber)]
            else { return }
            _rowid = 1
            _min = 0
            _max = 0xffffffff
            _step = 1
            
            // DEBUG
            Swift.print(
                filterInfo.describe(with: Column.allCases.map {String(describing:$0)},
                                           values: arguments))
            
            for farg in filterInfo.argv {
                switch (Column(rawValue: farg.col_ndx), arguments[Int(farg.arg_ndx)]) {
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
            guard _rowid <= max_rows else { return true }
            return isDescending ? (_value < _min) : (_value > _max)
        }
    }
}

// Extenstion to interface w/ SeriesModule
extension FilterInfo {
    func contains(_ col: SeriesModule.Column) -> Bool {
        argv.contains(where: { $0.col_ndx == col.rawValue} )
    }
}
