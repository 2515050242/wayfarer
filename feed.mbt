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
  calendar : CsvTable?
  calendar_dates : CsvTable?
}

///|
/// Create a set of core tables for feed validation.
pub fn GtfsTables::new(
  stops : CsvTable?,
  routes : CsvTable?,
  trips : CsvTable?,
  stop_times : CsvTable?,
) -> GtfsTables {
  GtfsTables::{
    stops,
    routes,
    trips,
    stop_times,
    calendar: None,
    calendar_dates: None,
  }
}

///|
/// Create a set of core tables with optional service-calendar context.
pub fn GtfsTables::with_services(
  stops : CsvTable?,
  routes : CsvTable?,
  trips : CsvTable?,
  stop_times : CsvTable?,
  calendar : CsvTable?,
  calendar_dates : CsvTable?,
) -> GtfsTables {
  GtfsTables::{ stops, routes, trips, stop_times, calendar, calendar_dates, }
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
/// references; and trip service references when `calendar.txt` or
/// `calendar_dates.txt` supplies service IDs. It also checks the supported
/// service-calendar date fields and stop-time window rules, plus route-level
/// continuous-service constraints when route, trip, and stop-time context is
/// available. It requires `stop_id` in the supported fixed-stop profile, but
/// does not check all conditional fields or whether the supplied tables satisfy
/// the remaining header profile.
pub fn validate_feed(tables : GtfsTables) -> Array[FeedIssue] {
  let issues : Array[FeedIssue] = []
  let mut stop_ids : Map[String, Int32] = Map([])
  let mut stop_location_types : Map[String, String] = Map([])
  let mut route_ids : Map[String, Int32] = Map([])
  let mut trip_ids : Map[String, Int32] = Map([])

  match tables.stops {
    Some(table) => {
      stop_ids = index_unique_id(table, "stops.txt", "stop_id", issues)
      stop_location_types = index_stop_location_types(table)
    }
    None => ()
  }
  match tables.routes {
    Some(table) => {
      route_ids = index_unique_id(table, "routes.txt", "route_id", issues)
      check_route_continuous_enums(table, issues)
    }
    None => ()
  }
  match tables.trips {
    Some(table) =>
      trip_ids = index_unique_id(table, "trips.txt", "trip_id", issues)
    None => ()
  }

  let service_ids : Map[String, Int32] = Map([])
  match tables.calendar {
    Some(table) => {
      index_service_ids(table, "calendar.txt", service_ids, issues, true)
      check_calendar_values(table, issues)
    }
    None => ()
  }
  match tables.calendar_dates {
    Some(table) => {
      index_service_ids(table, "calendar_dates.txt", service_ids, issues, false)
      check_calendar_date_keys(table, issues)
      check_calendar_dates_values(table, issues)
    }
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

  let has_calendar_service_ids = match tables.calendar {
    Some(table) => table.column_index("service_id") is Some(_)
    None => false
  }
  let has_date_service_ids = match tables.calendar_dates {
    Some(table) => table.column_index("service_id") is Some(_)
    None => false
  }
  match tables.trips {
    Some(trips) =>
      if (has_calendar_service_ids || has_date_service_ids) &&
        trips.column_index("service_id") is Some(_) {
        check_reference(
          trips, "trips.txt", "service_id", "calendar.txt or calendar_dates.txt",
          service_ids, issues, true,
        )
      }
    None => ()
  }

  match (tables.stop_times, tables.trips) {
    (Some(stop_times), Some(trips)) => {
      if trips.column_index("trip_id") is Some(_) {
        check_reference(
          stop_times, "stop_times.txt", "trip_id", "trips.txt", trip_ids, issues,
          false,
        )
      }
      check_trip_stop_counts(trips, stop_times, trip_ids, issues)
      check_stop_time_semantics(stop_times, issues)
    }
    (Some(stop_times), None) => check_stop_time_semantics(stop_times, issues)
    _ => ()
  }

  match tables.stop_times {
    Some(stop_times) =>
      check_stop_time_locations(
        stop_times,
        tables.stops is Some(_),
        stop_ids,
        stop_location_types,
        issues,
      )
    None => ()
  }
  match (tables.routes, tables.trips, tables.stop_times) {
    (Some(routes), Some(trips), Some(stop_times)) =>
      check_route_continuous_windows(routes, trips, stop_times, issues)
    _ => ()
  }
  issues
}

///|
fn index_stop_location_types(table : CsvTable) -> Map[String, String] {
  let locations : Map[String, String] = Map([])
  match (table.column_index("stop_id"), table.column_index("location_type")) {
    (Some(stop_column), location_type_column) =>
      for row in table.rows {
        let stop_id = row.cells[stop_column]
        if stop_id != "" && locations.get(stop_id) is None {
          let location_type = match location_type_column {
            Some(column) => row.cells[column]
            None => ""
          }
          locations.set(stop_id, location_type)
        }
      }
    _ => ()
  }
  locations
}

///|
fn check_stop_time_locations(
  table : CsvTable,
  has_stops_table : Bool,
  stop_ids : Map[String, Int32],
  stop_location_types : Map[String, String],
  issues : Array[FeedIssue],
) -> Unit {
  let stop_column = table.column_index("stop_id")
  let location_group_column = table.column_index("location_group_id")
  let location_column = table.column_index("location_id")
  let mut missing_header_reported = false
  if stop_column is None && table.rows.length() == 0 {
    add_missing_stop_id_header_issue(issues)
  }
  for row in table.rows {
    let location_group_id = match location_group_column {
      Some(column) => row.cells[column]
      None => ""
    }
    let location_id = match location_column {
      Some(column) => row.cells[column]
      None => ""
    }
    if location_group_id != "" || location_id != "" {
      let unsupported_column = if location_group_id != "" {
        "location_group_id"
      } else {
        "location_id"
      }
      let unsupported_value = if location_group_id != "" {
        location_group_id
      } else {
        location_id
      }
      issues.push(FeedIssue::{
        code: "unsupported_location_profile",
        file: "stop_times.txt",
        line: row.line,
        column: unsupported_column,
        value: unsupported_value,
        message: "flexible-location records using location_group_id or location_id are outside the supported fixed-stop profile",
      })
    } else {
      match stop_column {
        None =>
          if !missing_header_reported {
            add_missing_stop_id_header_issue(issues)
            missing_header_reported = true
          }
        Some(stop_column) => {
          let stop_id = row.cells[stop_column]
          if stop_id == "" {
            issues.push(FeedIssue::{
              code: "empty_foreign_key",
              file: "stop_times.txt",
              line: row.line,
              column: "stop_id",
              value: "",
              message: "stop_id is required for the supported fixed-stop profile",
            })
          } else if has_stops_table {
            if stop_ids.get(stop_id) is None {
              issues.push(FeedIssue::{
                code: "unresolved_reference",
                file: "stop_times.txt",
                line: row.line,
                column: "stop_id",
                value: stop_id,
                message: "referenced ID does not exist in stops.txt",
              })
            } else {
              match stop_location_types.get(stop_id) {
                Some("0") | Some("") => ()
                Some(_) =>
                  issues.push(FeedIssue::{
                    code: "invalid_stop_location_type",
                    file: "stop_times.txt",
                    line: row.line,
                    column: "stop_id",
                    value: stop_id,
                    message: "stop_times.stop_id must identify a stop or platform (location_type 0 or empty)",
                  })
                None => ()
              }
            }
          }
        }
      }
    }
  }
}

///|
fn add_missing_stop_id_header_issue(issues : Array[FeedIssue]) -> Unit {
  issues.push(FeedIssue::{
    code: "missing_required_header",
    file: "stop_times.txt",
    line: 1,
    column: "stop_id",
    value: "",
    message: "stop_id header is required for the supported fixed-stop profile",
  })
}

///|
fn check_calendar_date_keys(
  table : CsvTable,
  issues : Array[FeedIssue],
) -> Unit {
  match (table.column_index("service_id"), table.column_index("date")) {
    (Some(service_column), Some(date_column)) => {
      let seen : Map[String, Map[String, Int32]] = Map([])
      for row in table.rows {
        let service_id = row.cells[service_column]
        let date = row.cells[date_column]
        if date == "" {
          issues.push(FeedIssue::{
            code: "empty_primary_key",
            file: "calendar_dates.txt",
            line: row.line,
            column: "date",
            value: date,
            message: "date value must not be empty",
          })
        } else if service_id != "" {
          let dates = match seen.get(service_id) {
            Some(dates) => dates
            None => {
              let dates : Map[String, Int32] = Map([])
              seen.set(service_id, dates)
              dates
            }
          }
          if dates.get(date) is Some(_) {
            issues.push(FeedIssue::{
              code: "duplicate_primary_key",
              file: "calendar_dates.txt",
              line: row.line,
              column: "service_id,date",
              value: service_id + "," + date,
              message: "service_id and date pair is already used in this table",
            })
          } else {
            dates.set(date, row.line)
          }
        }
      }
    }
    _ => ()
  }
}

///|
fn check_calendar_values(table : CsvTable, issues : Array[FeedIssue]) -> Unit {
  let weekday_columns = [
    "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
  ]
  let weekday_indices = weekday_columns.map(fn(column) {
    table.column_index(column)
  })
  let start_index = table.column_index("start_date")
  let end_index = table.column_index("end_date")
  for row in table.rows {
    for index in 0..<weekday_columns.length() {
      match weekday_indices[index] {
        Some(column_index) => {
          let value = row.cells[column_index]
          if value != "0" && value != "1" {
            add_calendar_issue(
              row,
              "calendar.txt",
              weekday_columns[index],
              value,
              if value == "" {
                "missing_required_value"
              } else {
                "invalid_enum_value"
              },
              weekday_columns[index] + " must be 0 or 1",
              issues,
            )
          }
        }
        None => ()
      }
    }

    let start_date = csv_cell(row, start_index)
    let end_date = csv_cell(row, end_index)
    let start_valid = is_valid_gtfs_date(start_date)
    let end_valid = is_valid_gtfs_date(end_date)
    match start_index {
      Some(_) =>
        check_required_gtfs_date(
          row, "calendar.txt", "start_date", start_date, start_valid, issues,
        )
      None => ()
    }
    match end_index {
      Some(_) =>
        check_required_gtfs_date(
          row, "calendar.txt", "end_date", end_date, end_valid, issues,
        )
      None => ()
    }
    match (start_index, end_index) {
      (Some(_), Some(_)) if start_valid && end_valid => {
        let start_value = parse_non_negative_integer(start_date)
        let end_value = parse_non_negative_integer(end_date)
        match (start_value, end_value) {
          (Some(start), Some(end)) if end < start =>
            add_calendar_issue(
              row, "calendar.txt", "end_date", end_date, "invalid_date_range", "end_date must not precede start_date",
              issues,
            )
          _ => ()
        }
      }
      _ => ()
    }
  }
}

///|
fn check_calendar_dates_values(
  table : CsvTable,
  issues : Array[FeedIssue],
) -> Unit {
  let date_index = table.column_index("date")
  let exception_index = table.column_index("exception_type")
  for row in table.rows {
    let date = csv_cell(row, date_index)
    if date != "" && !is_valid_gtfs_date(date) {
      add_calendar_issue(
        row, "calendar_dates.txt", "date", date, "invalid_date", "date must be a valid Gregorian date in YYYYMMDD format",
        issues,
      )
    }
    match exception_index {
      Some(column_index) => {
        let value = row.cells[column_index]
        if value != "1" && value != "2" {
          add_calendar_issue(
            row,
            "calendar_dates.txt",
            "exception_type",
            value,
            if value == "" {
              "missing_required_value"
            } else {
              "invalid_enum_value"
            },
            "exception_type must be 1 or 2",
            issues,
          )
        }
      }
      None => ()
    }
  }
}

///|
fn check_required_gtfs_date(
  row : CsvRow,
  file : String,
  column : String,
  value : String,
  valid : Bool,
  issues : Array[FeedIssue],
) -> Unit {
  if value == "" {
    add_calendar_issue(
      row,
      file,
      column,
      value,
      "missing_required_value",
      column + " is required",
      issues,
    )
  } else if !valid {
    add_calendar_issue(
      row, file, column, value, "invalid_date", "date must be a valid Gregorian date in YYYYMMDD format",
      issues,
    )
  }
}

///|
fn add_calendar_issue(
  row : CsvRow,
  file : String,
  column : String,
  value : String,
  code : String,
  message : String,
  issues : Array[FeedIssue],
) -> Unit {
  issues.push(FeedIssue::{ code, file, line: row.line, column, value, message, })
}

///|
fn is_valid_gtfs_date(value : String) -> Bool {
  if value.length() != 8 {
    false
  } else {
    match parse_non_negative_integer(value) {
      None => false
      Some(date) => {
        let year = date / 10000
        let month = date / 100 % 100
        let day = date % 100
        let days_in_month = match month {
          1 | 3 | 5 | 7 | 8 | 10 | 12 => 31
          4 | 6 | 9 | 11 => 30
          2 =>
            if year % 400 == 0 || (year % 4 == 0 && year % 100 != 0) {
              29
            } else {
              28
            }
          _ => 0
        }
        year > 0 && day > 0 && day <= days_in_month
      }
    }
  }
}

///|
fn index_service_ids(
  table : CsvTable,
  file : String,
  service_ids : Map[String, Int32],
  issues : Array[FeedIssue],
  unique_in_table : Bool,
) -> Unit {
  let seen : Map[String, Int32] = Map([])
  match table.column_index("service_id") {
    None => ()
    Some(column_index) =>
      for row in table.rows {
        let value = row.cells[column_index]
        if value == "" {
          issues.push(FeedIssue::{
            code: "empty_primary_key",
            file,
            line: row.line,
            column: "service_id",
            value,
            message: "service_id value must not be empty",
          })
        } else if unique_in_table && seen.get(value) is Some(_) {
          issues.push(FeedIssue::{
            code: "duplicate_primary_key",
            file,
            line: row.line,
            column: "service_id",
            value,
            message: "service_id is already used in this table",
          })
        } else {
          seen.set(value, row.line)
          service_ids.set(value, row.line)
        }
      }
  }
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
fn check_trip_stop_counts(
  trips : CsvTable,
  stop_times : CsvTable,
  trip_ids : Map[String, Int32],
  issues : Array[FeedIssue],
) -> Unit {
  match (trips.column_index("trip_id"), stop_times.column_index("trip_id")) {
    (Some(trips_trip_column), Some(stop_times_trip_column)) => {
      let stop_counts : Map[String, Int32] = Map([])
      for row in stop_times.rows {
        let trip_id = row.cells[stop_times_trip_column]
        if trip_id != "" {
          let previous_count = match stop_counts.get(trip_id) {
            Some(count) => count
            None => 0
          }
          stop_counts.set(trip_id, previous_count + 1)
        }
      }
      for row in trips.rows {
        let trip_id = row.cells[trips_trip_column]
        let is_first_trip_record = match trip_ids.get(trip_id) {
          Some(first_line) => first_line == row.line
          None => false
        }
        if trip_id != "" && is_first_trip_record {
          let stop_count = match stop_counts.get(trip_id) {
            Some(count) => count
            None => 0
          }
          if stop_count < 2 {
            issues.push(FeedIssue::{
              code: "insufficient_stop_times",
              file: "trips.txt",
              line: row.line,
              column: "trip_id",
              value: trip_id,
              message: "trip must have at least two stop_times records",
            })
          }
        }
      }
    }
    _ => ()
  }
}

///|
fn check_stop_time_semantics(
  table : CsvTable,
  issues : Array[FeedIssue],
) -> Unit {
  check_stop_time_window_and_enum_fields(table, issues)
  let timed_stops : Array[TimedStop] = []
  match (table.column_index("trip_id"), table.column_index("stop_sequence")) {
    (Some(trip_column), Some(sequence_column)) => {
      let sequences : Map[String, Map[Int32, Int32]] = Map([])
      let invalid_sequence_trips : Map[String, Bool] = Map([])
      let arrival_column = table.column_index("arrival_time")
      let departure_column = table.column_index("departure_time")
      let timepoint_column = table.column_index("timepoint")
      let start_window_column = table.column_index(
        "start_pickup_drop_off_window",
      )
      let end_window_column = table.column_index("end_pickup_drop_off_window")
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
          None => {
            if trip_id != "" {
              invalid_sequence_trips.set(trip_id, true)
            }
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
                invalid_sequence_trips.set(trip_id, true)
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
                let arrival_text = match arrival_column {
                  Some(column) => row.cells[column]
                  None => ""
                }
                let departure_text = match departure_column {
                  Some(column) => row.cells[column]
                  None => ""
                }
                let timepoint_text = match timepoint_column {
                  Some(column) => row.cells[column]
                  None => ""
                }
                let has_start_window = match start_window_column {
                  Some(column) => row.cells[column] != ""
                  None => false
                }
                let has_end_window = match end_window_column {
                  Some(column) => row.cells[column] != ""
                  None => false
                }
                let has_pickup_drop_off_window = has_start_window ||
                  has_end_window
                timed_stops.push(TimedStop::{
                  trip_id,
                  sequence,
                  line: row.line,
                  arrival_text,
                  arrival_seconds: gtfs_time_seconds(arrival_text),
                  departure_text,
                  departure_seconds: gtfs_time_seconds(departure_text),
                  timepoint_text,
                  has_pickup_drop_off_window,
                })
              }
            }
        }
      }
      timed_stops.sort_by(fn(a, b) {
        if a.trip_id < b.trip_id {
          -1
        } else if a.trip_id > b.trip_id {
          1
        } else if a.sequence < b.sequence {
          -1
        } else if a.sequence > b.sequence {
          1
        } else {
          0
        }
      })
      check_stop_time_conditionals(timed_stops, invalid_sequence_trips, issues)
    }
    _ => ()
  }
  check_stop_time_column(table, "arrival_time", issues)
  check_stop_time_column(table, "departure_time", issues)
  check_stop_time_order(timed_stops, issues)
}

