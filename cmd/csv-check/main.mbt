///|
fn main {
  let args = @env.args()
  if args.length() != 3 && args.length() != 4 {
    println(
      "Usage: moon run cmd/csv-check <profile.json> <csv-dataset-directory> [--json]",
    )
    @sys.exit(2)
  }
  let json_mode = if args.length() == 4 {
    if args[3] == "--json" {
      true
    } else {
      println("ERROR " + args[3] + " [unknown_option] expected --json")
      @sys.exit(2)
      abort("unreachable")
    }
  } else {
    false
  }
  let profile_path = args[1]
  let directory = args[2]
  let directory_check : Result[Bool, @fs.IOError] = Ok(@fs.is_dir(directory)) catch {
    error => Err(error)
  }
  match directory_check {
    Err(_) =>
      fail_profile_input(
        json_mode,
        input_issue("", "directory_read_error", "cannot open input directory"),
      )
    Ok(false) =>
      fail_profile_input(
        json_mode,
        input_issue("", "invalid_directory", "input path is not a directory"),
      )
    Ok(true) => ()
  }
  let profile_source : Result[String, @fs.IOError] = Ok(
    @fs.read_file_to_string(profile_path),
  ) catch {
    error => Err(error)
  }
  let profile_text = match profile_source {
    Ok(source) => source
    Err(_) => {
      fail_profile_input(
        json_mode,
        input_issue("profile", "profile_read_error", "could not read profile"),
        text_file=profile_path,
      )
      abort("unreachable")
    }
  }
  let profile = match @wayfarer.parse_csv_dataset_profile(profile_text) {
    Ok(value) => value
    Err(message) => {
      fail_profile_input(
        json_mode,
        input_issue("profile", "invalid_profile", message),
        text_file=profile_path,
      )
      abort("unreachable")
    }
  }
  let tables : Map[String, @wayfarer.CsvTable] = Map([])
  let mut file_count = 0
  let mut record_count = 0
  let seen_files : Map[String, Bool] = Map([])
  let input_issues : Array[@wayfarer.CsvDatasetIssue] = []
  for rule in profile.tables {
    if seen_files.get(rule.file) is None {
      seen_files.set(rule.file, true)
      let path = directory + @path.sep.to_string() + rule.file
      if @fs.path_exists(path) {
        let source : Result[String, @fs.IOError] = Ok(
          @fs.read_file_to_string(path),
        ) catch {
          error => Err(error)
        }
        let text = match source {
          Ok(value) => value
          Err(_) => {
            input_issues.push(
              input_issue(rule.file, "read_error", "could not read CSV file"),
            )
            continue
          }
        }
        match @wayfarer.parse_csv(text) {
          Err(error) => input_issues.push(profile_csv_issue(rule.file, error))
          Ok(table) => {
            file_count = file_count + 1
            record_count = record_count + table.rows.length()
            tables.set(rule.file, table)
          }
        }
      }
    }
  }
  if input_issues.length() > 0 {
    if json_mode {
      println(@wayfarer.csv_dataset_issues_to_json(input_issues))
    } else {
      for issue in input_issues {
        print_input_issue(issue, issue.file)
      }
    }
    @sys.exit(2)
  }
  let issues = @wayfarer.validate_csv_dataset(profile, tables)
  if json_mode {
    println(@wayfarer.csv_dataset_issues_to_json(issues))
    if issues.length() != 0 {
      @sys.exit(1)
    }
    return
  }
  println("Wayfarer: checking CSV profile in " + directory)
  for issue in issues {
    let location = match issue.line {
      Some(line) => issue.file + ":" + line.to_string()
      None => issue.file
    }
    let column = if issue.column == "" { "" } else { " " + issue.column }
    let value = if issue.value == "" {
      ""
    } else {
      "=" + quote_profile_value(issue.value)
    }
    println(
      "ERROR " +
      location +
      column +
      value +
      " [" +
      issue.code +
      "] " +
      issue.message,
    )
  }
  if issues.length() == 0 {
    println(
      "PASS: " +
      file_count.to_string() +
      " CSV tables, " +
      record_count.to_string() +
      " records, 0 findings",
    )
  } else {
    println(
      "FAIL: " +
      file_count.to_string() +
      " CSV tables, " +
      record_count.to_string() +
      " records, " +
      issues.length().to_string() +
      (if issues.length() == 1 { " finding" } else { " findings" }),
    )
    @sys.exit(1)
  }
}

