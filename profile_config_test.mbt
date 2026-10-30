///|
test "loads a versioned JSON profile into the shared validation API" {
  let profile = match
    @wayfarer.parse_csv_dataset_profile(
      (
        #|{
        #|  "version": 1,
        #|  "tables": [{
        #|    "file": "products.csv",
        #|    "required": true,
        #|    "minimum_rows": 1,
        #|    "required_columns": ["product_id"],
        #|    "non_empty_columns": ["product_id"],
        #|    "unique_keys": [["product_id"]]
        #|  }],
        #|  "references": []
        #|}
      ),
    ) {
    Ok(value) => value
    Err(message) => {
      println(message)
      abort(message)
    }
  }
  assert_eq(profile.tables.length(), 1)
  assert_eq(profile.tables[0].file, "products.csv")
  assert_eq(profile.tables[0].unique_keys[0][0], "product_id")
}

///|
test "reports JSON syntax, empty and typed configuration errors" {
  let malformed = @wayfarer.parse_csv_dataset_profile("{not-json")
  assert_true(malformed is Err(_))
  let empty = @wayfarer.parse_csv_dataset_profile(
    "{\"version\":1,\"tables\":[],\"references\":[]}",
  )
  assert_true(empty is Err("profile must declare at least one table"))
  let wrong_type = @wayfarer.parse_csv_dataset_profile(
    "{\"version\":1,\"tables\":[{}],\"references\":[]}",
  )
  assert_true(wrong_type is Err(_))
}

///|
test "rejects unsupported versions and paths in table filenames" {
  let wrong_version = @wayfarer.parse_csv_dataset_profile(
    "{\"version\":2,\"tables\":[],\"references\":[]}",
  )
  assert_true(wrong_version is Err("unsupported profile version: 2"))
  let traversal = @wayfarer.parse_csv_dataset_profile(
    (
      #|{"version":1,"tables":[{"file":"../secret.csv","required":true,"minimum_rows":0,"required_columns":[],"non_empty_columns":[],"unique_keys":[]}],"references":[]}
    ),
  )
  assert_true(traversal is Err(_))
}

///|
test "rejects negative minimum row counts and missing config fields" {
  let negative_minimum = @wayfarer.parse_csv_dataset_profile(
    (
      #|{"version":1,"tables":[{"file":"items.csv","required":true,"minimum_rows":-1,"required_columns":[],"non_empty_columns":[],"unique_keys":[]}],"references":[]}
    ),
  )
  assert_true(
    negative_minimum
    is Err("invalid profile at tables[0].minimum_rows: cannot be negative"),
  )
  let missing_references = @wayfarer.parse_csv_dataset_profile(
    "{\"version\":1,\"tables\":[]}",
  )
  assert_true(missing_references is Err(_))
}

///|
test "loads field rules from a versioned JSON profile" {
  let profile = match
    @wayfarer.parse_csv_dataset_profile(
      (
        #|{
        #|  "version": 1,
        #|  "tables": [{
        #|    "file": "courses.csv",
        #|    "required": true,
        #|    "minimum_rows": 1,
        #|    "required_columns": ["course_id"],
        #|    "non_empty_columns": ["course_id"],
        #|    "unique_keys": [["course_id"]],
        #|    "field_rules": [
        #|      {"column": "capacity", "type": "integer"},
        #|      {"column": "start_date", "type": "date"},
        #|      {"column": "level", "type": "enum", "allowed": ["beginner", "advanced"]}
        #|    ]
        #|  }],
        #|  "references": []
        #|}
      ),
    ) {
    Ok(value) => value
    Err(message) => {
      println(message)
      abort(message)
    }
  }
  assert_eq(profile.tables.length(), 1)
  assert_eq(profile.tables[0].field_rules.length(), 3)
  assert_eq(profile.tables[0].field_rules[0].column, "capacity")
  assert_eq(profile.tables[0].field_rules[2].allowed.length(), 2)
}

///|
test "rejects invalid field rule declarations" {
  let bad_type = @wayfarer.parse_csv_dataset_profile(
    (
      #|{"version":1,"tables":[{"file":"courses.csv","required":true,"minimum_rows":1,"required_columns":[],"non_empty_columns":[],"unique_keys":[],"field_rules":[{"column":"capacity","type":"percent"}]}],"references":[]}
    ),
  )
  assert_true(
    bad_type
    is Err(
      "invalid profile at tables[0].field_rules[0].type: expected integer, number, date, or enum"
    ),
  )
  let enum_without_allowed = @wayfarer.parse_csv_dataset_profile(
    (
      #|{"version":1,"tables":[{"file":"courses.csv","required":true,"minimum_rows":1,"required_columns":[],"non_empty_columns":[],"unique_keys":[],"field_rules":[{"column":"level","type":"enum"}]}],"references":[]}
    ),
  )
  assert_true(
    enum_without_allowed
    is Err(
      "invalid profile at tables[0].field_rules[0].allowed: field is required"
    ),
  )
  let empty_column = @wayfarer.parse_csv_dataset_profile(
    (
      #|{"version":1,"tables":[{"file":"courses.csv","required":true,"minimum_rows":1,"required_columns":[],"non_empty_columns":[],"unique_keys":[],"field_rules":[{"column":"","type":"integer"}]}],"references":[]}
    ),
  )
  assert_true(
    empty_column
    is Err(
      "invalid profile at tables[0].field_rules[0].column: must not be empty"
    ),
  )
}
