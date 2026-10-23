///|
fn main {
  let args = @env.args()
  if args.length() != 2 {
    println("Usage: moon run cmd/main <gtfs-directory>")
    @sys.exit(2)
  }

  let directory = args[1]
  let directory_check : Result[Bool, @fs.IOError] = Ok(@fs.is_dir(directory)) catch {
    error => Err(error)
  }
  match directory_check {
    Err(_) => {
      println("ERROR: cannot open input directory: " + directory)
      @sys.exit(2)
    }
    Ok(false) => {
      println("ERROR: input path is not a directory: " + directory)
      @sys.exit(2)
    }
    Ok(true) => ()
  }

  let filenames = [
    "agency.txt", "stops.txt", "routes.txt", "trips.txt", "stop_times.txt", "calendar.txt",
    "calendar_dates.txt",
  ]
  let required = [
    "agency.txt", "stops.txt", "routes.txt", "trips.txt", "stop_times.txt",
  ]
  let tables : Map[String, @wayfarer.CsvTable] = Map([])
  let mut finding_count = 0
  let mut record_count = 0
  let mut file_count = 0

  println("Wayfarer: checking " + directory)
  for filename in filenames {
    let path = directory + @path.sep.to_string() + filename
    if @fs.path_exists(path) {
      let source : Result[String, @fs.IOError] = Ok(
        @fs.read_file_to_string(path),
      ) catch {
        error => Err(error)
      }
      match source {
        Err(_) => {
          println("ERROR " + filename + " [read_error] could not read file")
          finding_count = finding_count + 1
        }
        Ok(text) =>
          match @wayfarer.parse_csv(text) {
            Err(error) => {
              print_csv_error(filename, error)
              finding_count = finding_count + 1
            }
            Ok(table) => {
              file_count = file_count + 1
              record_count = record_count + table.rows.length()
              tables.set(filename, table)
              for issue in @wayfarer.validate_schema(filename, table) {
                println(
                  "ERROR " +
                  filename +
                  ":header." +
                  issue.column +
                  " [" +
                  issue.code +
                  "] " +
                  issue.message,
                )
                finding_count = finding_count + 1
              }
            }
          }
      }
    } else if required.contains(filename) {
      println("ERROR " + filename + " [missing_file] required file is missing")
      finding_count = finding_count + 1
    }
  }

  let feed = @wayfarer.GtfsTables::with_services(
    tables.get("stops.txt"),
    tables.get("routes.txt"),
    tables.get("trips.txt"),
    tables.get("stop_times.txt"),
    tables.get("calendar.txt"),
    tables.get("calendar_dates.txt"),
  )
  for issue in @wayfarer.validate_feed(feed) {
    println(
      "ERROR " +
      issue.file +
      ":" +
      issue.line.to_string() +
      " " +
      issue.column +
      "=\"" +
      issue.value +
      "\" [" +
      issue.code +
      "] " +
      issue.message,
    )
    finding_count = finding_count + 1
  }

  if finding_count == 0 {
    println(
      "PASS (supported checks only): " +
      file_count.to_string() +
      " parsed files, " +
      record_count.to_string() +
      " records, 0 findings",
    )
  } else {
    println(
      "FAIL: " +
      file_count.to_string() +
      " parsed files, " +
      record_count.to_string() +
      " records, " +
      finding_count.to_string() +
      " findings",
    )
    @sys.exit(1)
  }
}

///|
fn print_csv_error(filename : String, error : @wayfarer.CsvError) -> Unit {
  match error {
    EmptyDocument =>
      println("ERROR " + filename + ":1:1 [csv_empty] document has no header")
    EmptyHeader(line~, column~) =>
      println(
        "ERROR " +
        filename +
        ":" +
        line.to_string() +
        ":" +
        column.to_string() +
        " [csv_empty_header] header is empty",
      )
    DuplicateHeader(name~, column~) =>
      println(
        "ERROR " +
        filename +
        ":1:" +
        column.to_string() +
        " [csv_duplicate_header] duplicate header \"" +
        name +
        "\"",
      )
    UnexpectedQuote(line~, column~) =>
      println(
        "ERROR " +
        filename +
        ":" +
        line.to_string() +
        ":" +
        column.to_string() +
        " [csv_unexpected_quote] unexpected quote",
      )
    CharactersAfterQuote(line~, column~) =>
      println(
        "ERROR " +
        filename +
        ":" +
        line.to_string() +
        ":" +
        column.to_string() +
        " [csv_characters_after_quote] data after closing quote",
      )
    UnterminatedQuote(line~, column~) =>
      println(
        "ERROR " +
        filename +
        ":" +
        line.to_string() +
        ":" +
        column.to_string() +
        " [csv_unterminated_quote] unterminated quoted field",
      )
    RowWidthMismatch(line~, expected~, actual~) =>
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
  }
}
