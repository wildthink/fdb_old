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
    public var argv: [FilterArg] = []
    public var isDescending: Bool = false
    
    public func contains(_ col: Int32) -> Bool {
        argv.contains(where: { $0.col_ndx == col} )
    }
    
    public func descibe(with cols: [String], values: [Any] = []) -> String {
        var str = "Filter ("
        for arg in argv {
            Swift.print(arg.descibe(with: cols, values: values),
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
    
    public var description: String  { "col[\(col_ndx)] \(op_str) argv[\(arg_ndx)])" }
    public var op_str: String       { FilterArg.op_str(self.op) }
    
    public func descibe(with cols: [String], values: [Any] = []) -> String {
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

public extension FilterArg {
    init(arg: Int32, col: ColumnIndex, op: UInt8) {
        self.init(arg: arg, col: col.rawValue, op: op)
    }
}