///|
fn check_stop_time_window_and_enum_fields(
  table : CsvTable,
  issues : Array[FeedIssue],
) -> Unit {
  let timepoint_column = table.column_index("timepoint")
  let pickup_column = table.column_index("pickup_type")
  let drop_off_column = table.column_index("drop_off_type")
  let continuous_pickup_column = table.column_index("continuous_pickup")
  let continuous_drop_off_column = table.column_index("continuous_drop_off")
  let start_window_column = table.column_index("start_pickup_drop_off_window")
  let end_window_column = table.column_index("end_pickup_drop_off_window")
  let arrival_column = table.column_index("arrival_time")
  let departure_column = table.column_index("departure_time")
  for row in table.rows {
    check_stop_time_enum(
      row,
      timepoint_column,
      "timepoint",
      ["0", "1"],
      "timepoint must be empty, 0, or 1",
      issues,
    )
    check_stop_time_enum(
      row,
      pickup_column,
      "pickup_type",
      ["0", "1", "2", "3"],
      "pickup_type must be empty or one of 0, 1, 2, or 3",
      issues,
    )
    check_stop_time_enum(
      row,
      drop_off_column,
      "drop_off_type",
      ["0", "1", "2", "3"],
      "drop_off_type must be empty or one of 0, 1, 2, or 3",
      issues,
    )
    check_stop_time_enum(
      row,
      continuous_pickup_column,
      "continuous_pickup",
      ["0", "1", "2", "3"],
      "continuous_pickup must be empty or one of 0, 1, 2, or 3",
      issues,
    )
    check_stop_time_enum(
      row,
      continuous_drop_off_column,
      "continuous_drop_off",
      ["0", "1", "2", "3"],
      "continuous_drop_off must be empty or one of 0, 1, 2, or 3",
      issues,
    )

    let start = csv_cell(row, start_window_column)
    let end = csv_cell(row, end_window_column)
    let has_window = start != "" || end != ""
    if start != "" && end == "" {
      add_stop_time_field_issue(
        row, "end_pickup_drop_off_window", "", "missing_required_window_bound", "end_pickup_drop_off_window is required when a start window is supplied",
        issues,
      )
    }
    if end != "" && start == "" {
      add_stop_time_field_issue(
        row, "start_pickup_drop_off_window", "", "missing_required_window_bound",
        "start_pickup_drop_off_window is required when an end window is supplied",
        issues,
      )
    }
    if start != "" && gtfs_time_seconds(start) is None {
      add_stop_time_field_issue(
        row, "start_pickup_drop_off_window", start, "invalid_time", "time must use H:MM:SS or HH:MM:SS with minutes and seconds from 00 to 59",
        issues,
      )
    }
    if end != "" && gtfs_time_seconds(end) is None {
      add_stop_time_field_issue(
        row, "end_pickup_drop_off_window", end, "invalid_time", "time must use H:MM:SS or HH:MM:SS with minutes and seconds from 00 to 59",
        issues,
      )
    }
    match (gtfs_time_seconds(start), gtfs_time_seconds(end)) {
      (Some(start_seconds), Some(end_seconds)) if end_seconds <= start_seconds =>
        add_stop_time_field_issue(
          row, "end_pickup_drop_off_window", end, "invalid_time_window", "end_pickup_drop_off_window must be later than start_pickup_drop_off_window",
          issues,
        )
      _ => ()
    }

    if has_window {
      if csv_cell(row, timepoint_column) == "1" {
        add_stop_time_field_issue(
          row, "timepoint", "1", "incompatible_stop_time_fields", "timepoint 1 requires exact times, which are forbidden with a pickup/drop-off window",
          issues,
        )
      }
      check_window_forbidden_value(row, arrival_column, "arrival_time", issues)
      check_window_forbidden_value(
        row, departure_column, "departure_time", issues,
      )
      check_window_forbidden_enum(
        row,
        pickup_column,
        "pickup_type",
        ["", "0", "3"],
        "pickup_type must be 1 or 2 when a pickup/drop-off window is defined",
        issues,
      )
      check_window_forbidden_enum(
        row,
        drop_off_column,
        "drop_off_type",
        ["", "0"],
        "drop_off_type must not be empty or 0 when a pickup/drop-off window is defined",
        issues,
      )
      check_window_forbidden_enum(
        row,
        continuous_pickup_column,
        "continuous_pickup",
        ["0", "2", "3"],
        "continuous_pickup must be 1 or empty when a pickup/drop-off window is defined",
        issues,
      )
      check_window_forbidden_enum(
        row,
        continuous_drop_off_column,
        "continuous_drop_off",
        ["0", "2", "3"],
        "continuous_drop_off must be 1 or empty when a pickup/drop-off window is defined",
        issues,
      )
    }
  }
}

