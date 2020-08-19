//
//  FeistyVtabExtensions.swift
//  fdb
//
//  Created by Jason Jobe on 8/19/20.
//

import Foundation
import CSQLite
import FeistyDB

public protocol ColumnIndex {
    var rawValue: Int32 { get }
}

public struct FilterInfo {
    public var key: Int32 = 0
    public var argv: [FilterArg] = []
    public var columnsUsed: UInt64 = 0
    public var isDescending: Bool = false
    
    public func contains(_ col: Int32) -> Bool {
        argv.contains(where: { $0.col_ndx == col} )
    }
    
    public func describe(with cols: [String], values: [Any] = []) -> String {
        var str = "Filter ("
        for arg in argv {
            Swift.print(arg.describe(with: cols, values: values),
                        separator: ",", terminator: " ", to: &str)
        }
        Swift.print(")", separator: "", terminator: "\n", to: &str)
        return str
    }
}

public struct FilterArg: CustomStringConvertible {
    
    var arg_ndx: Int32
    var col_ndx: Int32
    var op: UInt8
    
    public init(arg: Int32, col: Int32, op: UInt8) {
        self.arg_ndx = arg
        self.col_ndx = col
        self.op = op
    }
    
    init(arg: Int32, col: ColumnIndex, op: UInt8) {
        self.init(arg: arg, col: col.rawValue, op: op)
    }

    public var description: String  { "col[\(col_ndx)] \(op_str) argv[\(arg_ndx)])" }
    public var op_str: String       { FilterArg.op_str(self.op) }
    
    public func describe(with cols: [String], values: [Any] = []) -> String {
        let ndx = Int(col_ndx)
        let col = (ndx < cols.count ? cols[ndx] : "col[\(ndx)]")
        let a_ndx = Int(arg_ndx)
        let arg = (a_ndx < values.count ? values[a_ndx] : "argv[\(a_ndx)]")
        return "\(col) \(op_str) \(arg)"
    }
    
    public static func op_str(_ op: UInt8) -> String {
        
        switch Int32(op) {
            case SQLITE_INDEX_CONSTRAINT_EQ: return "="
            case SQLITE_INDEX_CONSTRAINT_GT: return ">"
            case SQLITE_INDEX_CONSTRAINT_LE: return "<="
            case SQLITE_INDEX_CONSTRAINT_LT: return "<"
            case SQLITE_INDEX_CONSTRAINT_GE: return ">="
            case SQLITE_INDEX_CONSTRAINT_MATCH: return "MATCH"
            case SQLITE_INDEX_CONSTRAINT_LIKE: return "LIKE"
            case SQLITE_INDEX_CONSTRAINT_GLOB: return "GLOB"
            case SQLITE_INDEX_CONSTRAINT_REGEXP: return "REGEX"
            case SQLITE_INDEX_CONSTRAINT_NE: return "!="
            case SQLITE_INDEX_CONSTRAINT_ISNOT: return "IS NOT"
            case SQLITE_INDEX_CONSTRAINT_ISNOTNULL: return "IS NOT NULL"
            case SQLITE_INDEX_CONSTRAINT_ISNULL: return "IS NULL"
            case SQLITE_INDEX_CONSTRAINT_IS: return "IS"
            case SQLITE_INDEX_CONSTRAINT_FUNCTION: return "f()"
            default:
                return "<op>"
        }
    }
}

public extension FilterInfo {
    
    init? (_ indexInfo: inout sqlite3_index_info) {
        
        // Inputs
        let constraintCount = Int(indexInfo.nConstraint)
        let constraints = UnsafeBufferPointer<sqlite3_index_constraint>(start: indexInfo.aConstraint, count: constraintCount)
                
        var argc: Int32 = 1
        
        for i in 0 ..< constraintCount {
            let constraint = constraints[i]
            guard constraint.usable != 0 else { continue }
            let farg = FilterArg(arg: argc - 1, col: constraint.iColumn, op: constraint.op)
            argv.append(farg)
            // Outputs
            indexInfo.aConstraintUsage[i].argvIndex = argc
            indexInfo.aConstraintUsage[i].omit = 1
            argc += 1
        }
        
        let orderByCount = Int(indexInfo.nOrderBy)
        let orderBy = UnsafeBufferPointer<sqlite3_index_orderby>(start: indexInfo.aOrderBy, count: orderByCount)
        
        if orderByCount == 1 {
            if orderBy[0].desc == 1 {
                isDescending = true
            }
            // Output
            indexInfo.orderByConsumed = 1
        }
        self.columnsUsed = indexInfo.colUsed
    }

}

