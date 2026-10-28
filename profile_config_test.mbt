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
