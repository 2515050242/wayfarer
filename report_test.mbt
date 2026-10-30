///|
fn parse_report_test_table(source : String) -> @wayfarer.CsvTable {
  match @wayfarer.parse_csv(source) {
    Ok(table) => table
    Err(_) => abort("expected the report fixture to parse")
  }
}

///|
test "encodes dataset findings as a JSON report" {
  let tables : Map[String, @wayfarer.CsvTable] = Map([])
  tables.set(
    "products.csv",
    parse_report_test_table("product_id,name\nP1,Brush"),
  )
  tables.set(
    "orders.csv",
    parse_report_test_table("order_id,product_id\nO1,UNKNOWN"),
  )
  let profile = @wayfarer.CsvDatasetProfile::new(
    [
      @wayfarer.CsvDatasetTableRule::new(
        "products.csv",
        true,
        1,
        ["product_id", "name"],
        ["product_id", "name"],
        [["product_id"]],
      ),
      @wayfarer.CsvDatasetTableRule::new(
        "orders.csv",
        true,
        1,
        ["order_id", "product_id"],
        ["order_id"],
        [["order_id"]],
      ),
    ],
    [
      @wayfarer.CsvDatasetReferenceRule::new(
        "orders.csv", "product_id", "products.csv", "product_id", true,
      ),
    ],
  )
  let issues = @wayfarer.validate_csv_dataset(profile, tables)
  assert_eq(issues.length(), 1)
  assert_eq(
    @wayfarer.csv_dataset_issues_to_json(issues),
    "{\"findings\":[{\"code\":\"unresolved_reference\",\"file\":\"orders.csv\",\"line\":2,\"column\":\"product_id\",\"value\":\"UNKNOWN\",\"message\":\"referenced value does not exist in products.csv\"}],\"count\":1,\"passed\":false}",
  )
}

///|
test "encodes an empty report as passing JSON" {
  assert_eq(
    @wayfarer.csv_dataset_issues_to_json([]),
    "{\"findings\":[],\"count\":0,\"passed\":true}",
  )
}

///|
test "escapes quotes and control characters in JSON values" {
  let quote = Int32::unsafe_to_char(34).to_string()
  let backslash = Int32::unsafe_to_char(92).to_string()
  let tab = Int32::unsafe_to_char(9).to_string()
  let tables : Map[String, @wayfarer.CsvTable] = Map([])
  tables.set(
    "products.csv",
    parse_report_test_table("product_id,name\nP1,Brush"),
  )
  // One cell holds a literal quote through a doubled CSV quote; the other
  // holds a tab character inside a quoted cell.
  let orders_csv = "order_id,product_id\nO1," +
    quote +
    "UN" +
    quote +
    quote +
    "KNOWN" +
    quote +
    "\nO2," +
    quote +
    "TA" +
    tab +
    "B" +
    quote
  tables.set("orders.csv", parse_report_test_table(orders_csv))
  let profile = @wayfarer.CsvDatasetProfile::new(
    [
      @wayfarer.CsvDatasetTableRule::new(
        "products.csv",
        true,
        1,
        ["product_id", "name"],
        ["product_id", "name"],
        [["product_id"]],
      ),
      @wayfarer.CsvDatasetTableRule::new(
        "orders.csv",
        true,
        1,
        ["order_id", "product_id"],
        ["order_id"],
        [["order_id"]],
      ),
    ],
    [
      @wayfarer.CsvDatasetReferenceRule::new(
        "orders.csv", "product_id", "products.csv", "product_id", true,
      ),
    ],
  )
  let issues = @wayfarer.validate_csv_dataset(profile, tables)
  assert_eq(issues.length(), 2)
  let report = @wayfarer.csv_dataset_issues_to_json(issues)
  assert_true(
    report.contains(quote + "UN" + backslash + quote + "KNOWN" + quote),
  )
  assert_true(report.contains(quote + "TA" + backslash + "t" + "B" + quote))
}
