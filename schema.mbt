///|
/// A missing field reported while checking a GTFS Schedule table's header.
pub struct SchemaIssue {
  code : String
  table : String
  column : String
  message : String
}

///|
/// A GTFS field value that contains a forbidden control character.
pub struct FieldValueIssue {
  code : String
  file : String
  line : Int32
  column : String
  value : String
  message : String
}

///|
/// Reject tabs, carriage returns, and newlines in parsed GTFS field values.
///
/// CSV row separators are consumed by `parse_csv`, and quoted newlines are
/// retained as normalized LF characters in the field value so they can be
/// diagnosed here with the source record and field.
pub fn validate_gtfs_field_values(
  file : String,
  table : CsvTable,
) -> Array[FieldValueIssue] {
  let issues : Array[FieldValueIssue] = []
  for row in table.rows {
    for column_index, column in table.headers {
      let value = row.cells[column_index]
      let mut forbidden = false
      for character in value.to_array() {
        if character == '\t' || character == '\r' || character == '\n' {
          forbidden = true
        }
      }
      if forbidden {
        issues.push(FieldValueIssue::{
          code: "forbidden_field_character",
          file,
          line: row.line,
          column,
          value,
          message: "GTFS field values must not contain tabs, carriage returns, or newlines",
        })
      }
    }
  }
  issues
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