///|
fn csv_cell(row : CsvRow, column : Int32?) -> String {
  match column {
    Some(index) => row.cells[index]
    None => ""
  }
}

///|
fn check_stop_time_enum(
  row : CsvRow,
  column_index : Int32?,
  column : String,
  allowed : Array[String],
  message : String,
  issues : Array[FeedIssue],
) -> Unit {
  match column_index {
    Some(index) => {
      let value = row.cells[index]
      if value != "" && !allowed.contains(value) {
        add_stop_time_field_issue(
          row, column, value, "invalid_enum_value", message, issues,
        )
      }
    }
    None => ()
  }
}

///|
fn check_window_forbidden_value(
  row : CsvRow,
  column_index : Int32?,
  column : String,
  issues : Array[FeedIssue],
) -> Unit {
  let value = csv_cell(row, column_index)
  if value != "" {
    add_stop_time_field_issue(
      row,
      column,
      value,
      "forbidden_with_pickup_drop_off_window",
      column + " must be empty when a pickup/drop-off window is defined",
      issues,
    )
  }
}

///|
fn check_window_forbidden_enum(
  row : CsvRow,
  column_index : Int32?,
  column : String,
  forbidden : Array[String],
  message : String,
  issues : Array[FeedIssue],
) -> Unit {
  let value = csv_cell(row, column_index)
  if forbidden.contains(value) {
    add_stop_time_field_issue(
      row, column, value, "forbidden_with_pickup_drop_off_window", message, issues,
    )
  }
}

