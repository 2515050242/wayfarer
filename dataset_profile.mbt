///|
/// A reusable contract for a set of related CSV tables.
///
/// This API is domain-neutral: callers can describe different table sets,
/// keys, required values, and references without changing GTFS-specific rules.
pub(all) struct CsvDatasetProfile {
  tables : Array[CsvDatasetTableRule]
  references : Array[CsvDatasetReferenceRule]
}

///|
/// A contract for one CSV file in a dataset.
pub(all) struct CsvDatasetTableRule {
  file : String
  required : Bool
  minimum_rows : Int32
  required_columns : Array[String]
  non_empty_columns : Array[String]
  unique_keys : Array[Array[String]]
}

///|
/// A foreign-key-style relation between two dataset tables.
pub(all) struct CsvDatasetReferenceRule {
  source_file : String
  source_column : String
  target_file : String
  target_column : String
  required : Bool
}

///|
/// A structured result from validating a CSV dataset against a profile.
///
/// `line` is absent for file- and header-level findings. `value` is empty for
/// findings that do not refer to a particular cell.
pub(all) struct CsvDatasetIssue {
  code : String
  file : String
  line : Int32?
  column : String
  value : String
  message : String
}

///|
/// Construct a profile from table and reference rules.
pub fn CsvDatasetProfile::new(
  tables : Array[CsvDatasetTableRule],
  references : Array[CsvDatasetReferenceRule],
) -> CsvDatasetProfile {
  CsvDatasetProfile::{ tables, references, }
}

///|
/// Construct a rule for one table. A zero `minimum_rows` allows an empty file.
pub fn CsvDatasetTableRule::new(
  file : String,
  required : Bool,
  minimum_rows : Int32,
  required_columns : Array[String],
  non_empty_columns : Array[String],
  unique_keys : Array[Array[String]],
) -> CsvDatasetTableRule {
  CsvDatasetTableRule::{
    file,
    required,
    minimum_rows,
    required_columns,
    non_empty_columns,
    unique_keys,
  }
}

///|
/// Construct a reference rule. Optional references may be blank in source rows.
pub fn CsvDatasetReferenceRule::new(
  source_file : String,
  source_column : String,
  target_file : String,
  target_column : String,
  required : Bool,
) -> CsvDatasetReferenceRule {
  CsvDatasetReferenceRule::{
    source_file,
    source_column,
    target_file,
    target_column,
    required,
  }
}

///|
/// Validate a set of CSV tables against a reusable dataset profile.
///
/// The validator checks required files and headers, minimum row counts,
/// non-empty fields, single- or multi-column unique keys, and declared
/// references. Missing optional tables are treated as unavailable context.
pub fn validate_csv_dataset(
  profile : CsvDatasetProfile,
  tables : Map[String, CsvTable],
) -> Array[CsvDatasetIssue] {
  let issues : Array[CsvDatasetIssue] = []
  if profile.tables.length() == 0 {
    add_dataset_issue(
      issues,
      "invalid_profile",
      "",
      None,
      "tables",
      "",
      "a dataset profile must declare at least one table",
    )
  }
  let declared_files : Map[String, Bool] = Map([])
  for rule in profile.tables {
    if rule.file == "" {
      add_dataset_issue(
        issues,
        "invalid_profile",
        "",
        None,
        "file",
        "",
        "table rules must name a file",
      )
    } else if declared_files.get(rule.file) is Some(_) {
      add_dataset_issue(
        issues,
        "duplicate_table_rule",
        rule.file,
        None,
        "file",
        rule.file,
        "each file may have only one table rule",
      )
    } else {
      declared_files.set(rule.file, true)
      if rule.minimum_rows < 0 {
        add_dataset_issue(
          issues,
          "invalid_profile",
          rule.file,
          None,
          "minimum_rows",
          rule.minimum_rows.to_string(),
          "minimum_rows cannot be negative",
        )
      }
      match tables.get(rule.file) {
        None =>
          if rule.required {
            add_dataset_issue(
              issues,
              "missing_required_table",
              rule.file,
              None,
              "",
              "",
              "required table is missing",
            )
          }
        Some(table) => validate_dataset_table(rule, table, issues)
      }
    }
  }

  for reference in profile.references {
    if declared_files.get(reference.source_file) is None ||
      declared_files.get(reference.target_file) is None ||
      reference.source_column == "" ||
      reference.target_column == "" {
      add_dataset_issue(
        issues,
        "invalid_profile",
        reference.source_file,
        None,
        reference.source_column,
        reference.target_file,
        "references must name declared tables and non-empty columns",
      )
    } else if !profile_has_unique_column(
        profile,
        reference.target_file,
        reference.target_column,
      ) {
      add_dataset_issue(
        issues,
        "invalid_reference_target",
        reference.target_file,
        None,
        reference.target_column,
        "",
        "a reference target must be declared as a single-column unique key",
      )
    } else {
      match
        (tables.get(reference.source_file), tables.get(reference.target_file)) {
        (Some(source), Some(target)) =>
          validate_dataset_reference(reference, source, target, issues)
        _ => ()
      }
    }
  }
  issues
}

