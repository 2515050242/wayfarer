///|
/// Decode a version 1 JSON document into a reusable CSV dataset profile.
pub fn parse_csv_dataset_profile(
  source : String,
) -> Result[CsvDatasetProfile, String] {
  let parsed : Result[Json, @json.ParseError] = Ok(@json.parse(source)) catch {
    error => Err(error)
  }
  let json = match parsed {
    Ok(value) => value
    Err(error) =>
      return Err("invalid JSON profile: " + profile_json_parse_error(error))
  }
  let document : Map[String, Json] = match
    decode_profile_value(json, "profile") {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  let version : Int32 = match decode_profile_field(document, "version") {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  if version != 1 {
    return Err("unsupported profile version: " + version.to_string())
  }
  let table_json : Array[Json] = match
    decode_profile_field(document, "tables") {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  if table_json.length() == 0 {
    return Err("profile must declare at least one table")
  }
  let reference_json : Array[Json] = match
    decode_profile_field(document, "references") {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  let table_rules : Array[CsvDatasetTableRule] = []
  for index, table in table_json {
    match parse_profile_table(table, "tables[" + index.to_string() + "]") {
      Ok(rule) => table_rules.push(rule)
      Err(message) => return Err(message)
    }
  }
  let reference_rules : Array[CsvDatasetReferenceRule] = []
  for index, reference in reference_json {
    match
      parse_profile_reference(
        reference,
        "references[" + index.to_string() + "]",
      ) {
      Ok(rule) => reference_rules.push(rule)
      Err(message) => return Err(message)
    }
  }
  Ok(CsvDatasetProfile::new(table_rules, reference_rules))
}

///|
fn parse_profile_table(
  value : Json,
  path : String,
) -> Result[CsvDatasetTableRule, String] {
  let object : Map[String, Json] = match decode_profile_value(value, path) {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  let file : String = match decode_profile_field(object, "file", path~) {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  if !is_safe_profile_filename(file) {
    return Err(
      "invalid profile at " +
      path +
      ".file: expected a non-empty filename without path separators",
    )
  }
  let required : Bool = match decode_profile_field(object, "required", path~) {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  let minimum_rows : Int32 = match
    decode_profile_field(object, "minimum_rows", path~) {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  if minimum_rows < 0 {
    return Err(
      "invalid profile at " + path + ".minimum_rows: cannot be negative",
    )
  }
  let required_columns : Array[String] = match
    decode_profile_field(object, "required_columns", path~) {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  let non_empty_columns : Array[String] = match
    decode_profile_field(object, "non_empty_columns", path~) {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  let unique_keys : Array[Array[String]] = match
    decode_profile_field(object, "unique_keys", path~) {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  Ok(
    CsvDatasetTableRule::new(
      file, required, minimum_rows, required_columns, non_empty_columns, unique_keys,
    ),
  )
}

///|
fn parse_profile_reference(
  value : Json,
  path : String,
) -> Result[CsvDatasetReferenceRule, String] {
  let object : Map[String, Json] = match decode_profile_value(value, path) {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  let source_file : String = match
    decode_profile_field(object, "source_file", path~) {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  let source_column : String = match
    decode_profile_field(object, "source_column", path~) {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  let target_file : String = match
    decode_profile_field(object, "target_file", path~) {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  let target_column : String = match
    decode_profile_field(object, "target_column", path~) {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  let required : Bool = match decode_profile_field(object, "required", path~) {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  Ok(
    CsvDatasetReferenceRule::new(
      source_file, source_column, target_file, target_column, required,
    ),
  )
}

///|
fn[T : @json.FromJson] decode_profile_field(
  object : Map[String, Json],
  field : String,
  path~ : String = "profile",
) -> Result[T, String] {
  match object.get(field) {
    None =>
      Err("invalid profile at " + path + "." + field + ": field is required")
    Some(value) => decode_profile_value(value, path + "." + field)
  }
}

///|
fn[T : @json.FromJson] decode_profile_value(
  value : Json,
  path : String,
) -> Result[T, String] {
  let decoded : Result[T, @json.JsonDecodeError] = Ok(@json.from_json(value)) catch {
    error => Err(error)
  }
  match decoded {
    Ok(result) => Ok(result)
    Err(@json.JsonDecodeError((_, message))) =>
      Err("invalid profile at " + path + ": " + message)
  }
}

///|
fn is_safe_profile_filename(filename : String) -> Bool {
  if filename == "" || filename == "." || filename == ".." {
    return false
  }
  for character in filename.to_array() {
    let code = character.to_int()
    if character == '/' || character == '\\' || code < 32 || code == 127 {
      return false
    }
  }
  true
}

///|
fn profile_json_parse_error(error : @json.ParseError) -> String {
  match error {
    @json.InvalidChar(position, _) =>
      "unexpected character at " +
      position.line.to_string() +
      ":" +
      position.column.to_string()
    @json.InvalidEof => "unexpected end of file"
    _ => "invalid JSON syntax"
  }
}