///|
fn add_stop_time_field_issue(
  row : CsvRow,
  column : String,
  value : String,
  code : String,
  message : String,
  issues : Array[FeedIssue],
) -> Unit {
  issues.push(FeedIssue::{
    code,
    file: "stop_times.txt",
    line: row.line,
    column,
    value,
    message,
  })
}

///|
fn check_route_continuous_windows(
  routes : CsvTable,
  trips : CsvTable,
  stop_times : CsvTable,
  issues : Array[FeedIssue],
) -> Unit {
  let trips_with_windows : Map[String, Bool] = Map([])
  match stop_times.column_index("trip_id") {
    Some(trip_column) => {
      let start_column = stop_times.column_index("start_pickup_drop_off_window")
      let end_column = stop_times.column_index("end_pickup_drop_off_window")
      for row in stop_times.rows {
        let trip_id = row.cells[trip_column]
        let has_start = match start_column {
          Some(index) => row.cells[index] != ""
          None => false
        }
        let has_end = match end_column {
          Some(index) => row.cells[index] != ""
          None => false
        }
        if trip_id != "" && (has_start || has_end) {
          trips_with_windows.set(trip_id, true)
        }
      }
    }
    None => ()
  }

  let routes_with_windows : Map[String, Bool] = Map([])
  match (trips.column_index("trip_id"), trips.column_index("route_id")) {
    (Some(trip_column), Some(route_column)) =>
      for row in trips.rows {
        let trip_id = row.cells[trip_column]
        let route_id = row.cells[route_column]
        if route_id != "" && trips_with_windows.get(trip_id) is Some(_) {
          routes_with_windows.set(route_id, true)
        }
      }
    _ => ()
  }

  let route_id_column = routes.column_index("route_id")
  let continuous_pickup_column = routes.column_index("continuous_pickup")
  let continuous_drop_off_column = routes.column_index("continuous_drop_off")
  match route_id_column {
    Some(route_id_column) =>
      for row in routes.rows {
        let route_id = row.cells[route_id_column]
        if routes_with_windows.get(route_id) is Some(_) {
          check_route_continuous_window_value(
            row, continuous_pickup_column, "continuous_pickup", issues,
          )
          check_route_continuous_window_value(
            row, continuous_drop_off_column, "continuous_drop_off", issues,
          )
        }
      }
    None => ()
  }
}

