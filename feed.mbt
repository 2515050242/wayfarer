///|
/// The core tables used for feed-level relationship checks.
///
/// A missing table is treated as unavailable context: references into it are
/// not checked. Run `validate_schema` separately to check each table's headers.
pub(all) struct GtfsTables {
  stops : CsvTable?
  routes : CsvTable?
  trips : CsvTable?
  stop_times : CsvTable?
}

///|
/// Create a set of core tables for feed validation.
pub fn GtfsTables::new(
  stops : CsvTable?,
  routes : CsvTable?,
  trips : CsvTable?,
  stop_times : CsvTable?,
) -> GtfsTables {
  GtfsTables::{ stops, routes, trips, stop_times, }
}

///|
/// A row-level finding from feed relationship validation.
pub struct FeedIssue {
  code : String
  file : String
  line : Int32
  column : String
  value : String
  message : String
}

///|
/// Check core GTFS IDs and references across the supplied tables.
///
/// This checks `stops.stop_id`, `routes.route_id`, and `trips.trip_id` for
/// uniqueness; stop-time key and schedule fields; trip-to-route and stop-time
/// references. It does not check service IDs, conditional fields, or whether
/// the supplied tables satisfy the required-header profile.
pub fn validate_feed(tables : GtfsTables) -> Array[FeedIssue] {
  let issues : Array[FeedIssue] = []
  let mut stop_ids : Map[String, Int32] = Map([])
  let mut route_ids : Map[String, Int32] = Map([])
  let mut trip_ids : Map[String, Int32] = Map([])

  match tables.stops {
    Some(table) =>
      stop_ids = index_unique_id(table, "stops.txt", "stop_id", issues)
    None => ()
  }
  match tables.routes {
    Some(table) =>
      route_ids = index_unique_id(table, "routes.txt", "route_id", issues)
    None => ()
  }
  match tables.trips {
    Some(table) =>
      trip_ids = index_unique_id(table, "trips.txt", "trip_id", issues)
    None => ()
  }

  match (tables.trips, tables.routes) {
    (Some(trips), Some(routes)) =>
      if routes.column_index("route_id") is Some(_) {
        check_reference(
          trips, "trips.txt", "route_id", "routes.txt", route_ids, issues, true,
        )
      }
    _ => ()
  }

  match (tables.stop_times, tables.trips) {
    (Some(stop_times), Some(trips)) => {
      if trips.column_index("trip_id") is Some(_) {
        check_reference(
          stop_times, "stop_times.txt", "trip_id", "trips.txt", trip_ids, issues,
          true,
        )
      }
      check_stop_time_semantics(stop_times, issues)
    }
    (Some(stop_times), None) => check_stop_time_semantics(stop_times, issues)
    _ => ()
  }

  match (tables.stop_times, tables.stops) {
    (Some(stop_times), Some(stops)) =>
      if stops.column_index("stop_id") is Some(_) {
        check_reference(
          stop_times, "stop_times.txt", "stop_id", "stops.txt", stop_ids, issues,
          false,
        )
      }
    _ => ()
  }
  issues
}

///|
fn index_unique_id(
  table : CsvTable,
  file : String,
  column : String,
  issues : Array[FeedIssue],
) -> Map[String, Int32] {
  let index : Map[String, Int32] = Map([], capacity=table.rows.length())
  match table.column_index(column) {
    None => index
    Some(column_index) => {
      for row in table.rows {
        let value = row.cells[column_index]
        if value == "" {
          issues.push(FeedIssue::{
            code: "empty_primary_key",
            file,
            line: row.line,
            column,
            value,
            message: "primary key value must not be empty",
          })
        } else {
          match index.get(value) {
            Some(_) =>
              issues.push(FeedIssue::{
                code: "duplicate_primary_key",
                file,
                line: row.line,
                column,
                value,
                message: "primary key value is already used in this table",
              })
            None => index.set(value, row.line)
          }
        }
      }
      index
    }
  }
}

///|
fn check_reference(
  source : CsvTable,
  source_file : String,
  column : String,
  target_file : String,
  target_ids : Map[String, Int32],
  issues : Array[FeedIssue],
  required : Bool,
) -> Unit {
  match source.column_index(column) {
    None => ()
    Some(column_index) =>
      for row in source.rows {
        let value = row.cells[column_index]
        if value == "" {
          if required {
            issues.push(FeedIssue::{
              code: "empty_foreign_key",
              file: source_file,
              line: row.line,
              column,
              value,
              message: "required foreign key value must not be empty",
            })
          }
        } else if target_ids.get(value) is None {
          issues.push(FeedIssue::{
            code: "unresolved_reference",
            file: source_file,
            line: row.line,
            column,
            value,
            message: "referenced ID does not exist in " + target_file,
          })
        }
      }
  }
}

