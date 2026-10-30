///|
/// Encode dataset findings as a machine-readable JSON report.
///
/// The report contains one object per finding with its stable code, source
/// file, physical line (`null` for file-level findings), column, value, and
/// message, followed by the finding count and the overall `passed` status.
/// Keys are emitted in a fixed order and the result is valid JSON.
pub fn csv_dataset_issues_to_json(issues : Array[CsvDatasetIssue]) -> String {
  let builder = StringBuilder()
  builder.write_string("{")
  write_report_key(builder, "findings")
  builder.write_string("[")
  for index, issue in issues {
    if index > 0 {
      builder.write_string(",")
    }
    builder.write_string("{")
    write_report_key(builder, "code")
    write_report_json_string(builder, issue.code)
    builder.write_string(",")
    write_report_key(builder, "file")
    write_report_json_string(builder, issue.file)
    builder.write_string(",")
    write_report_key(builder, "line")
    match issue.line {
      Some(line) => builder.write_string(line.to_string())
      None => builder.write_string("null")
    }
    builder.write_string(",")
    write_report_key(builder, "column")
    write_report_json_string(builder, issue.column)
    builder.write_string(",")
    write_report_key(builder, "value")
    write_report_json_string(builder, issue.value)
    builder.write_string(",")
    write_report_key(builder, "message")
    write_report_json_string(builder, issue.message)
    builder.write_string("}")
  }
  builder.write_string("],")
  write_report_key(builder, "count")
  builder.write_string(issues.length().to_string())
  builder.write_string(",")
  write_report_key(builder, "passed")
  builder.write_string(if issues.length() == 0 { "true" } else { "false" })
  builder.write_string("}")
  builder.to_string()
}

///|
fn write_report_key(builder : StringBuilder, key : String) -> Unit {
  write_report_json_string(builder, key)
  builder.write_char(':')
}

///|
fn write_report_json_string(builder : StringBuilder, value : String) -> Unit {
  builder.write_char('"')
  for character in value.to_array() {
    match character.to_int() {
      34 => write_report_escaped(builder, '"')
      92 => write_report_escaped(builder, report_backslash_char())
      10 => write_report_escaped(builder, 'n')
      13 => write_report_escaped(builder, 'r')
      9 => write_report_escaped(builder, 't')
      code =>
        if code < 32 || code == 127 {
          builder.write_string(report_unicode_escape(code))
        } else {
          builder.write_char(character)
        }
    }
  }
  builder.write_char('"')
}

///|
fn write_report_escaped(builder : StringBuilder, character : Char) -> Unit {
  builder.write_char(report_backslash_char())
  builder.write_char(character)
}

///|
fn report_backslash_char() -> Char {
  Int32::unsafe_to_char(92)
}

///|
fn report_unicode_escape(code : Int32) -> String {
  let digits = "0123456789abcdef"
  let builder = StringBuilder()
  builder.write_char(report_backslash_char())
  builder.write_char('u')
  builder.write_char(digits.to_array()[code / 16 % 16])
  builder.write_char(digits.to_array()[code % 16])
  builder.to_string()
}