///|
fn check_route_continuous_enums(
  routes : CsvTable,
  issues : Array[FeedIssue],
) -> Unit {
  let continuous_pickup_column = routes.column_index("continuous_pickup")
  let continuous_drop_off_column = routes.column_index("continuous_drop_off")
  for row in routes.rows {
    check_route_continuous_enum(
      row, continuous_pickup_column, "continuous_pickup", issues,
    )
    check_route_continuous_enum(
      row, continuous_drop_off_column, "continuous_drop_off", issues,
    )
  }
}

///|
fn check_route_continuous_enum(
  row : CsvRow,
  column_index : Int32?,
  column : String,
  issues : Array[FeedIssue],
) -> Unit {
  match column_index {
    Some(index) => {
      let value = row.cells[index]
      if value != "" && !["0", "1", "2", "3"].contains(value) {
        issues.push(FeedIssue::{
          code: "invalid_enum_value",
          file: "routes.txt",
          line: row.line,
          column,
          value,
          message: column + " must be empty or one of 0, 1, 2, or 3",
        })
      }
    }
    None => ()
  }
}

///|
fn check_route_continuous_window_value(
  row : CsvRow,
  column_index : Int32?,
  column : String,
  issues : Array[FeedIssue],
) -> Unit {
  match column_index {
    Some(index) => {
      let value = row.cells[index]
      if ["0", "2", "3"].contains(value) {
        issues.push(FeedIssue::{
          code: "forbidden_with_pickup_drop_off_window",
          file: "routes.txt",
          line: row.line,
          column,
          value,
          message: column +
          " must be 1 or empty when a trip on this route defines a pickup/drop-off window",
        })
      }
    }
    None => ()
  }
}

