///| A decoded row in a comma-separated table. `line` is the physical source

///|
/// line where the record begins (quoted records may span multiple lines).
pub struct CsvRow {
  line : Int32
  cells : Array[String]
}

///|
/// A CSV document with its first record interpreted as the header.
pub struct CsvTable {
  headers : Array[String]
  rows : Array[CsvRow]
}

///|
/// A parser error with a stable source location.
pub enum CsvError {
  EmptyDocument
  EmptyHeader(line~ : Int32, column~ : Int32)
  DuplicateHeader(name~ : String, column~ : Int32)
  UnexpectedQuote(line~ : Int32, column~ : Int32)
  CharactersAfterQuote(line~ : Int32, column~ : Int32)
  UnterminatedQuote(line~ : Int32, column~ : Int32)
  RowWidthMismatch(line~ : Int32, expected~ : Int32, actual~ : Int32)
}

///| Parse a CSV document using RFC 4180 quoting rules.

///| CRLF and LF record endings are accepted; newlines inside quoted cells are

///| normalized to LF. Every data row must have the same number of cells as the

///|
/// header so downstream feed checks can rely on rectangular records.
pub fn parse_csv(source : String) -> Result[CsvTable, CsvError] {
  let chars = source.to_array()
  let mut index = 0
  let mut line = 1
  let mut column = 1
  let mut record_line = 1
  let mut quote_line = 1
  let mut quote_column = 1
  let mut in_quotes = false
  let mut after_quote = false
  let mut record_started = false
  let mut field = Array(capacity=0)
  let mut cells : Array[String] = []
  let mut headers : Array[String] = []
  let mut rows : Array[CsvRow] = []

  if chars.length() > 0 && chars[0] == '\u{feff}' {
    index = 1
    column = 2
  }

  while index < chars.length() {
    let ch = chars[index]
    if in_quotes {
      if ch == '"' {
        if index + 1 < chars.length() && chars[index + 1] == '"' {
          field.push('"')
          index = index + 2
          column = column + 2
        } else {
          in_quotes = false
          after_quote = true
          index = index + 1
          column = column + 1
        }
      } else if ch == '\r' || ch == '\n' {
        field.push('\n')
        if ch == '\r' && index + 1 < chars.length() && chars[index + 1] == '\n' {
          index = index + 2
        } else {
          index = index + 1
        }
        line = line + 1
        column = 1
      } else {
        field.push(ch)
        index = index + 1
        column = column + 1
      }
    } else if after_quote {
      if ch == ',' {
        cells.push(String::from_array(field))
        field = Array(capacity=0)
        after_quote = false
        record_started = true
        index = index + 1
        column = column + 1
      } else if ch == '\r' || ch == '\n' {
        cells.push(String::from_array(field))
        field = Array(capacity=0)
        after_quote = false
        index = index + 1
        if ch == '\r' && index < chars.length() && chars[index] == '\n' {
          index = index + 1
        }
        match finish_csv_record(cells, headers, rows, record_line) {
          Ok((next_headers, next_rows)) => {
            headers = next_headers
            rows = next_rows
          }
          Err(error) => return Err(error)
        }
        cells = []
        line = line + 1
        column = 1
        record_line = line
        record_started = false
      } else {
        return Err(CsvError::CharactersAfterQuote(line~, column~))
      }
    } else if ch == '"' {
      if field.length() != 0 {
        return Err(CsvError::UnexpectedQuote(line~, column~))
      }
      in_quotes = true
      quote_line = line
      quote_column = column
      record_started = true
      index = index + 1
      column = column + 1
    } else if ch == ',' {
      cells.push(String::from_array(field))
      field = Array(capacity=0)
      record_started = true
      index = index + 1
      column = column + 1
    } else if ch == '\r' || ch == '\n' {
      cells.push(String::from_array(field))
      field = Array(capacity=0)
      index = index + 1
      if ch == '\r' && index < chars.length() && chars[index] == '\n' {
        index = index + 1
      }
      match finish_csv_record(cells, headers, rows, record_line) {
        Ok((next_headers, next_rows)) => {
          headers = next_headers
          rows = next_rows
        }
        Err(error) => return Err(error)
      }
      cells = []
      line = line + 1
      column = 1
      record_line = line
      record_started = false
    } else {
      field.push(ch)
      record_started = true
      index = index + 1
      column = column + 1
    }
  }

  if in_quotes {
    return Err(
      CsvError::UnterminatedQuote(line=quote_line, column=quote_column),
    )
  }
  if record_started || after_quote || cells.length() > 0 || field.length() > 0 {
    cells.push(String::from_array(field))
    match finish_csv_record(cells, headers, rows, record_line) {
      Ok((next_headers, next_rows)) => {
        headers = next_headers
        rows = next_rows
      }
      Err(error) => return Err(error)
    }
  }
  if headers.length() == 0 {
    return Err(CsvError::EmptyDocument)
  }
  Ok(CsvTable::{ headers, rows, })
}

///|
fn finish_csv_record(
  cells : Array[String],
  headers : Array[String],
  rows : Array[CsvRow],
  line : Int32,
) -> Result[(Array[String], Array[CsvRow]), CsvError] {
  if headers.length() == 0 {
    if cells.length() == 0 || (cells.length() == 1 && cells[0] == "") {
      return Err(CsvError::EmptyHeader(line~, column=1))
    }
    let seen : Array[String] = []
    for i, header in cells {
      if header == "" {
        return Err(CsvError::EmptyHeader(line~, column=i + 1))
      }
      if seen.contains(header) {
        return Err(CsvError::DuplicateHeader(name=header, column=i + 1))
      }
      seen.push(header)
    }
    Ok((cells, rows))
  } else {
    if cells.length() != headers.length() {
      return Err(
        CsvError::RowWidthMismatch(
          line~,
          expected=headers.length(),
          actual=cells.length(),
        ),
      )
    }
    let next_rows = rows
    next_rows.push(CsvRow::{ line, cells, })
    Ok((headers, next_rows))
  }
}

///|
/// Return the index of a named column, if present.
pub fn CsvTable::column_index(self : CsvTable, name : String) -> Int32? {
  for index, header in self.headers {
    if header == name {
      return Some(index)
    }
  }
  None
}

///|
/// Return a cell by its header name, or `None` when the column is absent.
pub fn CsvRow::get(self : CsvRow, table : CsvTable, name : String) -> String? {
  match table.column_index(name) {
    Some(index) => Some(self.cells[index])
    None => None
  }
}
