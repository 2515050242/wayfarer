///|
fn parse_fixture(source : String) -> @wayfarer.CsvTable {
  match @wayfarer.parse_csv(source) {
    Ok(table) => table
    Err(_) => abort("expected valid CSV fixture")
  }
}

///|
test "published library detects a broken cross-table reference" {
  let products = @wayfarer.CsvDatasetTableRule::new(
    "products.csv", true, 1, ["id"], ["id"], [["id"]],
  )
  let orders = @wayfarer.CsvDatasetTableRule::new(
    "orders.csv", true, 1, ["product_id"], ["product_id"], [],
  )
  let reference = @wayfarer.CsvDatasetReferenceRule::new(
    "orders.csv", "product_id", "products.csv", "id", true,
  )
  let profile = @wayfarer.CsvDatasetProfile::new([products, orders], [reference])
  let tables : Map[String, @wayfarer.CsvTable] = {
    "products.csv": parse_fixture("id\nP1\n"),
    "orders.csv": parse_fixture("product_id\nP1\n"),
  }
  assert_eq(@wayfarer.validate_csv_dataset(profile, tables).length(), 0)
  tables.set("orders.csv", parse_fixture("product_id\nP2\n"))
  let issues = @wayfarer.validate_csv_dataset(profile, tables)
  assert_eq(issues.length(), 1)
  assert_eq(issues[0].code, "unresolved_reference")
  assert_eq(issues[0].file, "orders.csv")
  assert_eq(issues[0].line, Some(2))
}
