///|
fn parse_dataset_test_table(source : String) -> @wayfarer.CsvTable {
  match @wayfarer.parse_csv(source) {
    Ok(table) => table
    Err(_) => abort("expected the dataset profile fixture to parse")
  }
}

///|
test "validates a non-GTFS inventory dataset profile" {
  let tables : Map[String, @wayfarer.CsvTable] = Map([])
  tables.set(
    "products.csv",
    parse_dataset_test_table("product_id,name\nP1,Brush\nP2,Comb"),
  )
  tables.set(
    "orders.csv",
    parse_dataset_test_table("order_id,product_id,quantity\nO1,P1,2\nO2,P2,1"),
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
  assert_eq(@wayfarer.validate_csv_dataset(profile, tables).length(), 0)
}

///|
test "rejects an empty profile instead of reporting an unconstrained pass" {
  let profile = @wayfarer.CsvDatasetProfile::new([], [])
  let tables : Map[String, @wayfarer.CsvTable] = Map([])
  let issues = @wayfarer.validate_csv_dataset(profile, tables)
  assert_eq(issues.length(), 1)
  assert_eq(issues[0].code, "invalid_profile")
  assert_eq(issues[0].column, "tables")
}

///|
test "reports missing tables headers values and minimum rows" {
  let tables : Map[String, @wayfarer.CsvTable] = Map([])
  tables.set("products.csv", parse_dataset_test_table("product_id\n"))
  let profile = @wayfarer.CsvDatasetProfile::new(
    [
      @wayfarer.CsvDatasetTableRule::new(
        "products.csv",
        true,
        1,
        ["product_id", "name"],
        ["name"],
        [["product_id"]],
      ),
      @wayfarer.CsvDatasetTableRule::new(
        "orders.csv",
        true,
        1,
        ["order_id"],
        [],
        [["order_id"]],
      ),
    ],
    [],
  )
  let issues = @wayfarer.validate_csv_dataset(profile, tables)
  assert_eq(issues.length(), 3)
  assert_eq(issues[0].code, "minimum_rows")
  assert_eq(issues[1].code, "missing_required_column")
  assert_eq(issues[1].column, "name")
  assert_eq(issues[2].code, "missing_required_table")
  assert_eq(issues[2].file, "orders.csv")
}

///|
test "checks composite unique keys and locates duplicate records" {
  let tables : Map[String, @wayfarer.CsvTable] = Map([])
  tables.set(
    "order_lines.csv",
    parse_dataset_test_table("order_id,line_no,product_id\nO1,1,P1\nO1,1,P2"),
  )
  let profile = @wayfarer.CsvDatasetProfile::new(
    [
      @wayfarer.CsvDatasetTableRule::new(
        "order_lines.csv",
        true,
        1,
        ["order_id", "line_no", "product_id"],
        ["product_id"],
        [["order_id", "line_no"]],
      ),
    ],
    [],
  )
  let issues = @wayfarer.validate_csv_dataset(profile, tables)
  assert_eq(issues.length(), 1)
  assert_eq(issues[0].code, "duplicate_key")
  assert_eq(issues[0].line, Some(3))
  assert_eq(issues[0].column, "order_id,line_no")
  assert_eq(issues[0].value, "O1,1")
}

///|
test "reports unresolved generic references at the source row" {
  let tables : Map[String, @wayfarer.CsvTable] = Map([])
  tables.set(
    "products.csv",
    parse_dataset_test_table("product_id,name\nP1,Brush"),
  )
  tables.set(
    "orders.csv",
    parse_dataset_test_table("order_id,product_id\nO1,UNKNOWN"),
  )
  let profile = @wayfarer.CsvDatasetProfile::new(
    [
      @wayfarer.CsvDatasetTableRule::new(
        "products.csv",
        true,
        1,
        ["product_id", "name"],
        [],
        [["product_id"]],
      ),
      @wayfarer.CsvDatasetTableRule::new(
        "orders.csv",
        true,
        1,
        ["order_id", "product_id"],
        [],
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
  assert_eq(issues[0].code, "unresolved_reference")
  assert_eq(issues[0].file, "orders.csv")
  assert_eq(issues[0].line, Some(2))
  assert_eq(issues[0].column, "product_id")
  assert_eq(issues[0].value, "UNKNOWN")
}

///|
test "rejects references whose target is not declared unique" {
  let profile = @wayfarer.CsvDatasetProfile::new(
    [
      @wayfarer.CsvDatasetTableRule::new(
        "products.csv",
        true,
        0,
        ["category"],
        [],
        [],
      ),
      @wayfarer.CsvDatasetTableRule::new(
        "orders.csv",
        true,
        0,
        ["category"],
        [],
        [],
      ),
    ],
    [
      @wayfarer.CsvDatasetReferenceRule::new(
        "orders.csv", "category", "products.csv", "category", false,
      ),
    ],
  )
  let tables : Map[String, @wayfarer.CsvTable] = Map([])
  tables.set("products.csv", parse_dataset_test_table("category\n"))
  tables.set("orders.csv", parse_dataset_test_table("category\n"))
  let issues = @wayfarer.validate_csv_dataset(profile, tables)
  assert_eq(issues.length(), 1)
  assert_eq(issues[0].code, "invalid_reference_target")
}

///|
test "allows blank optional references and omitted optional tables" {
  let tables : Map[String, @wayfarer.CsvTable] = Map([])
  tables.set("orders.csv", parse_dataset_test_table("order_id,product_id\nO1,"))
  let profile = @wayfarer.CsvDatasetProfile::new(
    [
      @wayfarer.CsvDatasetTableRule::new(
        "products.csv",
        false,
        0,
        ["product_id", "name"],
        [],
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
        "orders.csv", "product_id", "products.csv", "product_id", false,
      ),
    ],
  )
  assert_eq(@wayfarer.validate_csv_dataset(profile, tables).length(), 0)
  tables.set(
    "products.csv",
    parse_dataset_test_table("product_id,name\nP1,Brush"),
  )
  assert_eq(@wayfarer.validate_csv_dataset(profile, tables).length(), 0)
}

///|
test "requires non-empty fields and required references" {
  let tables : Map[String, @wayfarer.CsvTable] = Map([])
  tables.set("products.csv", parse_dataset_test_table("product_id,name\nP1,"))
  tables.set("orders.csv", parse_dataset_test_table("order_id,product_id\nO1,"))
  let profile = @wayfarer.CsvDatasetProfile::new(
    [
      @wayfarer.CsvDatasetTableRule::new(
        "products.csv",
        true,
        1,
        ["product_id", "name"],
        ["name"],
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
  assert_eq(issues[0].code, "missing_required_value")
  assert_eq(issues[0].file, "products.csv")
  assert_eq(issues[0].line, Some(2))
  assert_eq(issues[1].code, "missing_reference_value")
  assert_eq(issues[1].file, "orders.csv")
  assert_eq(issues[1].line, Some(2))
}

///|
test "checks field rules for integer number date and allowed values" {
  let tables : Map[String, @wayfarer.CsvTable] = Map([])
  tables.set(
    "courses.csv",
    parse_dataset_test_table(
      (
        #|course_id,capacity,seats,start_date,level
        #|C101,many,25,20261102,beginner
        #|C102,25,1.5.2,20230229,expert
        #|C103,-3,25.5,20261103,advanced
      ),
    ),
  )
  let allowed : Array[String] = ["beginner", "intermediate", "advanced"]
  let field_rules : Array[@wayfarer.CsvDatasetFieldRule] = [
    @wayfarer.CsvDatasetFieldRule::new("capacity", @wayfarer.IntegerValue),
    @wayfarer.CsvDatasetFieldRule::new("seats", @wayfarer.NumberValue),
    @wayfarer.CsvDatasetFieldRule::new("start_date", @wayfarer.DateValue),
    @wayfarer.CsvDatasetFieldRule::new(
      "level",
      @wayfarer.AllowedValues,
      allowed~,
    ),
  ]
  let profile = @wayfarer.CsvDatasetProfile::new(
    [
      @wayfarer.CsvDatasetTableRule::new(
        "courses.csv",
        true,
        1,
        ["course_id", "capacity", "seats", "start_date", "level"],
        ["course_id"],
        [["course_id"]],
        field_rules~,
      ),
    ],
    [],
  )
  let issues = @wayfarer.validate_csv_dataset(profile, tables)
  assert_eq(issues.length(), 4)
  assert_eq(issues[0].code, "invalid_integer_value")
  assert_eq(issues[0].line, Some(2))
  assert_eq(issues[0].column, "capacity")
  assert_eq(issues[0].value, "many")
  assert_eq(issues[1].code, "invalid_number_value")
  assert_eq(issues[1].line, Some(3))
  assert_eq(issues[1].column, "seats")
  assert_eq(issues[1].value, "1.5.2")
  assert_eq(issues[2].code, "invalid_date_value")
  assert_eq(issues[2].line, Some(3))
  assert_eq(issues[2].column, "start_date")
  assert_eq(issues[2].value, "20230229")
  assert_eq(issues[3].code, "value_not_allowed")
  assert_eq(issues[3].line, Some(3))
  assert_eq(issues[3].column, "level")
  assert_eq(issues[3].value, "expert")
}

///|
test "reports allowed value findings with the offending value" {
  let tables : Map[String, @wayfarer.CsvTable] = Map([])
  tables.set(
    "enrollments.csv",
    parse_dataset_test_table("enrollment_id,status\nE1,active\nE2,pending"),
  )
  let allowed : Array[String] = ["active", "dropped"]
  let field_rules : Array[@wayfarer.CsvDatasetFieldRule] = [
    @wayfarer.CsvDatasetFieldRule::new(
      "status",
      @wayfarer.AllowedValues,
      allowed~,
    ),
  ]
  let profile = @wayfarer.CsvDatasetProfile::new(
    [
      @wayfarer.CsvDatasetTableRule::new(
        "enrollments.csv",
        true,
        1,
        ["enrollment_id", "status"],
        ["enrollment_id"],
        [["enrollment_id"]],
        field_rules~,
      ),
    ],
    [],
  )
  let issues = @wayfarer.validate_csv_dataset(profile, tables)
  assert_eq(issues.length(), 1)
  assert_eq(issues[0].code, "value_not_allowed")
  assert_eq(issues[0].line, Some(3))
  assert_eq(issues[0].value, "pending")
}

///|
test "field rules skip empty cells" {
  let tables : Map[String, @wayfarer.CsvTable] = Map([])
  tables.set(
    "courses.csv",
    parse_dataset_test_table("course_id,capacity\nC101,"),
  )
  let field_rules : Array[@wayfarer.CsvDatasetFieldRule] = [
    @wayfarer.CsvDatasetFieldRule::new("capacity", @wayfarer.IntegerValue),
  ]
  let profile = @wayfarer.CsvDatasetProfile::new(
    [
      @wayfarer.CsvDatasetTableRule::new(
        "courses.csv",
        true,
        1,
        ["course_id", "capacity"],
        ["course_id"],
        [["course_id"]],
        field_rules~,
      ),
    ],
    [],
  )
  assert_eq(@wayfarer.validate_csv_dataset(profile, tables).length(), 0)
}

///|
test "reports a missing column referenced by a field rule" {
  let tables : Map[String, @wayfarer.CsvTable] = Map([])
  tables.set("courses.csv", parse_dataset_test_table("course_id\nC101"))
  let field_rules : Array[@wayfarer.CsvDatasetFieldRule] = [
    @wayfarer.CsvDatasetFieldRule::new("capacity", @wayfarer.IntegerValue),
  ]
  let profile = @wayfarer.CsvDatasetProfile::new(
    [
      @wayfarer.CsvDatasetTableRule::new(
        "courses.csv",
        true,
        1,
        ["course_id"],
        ["course_id"],
        [["course_id"]],
        field_rules~,
      ),
    ],
    [],
  )
  let issues = @wayfarer.validate_csv_dataset(profile, tables)
  assert_eq(issues.length(), 1)
  assert_eq(issues[0].code, "missing_required_column")
  assert_eq(issues[0].column, "capacity")
}
