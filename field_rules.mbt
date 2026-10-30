///|
/// The value constraint applied to one column by a field rule.
pub(all) enum CsvDatasetFieldKind {
  IntegerValue
  NumberValue
  DateValue
  AllowedValues
}

///|
/// A per-column value rule for one table in a dataset profile.
///
/// Empty cells are not reported by field rules; use `non_empty_columns` to
/// reject them. `allowed` is used by `AllowedValues` and ignored by the other
/// kinds.
pub(all) struct CsvDatasetFieldRule {
  column : String
  kind : CsvDatasetFieldKind
  allowed : Array[String]
}

///|
/// Construct a field rule for one column of a table.
pub fn CsvDatasetFieldRule::new(
  column : String,
  kind : CsvDatasetFieldKind,
  allowed~ : Array[String] = [],
) -> CsvDatasetFieldRule {
  CsvDatasetFieldRule::{ column, kind, allowed, }
}

///|
/// Check the per-column field rules declared by a table rule.
fn check_dataset_field_rules(
  rule : CsvDatasetTableRule,
  table : CsvTable,
  issues : Array[CsvDatasetIssue],
) -> Unit {
  for field_rule in rule.field_rules {
    if field_rule.column == "" {
      add_dataset_issue(
        issues,
        "invalid_profile",
        rule.file,
        None,
        "field_rules",
        "",
        "field rules must name a column",
      )
    } else {
      match table.column_index(field_rule.column) {
        None => add_missing_dataset_column(issues, rule.file, field_rule.column)
        Some(index) =>
          for row in table.rows {
            let value = row.cells[index]
            if value != "" {
              check_dataset_field_value(
                rule.file,
                field_rule,
                row.line,
                value,
                issues,
              )
            }
          }
      }
    }
  }
}

///|
fn check_dataset_field_value(
  file : String,
  field_rule : CsvDatasetFieldRule,
  line : Int32,
  value : String,
  issues : Array[CsvDatasetIssue],
) -> Unit {
  match field_rule.kind {
    IntegerValue =>
      if !is_dataset_integer(value) {
        add_dataset_issue(
          issues,
          "invalid_integer_value",
          file,
          Some(line),
          field_rule.column,
          value,
          "value must be an optionally signed integer",
        )
      }
    NumberValue =>
      if !is_dataset_number(value) {
        add_dataset_issue(
          issues,
          "invalid_number_value",
          file,
          Some(line),
          field_rule.column,
          value,
          "value must be an integer or decimal number",
        )
      }
    DateValue =>
      if !is_valid_gtfs_date(value) {
        add_dataset_issue(
          issues,
          "invalid_date_value",
          file,
          Some(line),
          field_rule.column,
          value,
          "value must be a valid Gregorian date in YYYYMMDD format",
        )
      }
    AllowedValues => {
      let mut is_allowed = false
      for allowed in field_rule.allowed {
        if allowed == value {
          is_allowed = true
          break
        }
      }
      if !is_allowed {
        add_dataset_issue(
          issues,
          "value_not_allowed",
          file,
          Some(line),
          field_rule.column,
          value,
          "value is not one of the allowed values declared in the profile",
        )
      }
    }
  }
}

///|
fn is_dataset_integer(value : String) -> Bool {
  let characters = value.to_array()
  let start = if characters[0] == '-' || characters[0] == '+' { 1 } else { 0 }
  if characters.length() == start {
    return false
  }
  for index in start..<characters.length() {
    let character = characters[index]
    if character < '0' || character > '9' {
      return false
    }
  }
  true
}

///|
/// A number is an optionally signed run of digits with an optional single
/// decimal point followed by at least one digit. Exponent notation is not
/// accepted.
fn is_dataset_number(value : String) -> Bool {
  let characters = value.to_array()
  let start = if characters[0] == '-' || characters[0] == '+' { 1 } else { 0 }
  let mut index = start
  let mut integer_digits = 0
  while index < characters.length() &&
        characters[index] >= '0' &&
        characters[index] <= '9' {
    integer_digits = integer_digits + 1
    index = index + 1
  }
  if integer_digits == 0 {
    return false
  }
  if index < characters.length() && characters[index] == '.' {
    index = index + 1
    let mut fraction_digits = 0
    while index < characters.length() &&
          characters[index] >= '0' &&
          characters[index] <= '9' {
      fraction_digits = fraction_digits + 1
      index = index + 1
    }
    if fraction_digits == 0 {
      return false
    }
  }
  index == characters.length()
}