///|
fn input_issue(
  file : String,
  code : String,
  message : String,
  line? : Int32,
  column~ : String = "",
) -> @wayfarer.CsvDatasetIssue {
  { file, code, message, line, column, value: "", }
}

///|
fn fail_profile_input(
  json_mode : Bool,
  issue : @wayfarer.CsvDatasetIssue,
  text_file~ : String = "",
) -> Unit {
  if json_mode {
    println(@wayfarer.csv_dataset_issues_to_json([issue]))
  } else {
    print_input_issue(issue, text_file)
  }
  @sys.exit(2)
}

///|
fn print_input_issue(issue : @wayfarer.CsvDatasetIssue, file : String) -> Unit {
  if file == "" {
    println("ERROR: " + issue.message)
    return
  }
  let location = match issue.line {
    Some(line) => file + ":" + line.to_string()
    None => file
  }
  let location = if issue.column == "" {
    location
  } else {
    location + ":" + issue.column
  }
  println("ERROR " + location + " [" + issue.code + "] " + issue.message)
}

///|
fn profile_csv_issue(
  file : String,
  error : @wayfarer.CsvError,
) -> @wayfarer.CsvDatasetIssue {
  match error {
    @wayfarer.EmptyDocument =>
      input_issue(
        file,
        "csv_empty",
        "document has no header",
        line=1,
        column="1",
      )
    @wayfarer.EmptyHeader(line~, column~) =>
      input_issue(
        file,
        "csv_empty_header",
        "header is empty",
        line~,
        column=column.to_string(),
      )
    @wayfarer.DuplicateHeader(name~, column~) =>
      input_issue(
        file,
        "csv_duplicate_header",
        "duplicate header " + quote_profile_value(name),
        line=1,
        column=column.to_string(),
      )
    @wayfarer.UnexpectedQuote(line~, column~) =>
      input_issue(
        file,
        "csv_unexpected_quote",
        "unexpected quote",
        line~,
        column=column.to_string(),
      )
    @wayfarer.CharactersAfterQuote(line~, column~) =>
      input_issue(
        file,
        "csv_characters_after_quote",
        "data after closing quote",
        line~,
        column=column.to_string(),
      )
    @wayfarer.UnterminatedQuote(line~, column~) =>
      input_issue(
        file,
        "csv_unterminated_quote",
        "unterminated quoted field",
        line~,
        column=column.to_string(),
      )
    @wayfarer.RowWidthMismatch(line~, expected~, actual~) =>
      input_issue(
        file,
        "csv_row_width",
        "expected " +
        expected.to_string() +
        " cells, found " +
        actual.to_string(),
        line~,
      )
    @wayfarer.InvalidLineEnding(line~, column~) =>
      input_issue(
        file,
        "csv_invalid_line_ending",
        "only LF or CRLF may end a record",
        line~,
        column=column.to_string(),
      )
  }
}

///|
fn quote_profile_value(value : String) -> String {
  let escaped : Array[Char] = ['"']
  for character in value.to_array() {
    match character {
      '"' => {
        escaped.push('\\')
        escaped.push('"')
      }
      '\\' => {
        escaped.push('\\')
        escaped.push('\\')
      }
      '\t' => {
        escaped.push('\\')
        escaped.push('t')
      }
      '\r' => {
        escaped.push('\\')
        escaped.push('r')
      }
      '\n' => {
        escaped.push('\\')
        escaped.push('n')
      }
      _ => {
        let code = character.to_int()
        if code < 32 ||
          code == 127 ||
          (code >= 128 && code <= 159) ||
          code == 0x2028 ||
          code == 0x2029 {
          escaped.push('\\')
          escaped.push('u')
          escaped.push(profile_hex_digit(code / 4096))
          escaped.push(profile_hex_digit(code / 256 % 16))
          escaped.push(profile_hex_digit(code / 16 % 16))
          escaped.push(profile_hex_digit(code % 16))
        } else {
          escaped.push(character)
        }
      }
    }
  }
  escaped.push('"')
  String::from_array(escaped)
}

///|
fn profile_hex_digit(value : Int32) -> Char {
  "0123456789abcdef".to_array()[value]
}