///|
fn validate_dataset_table(
  rule : CsvDatasetTableRule,
  table : CsvTable,
  issues : Array[CsvDatasetIssue],
) -> Unit {
  if table.rows.length() < rule.minimum_rows {
    add_dataset_issue(
      issues,
      "minimum_rows",
      rule.file,
      None,
      "",
      table.rows.length().to_string(),
      "table has fewer records than the profile minimum",
    )
  }
  for column in rule.required_columns {
    if table.column_index(column) is None {
      add_missing_dataset_column(issues, rule.file, column)
    }
  }
  for column in rule.non_empty_columns {
    match table.column_index(column) {
      None => add_missing_dataset_column(issues, rule.file, column)
      Some(index) =>
        if !profile_key_has_column(rule.unique_keys, column) {
          for row in table.rows {
            if row.cells[index] == "" {
              add_dataset_issue(
                issues,
                "missing_required_value",
                rule.file,
                Some(row.line),
                column,
                "",
                "required field value is empty",
              )
            }
          }
        }
    }
  }
  for key_columns in rule.unique_keys {
    if key_columns.length() == 0 {
      add_dataset_issue(
        issues,
        "invalid_profile",
        rule.file,
        None,
        "unique_keys",
        "",
        "unique key rules must contain at least one column",
      )
    } else {
      let indices : Array[Int32] = []
      let mut key_is_available = true
      for column in key_columns {
        match table.column_index(column) {
          Some(index) => indices.push(index)
          None => {
            add_missing_dataset_column(issues, rule.file, column)
            key_is_available = false
          }
        }
      }
      if key_is_available {
        let first_lines : Map[String, Int32] = Map([])
        for row in table.rows {
          let mut has_empty_value = false
          let values : Array[String] = []
          for index in indices {
            let value = row.cells[index]
            values.push(value)
            if value == "" {
              has_empty_value = true
              add_dataset_issue(
                issues,
                "missing_key_value",
                rule.file,
                Some(row.line),
                table.headers[index],
                "",
                "unique key fields must not be empty",
              )
            }
          }
          if !has_empty_value {
            let encoded_key = encode_dataset_key(values)
            match first_lines.get(encoded_key) {
              Some(_) =>
                add_dataset_issue(
                  issues,
                  "duplicate_key",
                  rule.file,
                  Some(row.line),
                  join_dataset_strings(key_columns, ","),
                  join_dataset_strings(values, ","),
                  "key value is already used in this table",
                )
              None => first_lines.set(encoded_key, row.line)
            }
          }
        }
      }
    }
  }
}

///|
fn validate_dataset_reference(
  reference : CsvDatasetReferenceRule,
  source : CsvTable,
  target : CsvTable,
  issues : Array[CsvDatasetIssue],
) -> Unit {
  let source_index = source.column_index(reference.source_column)
  let target_index = target.column_index(reference.target_column)
  match source_index {
    None =>
      add_missing_dataset_column(
        issues,
        reference.source_file,
        reference.source_column,
      )
    Some(_) => ()
  }
  match target_index {
    None =>
      add_missing_dataset_column(
        issues,
        reference.target_file,
        reference.target_column,
      )
    Some(_) => ()
  }
  match (source_index, target_index) {
    (Some(from), Some(to)) => {
      let target_values : Map[String, Bool] = Map([])
      for row in target.rows {
        let value = row.cells[to]
        if value != "" {
          target_values.set(value, true)
        }
      }
      for row in source.rows {
        let value = row.cells[from]
        if value == "" {
          if reference.required {
            add_dataset_issue(
              issues,
              "missing_reference_value",
              reference.source_file,
              Some(row.line),
              reference.source_column,
              "",
              "required reference value is empty",
            )
          }
        } else if target_values.get(value) is None {
          add_dataset_issue(
            issues,
            "unresolved_reference",
            reference.source_file,
            Some(row.line),
            reference.source_column,
            value,
            "referenced value does not exist in " + reference.target_file,
          )
        }
      }
    }
    _ => ()
  }
}

///|
fn profile_has_unique_column(
  profile : CsvDatasetProfile,
  file : String,
  column : String,
) -> Bool {
  for rule in profile.tables {
    if rule.file == file {
      for key in rule.unique_keys {
        if key.length() == 1 && key[0] == column {
          return true
        }
      }
    }
  }
  false
}

///|
fn profile_key_has_column(keys : Array[Array[String]], column : String) -> Bool {
  for key in keys {
    if key.contains(column) {
      return true
    }
  }
  false
}

///|
fn encode_dataset_key(values : Array[String]) -> String {
  let mut encoded = ""
  for value in values {
    encoded = encoded + value.length().to_string() + ":" + value
  }
  encoded
}

///|
fn join_dataset_strings(values : Array[String], separator : String) -> String {
  let mut joined = ""
  for index, value in values {
    if index > 0 {
      joined = joined + separator
    }
    joined = joined + value
  }
  joined
}

///|
fn add_missing_dataset_column(
  issues : Array[CsvDatasetIssue],
  file : String,
  column : String,
) -> Unit {
  let mut already_reported = false
  for issue in issues {
    if issue.code == "missing_required_column" &&
      issue.file == file &&
      issue.column == column {
      already_reported = true
    }
  }
  if !already_reported {
    add_dataset_issue(
      issues,
      "missing_required_column",
      file,
      None,
      column,
      "",
      "required column is missing",
    )
  }
}

///|
fn add_dataset_issue(
  issues : Array[CsvDatasetIssue],
  code : String,
  file : String,
  line : Int32?,
  column : String,
  value : String,
  message : String,
) -> Unit {
  issues.push(CsvDatasetIssue::{ code, file, line, column, value, message, })
}
