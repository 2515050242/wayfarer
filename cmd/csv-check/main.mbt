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
    Err(_) => {
      println("ERROR: cannot open input directory")
      @sys.exit(2)
    }
    Ok(false) => {
      println("ERROR: input path is not a directory")
      @sys.exit(2)
    }
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
      println(
        "ERROR " + profile_path + " [profile_read_error] could not read profile",
      )
      @sys.exit(2)
      abort("unreachable")
    }
  }
  let profile = match @wayfarer.parse_csv_dataset_profile(profile_text) {
    Ok(value) => value
    Err(message) => {
      println("ERROR " + profile_path + " [invalid_profile] " + message)
      @sys.exit(2)
      abort("unreachable")
    }
  }
  let tables : Map[String, @wayfarer.CsvTable] = Map([])
  let mut file_count = 0
  let mut record_count = 0
  let seen_files : Map[String, Bool] = Map([])
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
            println(
              "ERROR " + rule.file + " [read_error] could not read CSV file",
            )
            @sys.exit(2)
            abort("unreachable")
          }
        }
        match @wayfarer.parse_csv(text) {
          Err(error) => {
            print_profile_csv_error(rule.file, error)
            @sys.exit(2)
          }
          Ok(table) => {
            file_count = file_count + 1
            record_count = record_count + table.rows.length()
            tables.set(rule.file, table)
          }
        }
      }
    }
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
fn print_profile_csv_error(
  filename : String,
  error : @wayfarer.CsvError,
) -> Unit {
  match error {
    @wayfarer.EmptyDocument =>
      println("ERROR " + filename + ":1:1 [csv_empty] document has no header")
    @wayfarer.EmptyHeader(line~, column~) =>
      println(
        "ERROR " +
        filename +
        ":" +
        line.to_string() +
        ":" +
        column.to_string() +
        " [csv_empty_header] header is empty",
      )
    @wayfarer.DuplicateHeader(name~, column~) =>
      println(
        "ERROR " +
        filename +
        ":1:" +
        column.to_string() +
        " [csv_duplicate_header] duplicate header " +
        quote_profile_value(name),
      )
    @wayfarer.UnexpectedQuote(line~, column~) =>
      println(
        "ERROR " +
        filename +
        ":" +
        line.to_string() +
        ":" +
        column.to_string() +
        " [csv_unexpected_quote] unexpected quote",
      )
    @wayfarer.CharactersAfterQuote(line~, column~) =>
      println(
        "ERROR " +
        filename +
        ":" +
        line.to_string() +
        ":" +
        column.to_string() +
        " [csv_characters_after_quote] data after closing quote",
      )
    @wayfarer.UnterminatedQuote(line~, column~) =>
      println(
        "ERROR " +
        filename +
        ":" +
        line.to_string() +
        ":" +
        column.to_string() +
        " [csv_unterminated_quote] unterminated quoted field",
      )
    @wayfarer.RowWidthMismatch(line~, expected~, actual~) =>
      println(
        "ERROR " +
        filename +
        ":" +
        line.to_string() +
        " [csv_row_width] expected " +
        expected.to_string() +
        " cells, found " +
        actual.to_string(),
      )
    @wayfarer.InvalidLineEnding(line~, column~) =>
      println(
        "ERROR " +
        filename +
        ":" +
        line.to_string() +
        ":" +
        column.to_string() +
        " [csv_invalid_line_ending] only LF or CRLF may end a record",
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
