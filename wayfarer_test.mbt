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
test "rejects a bare carriage return between CSV records" {
  match @wayfarer.parse_csv("id,name\r1,A") {
    Err(@wayfarer.CsvError::InvalidLineEnding(line~, column~)) => {
      assert_eq(line, 1)
      assert_eq(column, 8)
    }
    _ => fail("expected a bare CR record ending to be rejected")
  }
}

///|
test "rejects a bare CR record ending after a quoted field" {
  match @wayfarer.parse_csv("id,name\n1,\"A\"\r") {
    Err(@wayfarer.CsvError::InvalidLineEnding(line~, column~)) => {
      assert_eq(line, 2)
      assert_eq(column, 6)
    }
    _ => fail("expected a bare CR record ending after a quoted field to fail")
  }
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
test "checks required columns for calendar_dates" {
  let table = match @wayfarer.parse_csv("date,exception_type\n20260101,1") {
    Ok(table) => table
    Err(_) => fail("expected a valid CSV document")
  }
  let issues = @wayfarer.validate_schema("calendar_dates.txt", table)
  assert_eq(issues.length(), 1)
  assert_eq(issues[0].code, "missing_required_header")
  assert_eq(issues[0].column, "service_id")
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

///|
test "reports quoted and unquoted field controls at their source record" {
  let table = parse_test_table(
    "id,name\n1,\"Platform \"\"East\"\"\tA\"\n2,\"North\r\nAnnex\"\n3,South\tGate",
  )
  let issues = @wayfarer.validate_gtfs_field_values("stops.txt", table)
  assert_eq(issues.length(), 3)
  assert_eq(issues[0].code, "forbidden_field_character")
  assert_eq(issues[0].file, "stops.txt")
  assert_eq(issues[0].line, 2)
  assert_eq(issues[0].column, "name")
  assert_eq(issues[0].value, "Platform \"East\"\tA")
  assert_eq(issues[1].line, 3)
  assert_eq(issues[1].column, "name")
  assert_eq(issues[1].value, "North\nAnnex")
  assert_eq(issues[2].line, 5)
  assert_eq(issues[2].column, "name")
  assert_eq(issues[2].value, "South\tGate")
}

///|
test "normalizes quoted CR and rejects it as a GTFS field value" {
  let table = parse_test_table("stop_id,stop_name\nS1,\"North\rAnnex\"")
  let issues = @wayfarer.validate_gtfs_field_values("stops.txt", table)
  assert_eq(issues.length(), 1)
  assert_eq(issues[0].line, 2)
  assert_eq(issues[0].column, "stop_name")
  assert_eq(issues[0].value, "North\nAnnex")
}

///|
test "accepts LF and CRLF as CSV record separators for GTFS tables" {
  let lf = parse_test_table("stop_id,stop_name\nS1,Central\n")
  let crlf = parse_test_table("stop_id,stop_name\r\nS1,Central\r\n")
  assert_eq(@wayfarer.validate_gtfs_field_values("stops.txt", lf).length(), 0)
  assert_eq(@wayfarer.validate_gtfs_field_values("stops.txt", crlf).length(), 0)
}

///|
fn parse_test_table(source : String) -> @wayfarer.CsvTable {
  match @wayfarer.parse_csv(source) {
    Ok(table) => table
    Err(_) => abort("expected fixture CSV to parse")
  }
}

///|
fn make_gtfs_tables(
  stops : String,
  routes : String,
  trips : String,
  stop_times : String,
) -> @wayfarer.GtfsTables {
  @wayfarer.GtfsTables::new(
    Some(parse_test_table(stops)),
    Some(parse_test_table(routes)),
    Some(parse_test_table(trips)),
    Some(parse_test_table(stop_times)),
  )
}

///|
fn valid_gtfs_tables() -> @wayfarer.GtfsTables {
  make_gtfs_tables(
    "stop_id\nS1\nS2", "route_id\nR1", "route_id,service_id,trip_id\nR1,WK,T1", "trip_id,stop_sequence,stop_id,arrival_time\nT1,1,S1,9:00:00\nT1,2,S2,9:10:00",
  )
}

///|
test "validates references across a minimal feed" {
  let issues = @wayfarer.validate_feed(valid_gtfs_tables())
  assert_eq(issues.length(), 0)
}

///|
test "requires at least two stop-time records for each trip" {
  let one_stop = make_gtfs_tables(
    "stop_id\nS1", "route_id\nR1", "route_id,service_id,trip_id\nR1,WK,T1", "trip_id,stop_sequence,stop_id,arrival_time\nT1,1,S1,9:00:00",
  )
  let issues = @wayfarer.validate_feed(one_stop)
  assert_eq(issues.length(), 1)
  assert_eq(issues[0].code, "insufficient_stop_times")
  assert_eq(issues[0].file, "trips.txt")
  assert_eq(issues[0].line, 2)
  assert_eq(issues[0].column, "trip_id")
  assert_eq(issues[0].value, "T1")
}

///|
test "reports a trip with no stop-time records" {
  let no_stop_times = make_gtfs_tables(
    "stop_id\nS1\nS2", "route_id\nR1", "route_id,service_id,trip_id\nR1,WK,T1", "trip_id,stop_sequence,stop_id,arrival_time",
  )
  let issues = @wayfarer.validate_feed(no_stop_times)
  assert_eq(issues.length(), 1)
  assert_eq(issues[0].code, "insufficient_stop_times")
  assert_eq(issues[0].value, "T1")
}

///|
test "resolves trip service IDs from calendar or calendar_dates" {
  let trips = parse_test_table("route_id,service_id,trip_id\nR1,WK,T1")
  let calendar = parse_test_table("service_id\nWK")
  let calendar_dates = parse_test_table(
    "service_id,date,exception_type\nWK,20260101,1\nWK,20260102,2",
  )
  let from_calendar = @wayfarer.validate_feed(
    @wayfarer.GtfsTables::with_services(
      None,
      None,
      Some(trips),
      None,
      Some(calendar),
      None,
    ),
  )
  assert_eq(from_calendar.length(), 0)
  let from_dates = @wayfarer.validate_feed(
    @wayfarer.GtfsTables::with_services(
      None,
      None,
      Some(trips),
      None,
      None,
      Some(calendar_dates),
    ),
  )
  assert_eq(from_dates.length(), 0)
}

///|
test "accepts service IDs supplied across both calendar tables" {
  let trips = parse_test_table(
    "route_id,service_id,trip_id\nR1,WEEK,T1\nR1,EXTRA,T2",
  )
  let calendar = parse_test_table("service_id\nWEEK")
  let calendar_dates = parse_test_table(
    "service_id,date,exception_type\nEXTRA,20260101,1",
  )
  let issues = @wayfarer.validate_feed(
    @wayfarer.GtfsTables::with_services(
      None,
      None,
      Some(trips),
      None,
      Some(calendar),
      Some(calendar_dates),
    ),
  )
  assert_eq(issues.length(), 0)
}

///|
test "rejects duplicate calendar_dates service and date pairs" {
  let trips = parse_test_table("route_id,service_id,trip_id\nR1,WK,T1")
  let calendar_dates = parse_test_table(
    "service_id,date,exception_type\nWK,20260101,1\nWK,20260101,2",
  )
  let issues = @wayfarer.validate_feed(
    @wayfarer.GtfsTables::with_services(
      None,
      None,
      Some(trips),
      None,
      None,
      Some(calendar_dates),
    ),
  )
  assert_eq(issues.length(), 1)
  assert_eq(issues[0].code, "duplicate_primary_key")
  assert_eq(issues[0].file, "calendar_dates.txt")
  assert_eq(issues[0].line, 3)
  assert_eq(issues[0].column, "service_id,date")
  assert_eq(issues[0].value, "WK,20260101")
}

///|
test "reports an empty calendar_dates date at its source row" {
  let calendar_dates = parse_test_table("service_id,date,exception_type\nWK,,1")
  let issues = @wayfarer.validate_feed(
    @wayfarer.GtfsTables::with_services(
      None,
      None,
      None,
      None,
      None,
      Some(calendar_dates),
    ),
  )
  assert_eq(issues.length(), 1)
  assert_eq(issues[0].code, "empty_primary_key")
  assert_eq(issues[0].file, "calendar_dates.txt")
  assert_eq(issues[0].line, 2)
  assert_eq(issues[0].column, "date")
  assert_eq(issues[0].value, "")
}

///|
test "leaves a missing calendar_dates date column to schema validation" {
  let calendar_dates = parse_test_table("service_id,exception_type\nWK,1")
  let schema_issues = @wayfarer.validate_schema(
    "calendar_dates.txt", calendar_dates,
  )
  assert_eq(schema_issues.length(), 1)
  assert_eq(schema_issues[0].code, "missing_required_header")
  assert_eq(schema_issues[0].column, "date")
  let feed_issues = @wayfarer.validate_feed(
    @wayfarer.GtfsTables::with_services(
      None,
      None,
      None,
      None,
      None,
      Some(calendar_dates),
    ),
  )
  assert_eq(feed_issues.length(), 0)
}

///|
test "reports a trip service ID absent from supplied calendar tables" {
  let trips = parse_test_table("route_id,service_id,trip_id\nR1,MISSING,T1")
  let calendar = parse_test_table("service_id\nWK")
  let issues = @wayfarer.validate_feed(
    @wayfarer.GtfsTables::with_services(
      None,
      None,
      Some(trips),
      None,
      Some(calendar),
      None,
    ),
  )
  assert_eq(issues.length(), 1)
  assert_eq(issues[0].code, "unresolved_reference")
  assert_eq(issues[0].file, "trips.txt")
  assert_eq(issues[0].line, 2)
  assert_eq(issues[0].column, "service_id")
  assert_eq(issues[0].value, "MISSING")
}

///|
test "reports duplicate primary keys and the composite stop time key" {
  let tables = @wayfarer.GtfsTables::{
    stops: Some(parse_test_table("stop_id\nS1\nS1")),
    routes: Some(parse_test_table("route_id\nR1\nR1")),
    trips: Some(
      parse_test_table("route_id,service_id,trip_id\nR1,WK,T1\nR1,WK,T1"),
    ),
    stop_times: Some(
      parse_test_table(
        "trip_id,stop_sequence,stop_id,arrival_time\nT1,1,S1,9:00:00\nT1,1,S1,9:00:00",
      ),
    ),
    calendar: None,
    calendar_dates: None,
  }
  let issues = @wayfarer.validate_feed(tables)
  assert_eq(issues.length(), 4)
  assert_eq(issues[0].code, "duplicate_primary_key")
  assert_eq(issues[0].file, "stops.txt")
  assert_eq(issues[0].line, 3)
  assert_eq(issues[0].column, "stop_id")
  assert_eq(issues[1].file, "routes.txt")
  assert_eq(issues[2].file, "trips.txt")
  assert_eq(issues[3].file, "stop_times.txt")
  assert_eq(issues[3].column, "stop_sequence")
}

///|
test "detects each core duplicate key in isolation" {
  let duplicate_stops = @wayfarer.validate_feed(
    @wayfarer.GtfsTables::new(
      Some(parse_test_table("stop_id\nS1\nS1")),
      None,
      None,
      None,
    ),
  )
  assert_eq(duplicate_stops.length(), 1)
  assert_eq(duplicate_stops[0].file, "stops.txt")
  let duplicate_routes = @wayfarer.validate_feed(
    @wayfarer.GtfsTables::new(
      None,
      Some(parse_test_table("route_id\nR1\nR1")),
      None,
      None,
    ),
  )
  assert_eq(duplicate_routes.length(), 1)
  assert_eq(duplicate_routes[0].file, "routes.txt")
  let duplicate_trips = @wayfarer.validate_feed(
    @wayfarer.GtfsTables::new(
      None,
      None,
      Some(parse_test_table("route_id,service_id,trip_id\nR1,WK,T1\nR1,WK,T1")),
      None,
    ),
  )
  assert_eq(duplicate_trips.length(), 1)
  assert_eq(duplicate_trips[0].file, "trips.txt")
  let duplicate_sequence = @wayfarer.validate_feed(
    @wayfarer.GtfsTables::new(
      None,
      None,
      None,
      Some(parse_test_table("trip_id,stop_sequence,stop_id\nT1,1,S1\nT1,1,S1")),
    ),
  )
  assert_eq(duplicate_sequence.length(), 1)
  assert_eq(duplicate_sequence[0].file, "stop_times.txt")
}

///|
test "reports a trip whose route does not exist" {
  let tables = valid_gtfs_tables()
  let trips = parse_test_table("route_id,service_id,trip_id\nMISSING,WK,T1")
  let issues = @wayfarer.validate_feed(@wayfarer.GtfsTables::{
    ..tables,
    trips: Some(trips),
  })
  assert_eq(issues.length(), 1)
  assert_eq(issues[0].code, "unresolved_reference")
  assert_eq(issues[0].file, "trips.txt")
  assert_eq(issues[0].line, 2)
  assert_eq(issues[0].column, "route_id")
  assert_eq(issues[0].value, "MISSING")
}

///|
test "reports a stop time whose trip does not exist" {
  let tables = valid_gtfs_tables()
  let stop_times = parse_test_table(
    "trip_id,stop_sequence,stop_id,arrival_time\nMISSING,1,S1,8:00:00\nT1,1,S1,9:00:00\nT1,2,S2,9:10:00",
  )
  let issues = @wayfarer.validate_feed(@wayfarer.GtfsTables::{
    ..tables,
    stop_times: Some(stop_times),
  })
  assert_eq(issues.length(), 1)
  assert_eq(issues[0].file, "stop_times.txt")
  assert_eq(issues[0].column, "trip_id")
}

///|
test "reports an unresolved stop and requires stop ids in the fixed-stop profile" {
  let tables = valid_gtfs_tables()
  let missing_stop = parse_test_table(
    "trip_id,stop_sequence,stop_id,arrival_time\nT1,1,MISSING,9:00:00\nT1,2,S2,9:10:00",
  )
  let missing_issues = @wayfarer.validate_feed(@wayfarer.GtfsTables::{
    ..tables,
    stop_times: Some(missing_stop),
  })
  assert_eq(missing_issues.length(), 1)
  assert_eq(missing_issues[0].column, "stop_id")
  let location_group = parse_test_table(
    "trip_id,stop_sequence,stop_id,arrival_time\nT1,1,,9:00:00\nT1,2,S2,9:10:00",
  )
  let empty_issues = @wayfarer.validate_feed(@wayfarer.GtfsTables::{
    ..tables,
    stop_times: Some(location_group),
  })
  assert_eq(empty_issues.length(), 1)
  assert_eq(empty_issues[0].code, "empty_foreign_key")
  assert_eq(empty_issues[0].file, "stop_times.txt")
  assert_eq(empty_issues[0].line, 2)
  assert_eq(empty_issues[0].column, "stop_id")
}

///|
test "accepts stop-time references to stops and platforms only" {
  let stops = parse_test_table("stop_id,location_type\nS1,\nS2,0\nSTATION,1")
  let stop_times = parse_test_table(
    "trip_id,stop_sequence,stop_id,arrival_time\nT1,1,S1,9:00:00\nT2,1,S2,9:00:00",
  )
  let issues = @wayfarer.validate_feed(
    @wayfarer.GtfsTables::new(Some(stops), None, None, Some(stop_times)),
  )
  assert_eq(issues.length(), 0)
}

///|
test "rejects a stop-time reference to a station" {
  let tables = @wayfarer.GtfsTables::new(
    Some(parse_test_table("stop_id,location_type\nSTATION,1")),
    None,
    None,
    Some(
      parse_test_table(
        "trip_id,stop_sequence,stop_id,arrival_time\nT1,1,STATION,9:00:00",
      ),
    ),
  )
  let issues = @wayfarer.validate_feed(tables)
  assert_eq(issues.length(), 1)
  assert_eq(issues[0].code, "invalid_stop_location_type")
  assert_eq(issues[0].line, 2)
  assert_eq(issues[0].column, "stop_id")
  assert_eq(issues[0].value, "STATION")
}

///|
test "rejects flexible-location stop-time records as unsupported" {
  let tables = @wayfarer.GtfsTables::new(
    Some(parse_test_table("stop_id\nS1")),
    None,
    None,
    Some(
      parse_test_table(
        "trip_id,stop_sequence,location_id,arrival_time\nT1,1,ZONE,9:00:00",
      ),
    ),
  )
  let issues = @wayfarer.validate_feed(tables)
  assert_eq(issues.length(), 1)
  assert_eq(issues[0].code, "unsupported_location_profile")
  assert_eq(issues[0].file, "stop_times.txt")
  assert_eq(issues[0].line, 2)
  assert_eq(issues[0].column, "location_id")
  assert_eq(issues[0].value, "ZONE")
}

///|
test "rejects location-group rows and does not also require stop_id" {
  let tables = @wayfarer.GtfsTables::new(
    Some(parse_test_table("stop_id\nS1")),
    None,
    None,
    Some(
      parse_test_table(
        "trip_id,stop_sequence,stop_id,location_group_id,arrival_time\nT1,1,,LG1,9:00:00",
      ),
    ),
  )
  let issues = @wayfarer.validate_feed(tables)
  assert_eq(issues.length(), 1)
  assert_eq(issues[0].code, "unsupported_location_profile")
  assert_eq(issues[0].column, "location_group_id")
  assert_eq(issues[0].value, "LG1")
}

///|
test "treats an omitted location_type column as a stop" {
  let tables = @wayfarer.GtfsTables::new(
    Some(parse_test_table("stop_id\nS1")),
    None,
    None,
    Some(
      parse_test_table(
        "trip_id,stop_sequence,stop_id,arrival_time\nT1,1,S1,9:00:00",
      ),
    ),
  )
  assert_eq(@wayfarer.validate_feed(tables).length(), 0)
}

///|
test "requires the stop_id header in a fixed-stop feed" {
  let tables = @wayfarer.GtfsTables::new(
    None,
    None,
    None,
    Some(parse_test_table("trip_id,stop_sequence,arrival_time\nT1,1,9:00:00")),
  )
  let issues = @wayfarer.validate_feed(tables)
  assert_eq(issues.length(), 1)
  assert_eq(issues[0].code, "missing_required_header")
  assert_eq(issues[0].line, 1)
  assert_eq(issues[0].column, "stop_id")
}

///|
test "skips references when their target table is not supplied" {
  let tables = @wayfarer.GtfsTables::new(
    None,
    None,
    Some(parse_test_table("route_id,service_id,trip_id\nR1,WK,T1")),
    None,
  )
  let issues = @wayfarer.validate_feed(tables)
  assert_eq(issues.length(), 0)
}

///|
test "reports an empty required trip route reference" {
  let tables = make_gtfs_tables(
    "stop_id\nS1\nS2", "route_id\nR1", "route_id,service_id,trip_id\n,WK,T1", "trip_id,stop_sequence,stop_id,arrival_time\nT1,1,S1,9:00:00\nT1,2,S2,9:10:00",
  )
  let issues = @wayfarer.validate_feed(tables)
  assert_eq(issues.length(), 1)
  assert_eq(issues[0].code, "empty_foreign_key")
  assert_eq(issues[0].line, 2)
  assert_eq(issues[0].column, "route_id")
}

///|
fn validate_stop_time_fixture(source : String) -> Array[@wayfarer.FeedIssue] {
  @wayfarer.validate_feed(
    @wayfarer.GtfsTables::new(None, None, None, Some(parse_test_table(source))),
  )
}

///|
test "accepts sequence gaps and service-day times after midnight" {
  let issues = validate_stop_time_fixture(
    "trip_id,stop_sequence,arrival_time,departure_time,stop_id\nT1,0,23:59:00,23:59:00,S1\nT1,25,25:35:00,25:36:00,S1",
  )
  assert_eq(issues.length(), 0)
}

///|
test "accepts equal arrival and departure times with single-digit hours" {
  let issues = validate_stop_time_fixture(
    "trip_id,stop_sequence,arrival_time,departure_time,stop_id\nT1,1,9:05:07,9:05:07,S1\nT1,2,9:05:07,9:05:07,S1",
  )
  assert_eq(issues.length(), 0)
}

///|
test "reports a time reversal in stop sequence order" {
  let issues = validate_stop_time_fixture(
    "trip_id,stop_sequence,arrival_time,departure_time,stop_id\nT1,1,9:05:07,9:05:07,S1\nT1,2,8:00:00,8:00:00,S1",
  )
  assert_eq(issues.length(), 1)
  assert_eq(issues[0].code, "time_order_violation")
  assert_eq(issues[0].line, 3)
  assert_eq(issues[0].column, "arrival_time")
  assert_eq(issues[0].value, "8:00:00")
}

///|
test "reports negative and non-integer stop sequences" {
  let issues = validate_stop_time_fixture(
    "trip_id,stop_sequence,arrival_time,stop_id\nT1,-1,,S1\nT2,2.5,,S1\nT3,4,9:20:00,S1\nT3,2,9:10:00,S1",
  )
  assert_eq(issues.length(), 2)
  assert_eq(issues[0].code, "invalid_stop_sequence")
  assert_eq(issues[0].line, 2)
  assert_eq(issues[1].code, "invalid_stop_sequence")
}

///|
test "uses unique sequence values as trip order regardless of CSV row order" {
  let issues = validate_stop_time_fixture(
    "trip_id,stop_sequence,arrival_time,departure_time,stop_id\nT1,20,25:35:00,25:36:00,S1\nT1,10,23:59:00,23:59:00,S1\nT1,40,26:00:00,26:01:00,S1",
  )
  assert_eq(issues.length(), 0)
}

///|
test "treats integer spellings of the same sequence as a duplicate key" {
  let issues = validate_stop_time_fixture(
    "trip_id,stop_sequence,stop_id\nT1,1,S1\nT1,01,S1",
  )
  assert_eq(issues.length(), 1)
  assert_eq(issues[0].code, "duplicate_primary_key")
  assert_eq(issues[0].line, 3)
}

///|
test "reports malformed stop-time clock values at their source cells" {
  let issues = validate_stop_time_fixture(
    "trip_id,stop_sequence,arrival_time,departure_time,stop_id\nT1,1,1:2:03,25:60:00,S1\nT1,2,10:10:60,10:11:00,S1",
  )
  assert_eq(issues.length(), 3)
  assert_eq(issues[0].code, "invalid_time")
  assert_eq(issues[0].line, 2)
  assert_eq(issues[0].column, "arrival_time")
  assert_eq(issues[1].line, 3)
  assert_eq(issues[2].column, "departure_time")
}

///|
test "allows blank intermediate times when the stop is not exact" {
  let issues = validate_stop_time_fixture(
    "trip_id,stop_sequence,arrival_time,departure_time,timepoint,stop_id\nT1,1,9:00:00,,0,S1\nT1,2,,,0,S1\nT1,3,9:10:00,,0,S1",
  )
  assert_eq(issues.length(), 0)
}

///|
test "requires arrival times at first and last stops in sequence order" {
  let issues = validate_stop_time_fixture(
    "trip_id,stop_sequence,arrival_time,stop_id\nT1,30,,S1\nT1,10,,S1\nT1,20,9:05:00,S1",
  )
  assert_eq(issues.length(), 2)
  assert_eq(issues[0].code, "missing_required_time")
  assert_eq(issues[0].line, 3)
  assert_eq(issues[0].column, "arrival_time")
  assert_eq(issues[1].line, 2)
}

///|
test "reports a missing conditional time even when its column is absent" {
  let issues = validate_stop_time_fixture(
    "trip_id,stop_sequence,stop_id\nT1,1,S1",
  )
  assert_eq(issues.length(), 1)
  assert_eq(issues[0].code, "missing_required_time")
  assert_eq(issues[0].line, 2)
  assert_eq(issues[0].column, "arrival_time")
}

///|
test "requires arrival and departure when timepoint is exact" {
  let issues = validate_stop_time_fixture(
    "trip_id,stop_sequence,arrival_time,departure_time,timepoint,stop_id\nT1,1,9:00:00,,0,S1\nT1,2,,,1,S1\nT1,3,9:10:00,,0,S1",
  )
  assert_eq(issues.length(), 2)
  assert_eq(issues[0].code, "missing_required_time")
  assert_eq(issues[0].line, 3)
  assert_eq(issues[0].column, "arrival_time")
  assert_eq(issues[1].line, 3)
  assert_eq(issues[1].column, "departure_time")
}

///|
test "does not require times when a pickup or drop-off window is supplied" {
  let issues = validate_stop_time_fixture(
    "trip_id,stop_sequence,arrival_time,departure_time,start_pickup_drop_off_window,end_pickup_drop_off_window,stop_id\nT1,1,,,08:00:00,,S1\nT1,2,,,,08:10:00,S1",
  )
  assert_eq(issues.length(), 0)
}

///|
test "does not infer trip ends from duplicate stop sequences" {
  let issues = validate_stop_time_fixture(
    "trip_id,stop_sequence,arrival_time,stop_id\nT1,1,,S1\nT1,1,,S1",
  )
  assert_eq(issues.length(), 1)
  assert_eq(issues[0].code, "duplicate_primary_key")
}
