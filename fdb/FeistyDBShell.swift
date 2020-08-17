//
//  FeistyDBShell.swift
//  fdb
//
//  Created by Jason Jobe on 7/24/20.
//

import Foundation
import FeistyDB
import FeistyExtensions


@_cdecl("feisty_init")
func fiesty_init(_ db: SQLiteDatabaseConnection) {
    Swift.print (#function)
    let db = Database(rawSQLiteDatabase: db)
    do {
        try db.addModule("calendar", type: CalendarModule.self)
        try db.addModule("series", type: SeriesModule.self)
        
        let date_fmt = DateFormatter()
        date_fmt.dateFormat = "yyyy-MM-dd"

        try db.addFunction("datefmt", arity: 2) { values in
            
            guard case let DatabaseValue.text(fmt_s) = values[0] else { return .null }
            guard case let DatabaseValue.text(date_s) = values[1],
                  let date = date_fmt.date(from: date_s)
            else { return .null }

            let fmt = DateFormatter()
            fmt.dateFormat = fmt_s
            return .text(fmt.string(from: date))
        }

    } catch {
        Swift.print (error)
    }
    g_db = db
}

// extern feisty_init(sqlite* db);
var g_db: Database?

