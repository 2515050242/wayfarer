///|
/// A missing field reported while checking a GTFS Schedule table's header.
pub struct SchemaIssue {
  code : String
  table : String
  column : String
  message : String
}

///| Check the required column names for a supported GTFS Schedule table.

///| This initial layer checks unconditional table shape only; conditional

///|
/// fields, row values, and cross-file relationships are handled separately.
pub fn validate_schema(
  table_name : String,
  table : CsvTable,
) -> Array[SchemaIssue] {
  let required = required_columns(table_name)
  let issues : Array[SchemaIssue] = []
  if required.length() == 0 {
    issues.push(SchemaIssue::{
      code: "unsupported_table",
      table: table_name,
      column: "",
      message: "no header rules are defined for this table",
    })
    return issues
  }
  for column in required {
    if table.column_index(column) is None {
      issues.push(SchemaIssue::{
        code: "missing_required_header",
        table: table_name,
        column,
        message: "required column is missing",
      })
    }
  }
  issues
}

///|
fn required_columns(table_name : String) -> Array[String] {
  match table_name {
    "agency.txt" => ["agency_name", "agency_url", "agency_timezone"]
    "stops.txt" => ["stop_id"]
    "routes.txt" => ["route_id", "route_type"]
    "trips.txt" => ["route_id", "service_id", "trip_id"]
    "stop_times.txt" => ["trip_id", "stop_sequence"]
    "calendar.txt" =>
      [
        "service_id", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday",
        "sunday", "start_date", "end_date",
      ]
    "calendar_dates.txt" => ["service_id", "date", "exception_type"]
    _ => []
  }
}