///|
priv struct TimedStop {
  trip_id : String
  sequence : Int32
  line : Int32
  arrival_text : String
  arrival_seconds : Int32?
  departure_text : String
  departure_seconds : Int32?
  timepoint_text : String
  has_pickup_drop_off_window : Bool
}

///|
fn check_stop_time_conditionals(
  timed_stops : Array[TimedStop],
  invalid_sequence_trips : Map[String, Bool],
  issues : Array[FeedIssue],
) -> Unit {
  for index in 0..<timed_stops.length() {
    let stop = timed_stops[index]
    let first_in_trip = index == 0 ||
      timed_stops[index - 1].trip_id != stop.trip_id
    let last_in_trip = index + 1 == timed_stops.length() ||
      timed_stops[index + 1].trip_id != stop.trip_id
    let can_locate_trip_ends = match invalid_sequence_trips.get(stop.trip_id) {
      Some(_) => false
      None => true
    }
    let arrival_required = !stop.has_pickup_drop_off_window &&
      (
        stop.timepoint_text == "1" ||
        (can_locate_trip_ends && (first_in_trip || last_in_trip))
      )
    if arrival_required && stop.arrival_text == "" {
      let message = if stop.timepoint_text == "1" {
        "arrival_time is required when timepoint is 1"
      } else {
        "arrival_time is required at the first and last stop of a trip"
      }
      add_missing_stop_time_issue(stop, "arrival_time", message, issues)
    }
    if !stop.has_pickup_drop_off_window &&
      stop.timepoint_text == "1" &&
      stop.departure_text == "" {
      add_missing_stop_time_issue(
        stop, "departure_time", "departure_time is required when timepoint is 1",
        issues,
      )
    }
  }
}

