///|
test "parses headers, rows, and CRLF endings" {
  let table = match
    @wayfarer.parse_csv("stop_id,stop_name\r\nA1,Central\r\nB2,Harbor\r\n") {
    Ok(table) => table
    Err(_) => fail("expected a valid CSV document")
  }
  assert_eq(table.headers.length(), 2)
  assert_eq(table.rows.length(), 2)
  assert_eq(table.rows[0].line, 2)
  assert_eq(table.rows[1].cells[1], "Harbor")
}

///|
test "parses commas, escaped quotes, and multiline values" {
  let table = match
    @wayfarer.parse_csv(
      "id,name,note\n1,\"Bay, North\",\"said \"\"hello\"\"\nnext\"\n",
    ) {
    Ok(table) => table
    Err(_) => fail("expected RFC-style quoted cells to parse")
  }
  assert_eq(table.rows[0].cells[1], "Bay, North")
  assert_eq(table.rows[0].cells[2], "said \"hello\"\nnext")
  assert_eq(table.rows[0].line, 2)
}

///|
test "accepts a UTF-8 BOM before the header" {
  let table = match
    @wayfarer.parse_csv("\u{feff}stop_id,stop_name\nA1,Central") {
    Ok(table) => table
    Err(_) => fail("expected a leading BOM to be ignored")
  }
  assert_eq(table.headers[0], "stop_id")
  assert_eq(table.rows.length(), 1)
}

///|
test "rejects duplicate headers" {
  match @wayfarer.parse_csv("stop_id,stop_id\nA1,A2") {
    Err(@wayfarer.CsvError::DuplicateHeader(name~, column~)) => {
      assert_eq(name, "stop_id")
      assert_eq(column, 2)
    }
    _ => fail("expected the duplicate column location")
  }
}

///|
test "rejects malformed quotes and reports their source location" {
  match @wayfarer.parse_csv("id,name\n1,\"open") {
    Err(@wayfarer.CsvError::UnterminatedQuote(line~, column~)) => {
      assert_eq(line, 2)
      assert_eq(column, 3)
    }
    _ => fail("expected an unterminated quote error")
  }
  match @wayfarer.parse_csv("id,name\n1,ab\"cd") {
    Err(@wayfarer.CsvError::UnexpectedQuote(line~, column~)) => {
      assert_eq(line, 2)
      assert_eq(column, 5)
    }
    _ => fail("expected an unexpected quote error")
  }
}

///|
test "rejects rows whose width differs from the header" {
  match @wayfarer.parse_csv("stop_id,stop_name\nA1,Central,extra") {
    Err(@wayfarer.CsvError::RowWidthMismatch(line~, expected~, actual~)) => {
      assert_eq(line, 2)
      assert_eq(expected, 2)
      assert_eq(actual, 3)
    }
    _ => fail("expected a row-width error")
  }
}

///|
test "rejects data after a closing quote" {
  match @wayfarer.parse_csv("id,name\n1,\"Central\" extra") {
    Err(@wayfarer.CsvError::CharactersAfterQuote(line~, column~)) => {
      assert_eq(line, 2)
      assert_eq(column, 12)
    }
    _ => fail("expected non-delimiter text after a quote to fail")
  }
}

///|
test "reports unsupported tables instead of silently passing them" {
  let table = match @wayfarer.parse_csv("stop_id\nA1") {
    Ok(table) => table
    Err(_) => fail("expected a valid CSV document")
  }
  let issues = @wayfarer.validate_schema("calendar_dates.txt", table)
  assert_eq(issues.length(), 1)
  assert_eq(issues[0].code, "unsupported_table")
}

///|
test "checks required GTFS columns without imposing row rules" {
  let table = match @wayfarer.parse_csv("platform_code,stop_name\nA1,2") {
    Ok(table) => table
    Err(_) => fail("expected a valid CSV document")
  }
  let issues = @wayfarer.validate_schema("stops.txt", table)
  assert_eq(issues.length(), 1)
  assert_eq(issues[0].column, "stop_id")
  assert_eq(issues[0].table, "stops.txt")
}
