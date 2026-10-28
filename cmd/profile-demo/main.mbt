///|
fn main {
  let args = @env.args()
  if args.length() != 2 {
    println("Usage: moon run cmd/profile-demo <csv-dataset-directory>")
    @sys.exit(2)
  }
  let directory = args[1]
  let products_path = directory + @path.sep.to_string() + "products.csv"
  let orders_path = directory + @path.sep.to_string() + "orders.csv"
  let products = match read_profile_demo_table(products_path) {
    Some(table) => table
    None => {
      println("ERROR products.csv [input_error] could not read or parse CSV")
      @sys.exit(2)
      abort("products.csv input error")
    }
  }
  let orders = match read_profile_demo_table(orders_path) {
    Some(table) => table
    None => {
      println("ERROR orders.csv [input_error] could not read or parse CSV")
      @sys.exit(2)
      abort("orders.csv input error")
    }
  }
  let tables : Map[String, @wayfarer.CsvTable] = Map([])
  tables.set("products.csv", products)
  tables.set("orders.csv", orders)
  let issues = @wayfarer.validate_csv_dataset(inventory_profile(), tables)
  println("Wayfarer: checking inventory CSV profile in " + directory)
  for issue in issues {
    let location = match issue.line {
      Some(line) => issue.file + ":" + line.to_string()
      None => issue.file
    }
    let column = if issue.column == "" { "" } else { " " + issue.column }
    println(
      "ERROR " + location + column + " [" + issue.code + "] " + issue.message,
    )
  }
  let record_count = products.rows.length() + orders.rows.length()
  if issues.length() == 0 {
    println(
      "PASS: 2 CSV tables, " + record_count.to_string() + " records, 0 findings",
    )
  } else {
    println(
      "FAIL: 2 CSV tables, " +
      record_count.to_string() +
      " records, " +
      issues.length().to_string() +
      (if issues.length() == 1 { " finding" } else { " findings" }),
    )
    @sys.exit(1)
  }
}

///|
fn inventory_profile() -> @wayfarer.CsvDatasetProfile {
  @wayfarer.CsvDatasetProfile::new(
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
        ["order_id", "product_id", "quantity"],
        ["order_id", "product_id", "quantity"],
        [["order_id"]],
      ),
    ],
    [
      @wayfarer.CsvDatasetReferenceRule::new(
        "orders.csv", "product_id", "products.csv", "product_id", true,
      ),
    ],
  )
}

///|
fn read_profile_demo_table(path : String) -> @wayfarer.CsvTable? {
  let source : Result[String, @fs.IOError] = Ok(@fs.read_file_to_string(path)) catch {
    error => Err(error)
  }
  match source {
    Ok(text) =>
      match @wayfarer.parse_csv(text) {
        Ok(table) => Some(table)
        Err(_) => None
      }
    Err(_) => None
  }
}