///|
fn add_missing_stop_time_issue(
  stop : TimedStop,
  column : String,
  message : String,
  issues : Array[FeedIssue],
) -> Unit {
  issues.push(FeedIssue::{
    code: "missing_required_time",
    file: "stop_times.txt",
    line: stop.line,
    column,
    value: "",
    message,
  })
}

///|
fn check_stop_time_order(
  timed_stops : Array[TimedStop],
  issues : Array[FeedIssue],
) -> Unit {
  let mut previous_trip = ""
  let mut previous_time : Int32? = None
  for stop in timed_stops {
    if previous_trip != stop.trip_id {
      previous_trip = stop.trip_id
      previous_time = None
    }
    if !stop.has_pickup_drop_off_window {
      previous_time = check_time_order_event(
        stop.arrival_text,
        stop.arrival_seconds,
        "arrival_time",
        stop,
        previous_time,
        issues,
      )
      previous_time = check_time_order_event(
        stop.departure_text,
        stop.departure_seconds,
        "departure_time",
        stop,
        previous_time,
        issues,
      )
    }
  }
}

///|
fn check_time_order_event(
  value : String,
  seconds : Int32?,
  column : String,
  stop : TimedStop,
  previous_time : Int32?,
  issues : Array[FeedIssue],
) -> Int32? {
  match seconds {
    None => previous_time
    Some(current_time) => {
      match previous_time {
        Some(previous) =>
          if current_time < previous {
            issues.push(FeedIssue::{
              code: "time_order_violation",
              file: "stop_times.txt",
              line: stop.line,
              column,
              value,
              message: "time precedes an earlier defined time in this trip's stop_sequence order",
            })
          }
        None => ()
      }
      Some(current_time)
    }
  }
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
fn gtfs_time_seconds(value : String) -> Int32? {
  if !is_gtfs_time(value) {
    None
  } else {
    let hour_digits = value.length() - 6
    let mut hours = 0
    for index in 0..<hour_digits {
      hours = hours * 10 + value.code_unit_at(index).to_int() - 48
    }
    Some(
      hours * 3600 +
      two_digits(value, hour_digits + 1) * 60 +
      two_digits(value, hour_digits + 4),
    )
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