///|
fn check_stop_time_semantics(
  table : CsvTable,
  issues : Array[FeedIssue],
) -> Unit {
  match (table.column_index("trip_id"), table.column_index("stop_sequence")) {
    (Some(trip_column), Some(sequence_column)) => {
      let sequences : Map[String, Map[Int32, Int32]] = Map([])
      let previous : Map[String, Int32] = Map([])
      for row in table.rows {
        let trip_id = row.cells[trip_column]
        let sequence_text = row.cells[sequence_column]
        if sequence_text == "" {
          issues.push(FeedIssue::{
            code: "empty_primary_key",
            file: "stop_times.txt",
            line: row.line,
            column: "stop_sequence",
            value: sequence_text,
            message: "primary key value must not be empty",
          })
        }
        if trip_id == "" {
          issues.push(FeedIssue::{
            code: "empty_primary_key",
            file: "stop_times.txt",
            line: row.line,
            column: "trip_id",
            value: trip_id,
            message: "primary key value must not be empty",
          })
        }
        match parse_non_negative_integer(sequence_text) {
          None =>
            if sequence_text != "" {
              issues.push(FeedIssue::{
                code: "invalid_stop_sequence",
                file: "stop_times.txt",
                line: row.line,
                column: "stop_sequence",
                value: sequence_text,
                message: "stop_sequence must be a non-negative integer",
              })
            }
          Some(sequence) =>
            if trip_id != "" {
              let seen = match sequences.get(trip_id) {
                Some(seen) => seen
                None => {
                  let first_sequence : Map[Int32, Int32] = Map([])
                  sequences.set(trip_id, first_sequence)
                  first_sequence
                }
              }
              if seen.get(sequence) is Some(_) {
                issues.push(FeedIssue::{
                  code: "duplicate_primary_key",
                  file: "stop_times.txt",
                  line: row.line,
                  column: "stop_sequence",
                  value: sequence_text,
                  message: "stop_sequence is already used for this trip_id",
                })
              } else {
                seen.set(sequence, row.line)
                match previous.get(trip_id) {
                  Some(last) =>
                    if sequence < last {
                      issues.push(FeedIssue::{
                        code: "stop_sequence_not_increasing",
                        file: "stop_times.txt",
                        line: row.line,
                        column: "stop_sequence",
                        value: sequence_text,
                        message: "stop_sequence must increase along each trip",
                      })
                    }
                  None => ()
                }
                previous.set(trip_id, sequence)
              }
            }
        }
      }
    }
    _ => ()
  }
  check_stop_time_column(table, "arrival_time", issues)
  check_stop_time_column(table, "departure_time", issues)
}

///|
fn check_stop_time_column(
  table : CsvTable,
  column : String,
  issues : Array[FeedIssue],
) -> Unit {
  match table.column_index(column) {
    None => ()
    Some(column_index) =>
      for row in table.rows {
        let value = row.cells[column_index]
        if value != "" && !is_gtfs_time(value) {
          issues.push(FeedIssue::{
            code: "invalid_time",
            file: "stop_times.txt",
            line: row.line,
            column,
            value,
            message: "time must use H:MM:SS or HH:MM:SS with minutes and seconds from 00 to 59",
          })
        }
      }
  }
}

///|
fn parse_non_negative_integer(value : String) -> Int32? {
  if value == "" {
    None
  } else {
    let mut result = 0
    let mut valid = true
    for index in 0..<value.length() {
      let unit = value.code_unit_at(index).to_int()
      if unit < 48 ||
        unit > 57 ||
        result > 214748364 ||
        (result == 214748364 && unit > 55) {
        valid = false
      } else {
        result = result * 10 + unit - 48
      }
    }
    if valid {
      Some(result)
    } else {
      None
    }
  }
}

///|
fn is_gtfs_time(value : String) -> Bool {
  let length = value.length()
  if length != 7 && length != 8 {
    false
  } else {
    let hour_digits = length - 6
    let mut valid = true
    for index in 0..<length {
      let unit = value.code_unit_at(index).to_int()
      if index == hour_digits || index == hour_digits + 3 {
        if unit != 58 {
          valid = false
        }
      } else if unit < 48 || unit > 57 {
        valid = false
      }
    }
    if !valid {
      false
    } else {
      let minute_start = hour_digits + 1
      let second_start = hour_digits + 4
      let minutes = two_digits(value, minute_start)
      let seconds = two_digits(value, second_start)
      minutes < 60 && seconds < 60
    }
  }
}

///|
fn two_digits(value : String, start : Int32) -> Int32 {
  (value.code_unit_at(start).to_int() - 48) * 10 +
  value.code_unit_at(start + 1).to_int() -
  48
}
