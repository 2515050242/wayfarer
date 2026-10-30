# Wayfarer

Wayfarer is a MoonBit library and CLI for checking a directory of related CSV
files against a declarative dataset contract before the data enters an ETL
pipeline, an analysis, or a release. It validates multi-table datasets:
required tables and headers, minimum row counts, non-empty values, single-
and multi-column unique keys, foreign-key-style references across files, and
per-column field rules (integer, number, date, allowed values). Findings keep
the source file, physical line, column, offending value, and a stable code,
and the CLI can emit a machine-readable JSON report for CI and pipeline
integration.

A built-in GTFS Schedule profile demonstrates a domain profile on top of the
same engine: it adds transit-specific cross-table, service-calendar, and
stop-time semantics for a feed directory. The general CSV path is not a
database, ETL framework, or full schema language; its scope is listed
explicitly below.

Typical datasets are multi-file CSV exports and handoffs: product and order
files, roster or enrollment sets, or a transit feed produced by another tool.
Broken references, duplicate keys, and malformed values are cheap to catch
before ingestion and expensive to debug afterwards, so Wayfarer reports them
with exact source locations and stable codes.

Every dataset under `examples/` is synthetic and exists for reproducible
checks. None is presented as production, student, business, or transit-operator
data.

## Try it

Install the [MoonBit toolchain](https://www.moonbitlang.com/download/), clone
this repository, run the registry sync once, and check the bundled course
catalog dataset (a synthetic course and session roster):

```text
moon update
moon run cmd/csv-check examples/course-catalog-profile.json examples/course-catalog
```

Expected output:

```text
Wayfarer: checking CSV profile in examples/course-catalog
PASS: 2 CSV tables, 4 records, 0 findings
```

The invalid fixture shows the field rules and the cross-file reference in
action. It exits with status 1:

```text
moon run cmd/csv-check examples/course-catalog-profile.json examples/course-catalog-invalid
```

```text
ERROR courses.csv:2 capacity="many" [invalid_integer_value] value must be an optionally signed integer
ERROR courses.csv:3 start_date="20230229" [invalid_date_value] value must be a valid Gregorian date in YYYYMMDD format
ERROR courses.csv:3 level="expert" [value_not_allowed] value is not one of the allowed values declared in the profile
ERROR sessions.csv:3 seats="1.5.2" [invalid_number_value] value must be an integer or decimal number
ERROR sessions.csv:3 course_id="C999" [unresolved_reference] referenced value does not exist in courses.csv
FAIL: 2 CSV tables, 4 records, 5 findings
```

## Dataset profiles

A `CsvDatasetProfile` describes a dataset without adding domain-specific
logic to the validation engine.

| Table rule | Meaning |
| --- | --- |
| `required` | the file must be present |
| `minimum_rows` | the table must contain at least this many data records |
| `required_columns` | these headers must exist |
| `non_empty_columns` | these fields must be non-empty in every record |
| `unique_keys` | each listed column combination is unique within the table |
| `field_rules` | per-column value rules (below) |

Reference rules validate values in one table against a declared
single-column unique key in another table, for example a `course_id` column
in `sessions.csv` resolving to `courses.csv`. Optional references allow blank
source values.

### Field rules

| `type` | Accepted values |
| --- | --- |
| `integer` | an optionally signed run of digits |
| `number` | an optionally signed integer or decimal number without exponent |
| `date` | a valid Gregorian date in `YYYYMMDD` format |
| `enum` | one of the values listed in `allowed` |

Empty cells are not reported by field rules; use `non_empty_columns` to
reject them. A field rule on a missing column reports
`missing_required_column`. Findings use the stable codes
`invalid_integer_value`, `invalid_number_value`, `invalid_date_value`, and
`value_not_allowed`, with the source file, line, column, and offending value.

### JSON profile configuration

`cmd/csv-check` reads the same contract from a versioned JSON profile, so a
dataset can be checked without writing a MoonBit caller. The JSON format
mirrors the API: one entry per table with the rules above, plus reference
entries. See
[`examples/course-catalog-profile.json`](examples/course-catalog-profile.json)
and
[`examples/inventory-profile.json`](examples/inventory-profile.json);
`cmd/profile-demo` remains a compiled-in example of the library API.

### Machine-readable JSON report

`cmd/csv-check --json` prints the findings as a JSON object instead of the
text report, with the same exit status, for CI pipelines and downstream tools:

```text
moon run cmd/csv-check examples/course-catalog-profile.json examples/course-catalog-invalid --json
```

Each finding carries `code`, `file`, `line` (null for file-level findings),
`column`, `value`, and `message`; the report ends with `count` and `passed`.
The library exposes the same encoding as `csv_dataset_issues_to_json`.

## Library API

The public API exposes `parse_csv` for source-located CSV text (quoted cells,
CRLF, BOM, structured `CsvError` results), `CsvDatasetProfile` and its rule
builders, `validate_csv_dataset` for user-defined contracts,
`parse_csv_dataset_profile` for version 1 profile JSON, and
`csv_dataset_issues_to_json` for machine-readable reports. Build a profile
from table, field, and reference rules, parse each input with `parse_csv`,
place the results in a `Map[String, CsvTable]`, and pass the map to
`validate_csv_dataset`. All findings use structured result types.

The only external module dependency is `moonbitlang/x` 0.5.6 for filesystem,
path, and process-exit support; the parser, config decoding, and validation
rules are implemented in MoonBit. The upstream module declares Apache-2.0 and
identifies its packages as experimental.

## Ecosystem positioning

Checked against the Mooncakes index on 2026-10-30:

- [moon-csv-lite](https://mooncakes.io/docs/clhhhhh/moon-csv-lite) (0.1.0)
  profiles a single CSV table: dialect detection, schema inference, column
  statistics, and quality contracts per file.
- [moonverity](https://mooncakes.io/docs/Wchwch777/moonverity) (0.1.2)
  validates one CSV or JSONL dataset against a per-file contract, with row
  normalization, quality scores, and CI exits.
- Wayfarer checks a *directory of related CSV tables* together: required
  tables, cross-file references, composite unique keys across tables, and
  physical source locations (file, line, column) in every finding, plus a
  built-in domain profile (GTFS Schedule).

The single-table tools overlap with Wayfarer on per-file rules; neither of
them covers cross-table relational integrity or source-located findings for a
multi-file dataset, which is Wayfarer's focus. Wayfarer does not read JSONL
and does not infer schemas or score quality; use the other tools for those.

## Built-in GTFS Schedule profile

| Table | Unconditionally required headers checked |
| --- | --- |
| `agency.txt` | `agency_name`, `agency_url`, `agency_timezone` |
| `stops.txt` | `stop_id` |
| `routes.txt` | `route_id`, `route_type` |
| `trips.txt` | `route_id`, `service_id`, `trip_id` |
| `stop_times.txt` | `trip_id`, `stop_sequence` |
| `calendar.txt` | `service_id`, weekday flags, `start_date`, `end_date` |
| `calendar_dates.txt` | `service_id`, `date`, `exception_type` |

`validate_schema` checks only these required header names when a listed table is
passed to it. It does not validate every field's type, enum, conditional
presence, or cross-file rule. For example, `route_type` and most fields outside
the documented feed checks are not yet validated.
The directory CLI additionally requires at least one data row in `agency.txt`,
`stops.txt`, `routes.txt`, and `trips.txt`, and requires each declared trip to
have at least two `stop_times.txt` records. These checks prevent a header-only
or one-stop feed from being reported as passing the supported profile.

## Feed relationship checks

`validate_feed` accepts the core tables that are available and checks:

- `stop_id`, `route_id`, and `trip_id` are non-empty and unique within their
  supported table.
- `(trip_id, stop_sequence)` is present and unique in `stop_times.txt`.
- Each `trips.route_id` resolves to `routes.route_id`.
- When `calendar.txt` or `calendar_dates.txt` is supplied with a `service_id`
  column, each `trips.service_id` resolves to the union of those service IDs.
- Calendar weekday fields accept `0` or `1`; `start_date` and `end_date` must
  be valid Gregorian `YYYYMMDD` dates, and the end date cannot precede the
  start date.
- In `calendar_dates.txt`, `(service_id, date)` pairs are unique, `date` must
  be a valid Gregorian `YYYYMMDD` date, and `exception_type` must be `1` or `2`.
- Each `stop_times.trip_id` resolves to `trips.trip_id`.
- In the supported fixed-stop profile, `stop_times.stop_id` is present and
  non-empty, resolves to `stops.stop_id`, and points to a stop/platform whose
  `location_type` is `0` or empty. An omitted `location_type` column is treated
  as empty, as allowed by GTFS.
- Non-empty `stop_times.location_group_id` or `location_id` values are reported
  as an unsupported flexible-location profile; they are never treated as a
  passing fixed-stop record.
- `stop_sequence` is a non-negative integer and unique within each trip. Gaps
  are accepted. Its numeric value defines stop order; CSV rows need not be
  physically sorted by that value.
- `timepoint`, `pickup_type`, `drop_off_type`, `continuous_pickup`, and
  `continuous_drop_off` accept only their GTFS enum values. The optional
  route-level continuous pickup/drop-off values are checked too.
- If either pickup/drop-off window bound is present, both must be present and
  form a positive interval using valid GTFS times. Arrival/departure times are
  forbidden on that row. Default/`0` regular pickup and drop-off values and
  `pickup_type` `3` are forbidden; stop-level continuous values must be `1` or
  empty. If any trip on a route uses a window, route-level continuous values
  must be `1` or empty. Times after midnight may exceed 24 hours.
- Non-empty `arrival_time` and `departure_time` values use `H:MM:SS` or
  `HH:MM:SS`; minute and second values must be from `00` to `59`. Hours above
  24 are accepted for service after midnight.
- Provided arrival and departure times do not move backward when stop rows are
  read in `trip_id` and numeric `stop_sequence` order. Equal consecutive times
  are accepted, and blank or malformed times are excluded from this comparison.
- `arrival_time` is required at the first and last stop of each trip, and both
  `arrival_time` and `departure_time` are required when `timepoint` is `1`.
  Rows with a non-empty pickup/drop-off window are exempt from required event
  times; supplying either event time on such a row is separately reported as
  forbidden. These checks use numeric stop order and report a missing field
  even when its column is absent. A trip with invalid or duplicate stop
  sequences has no inferred first or last stop, avoiding boundary findings
  from ambiguous order.

Findings include the source file, physical CSV line, field, offending value,
stable code, and a short explanation. Missing table context skips checks that
need that table; callers should run `validate_schema` and
`validate_gtfs_field_values` for each parsed table as well. The directory CLI
runs both checks on its supported files. GTFS field values containing a tab,
carriage return, or line feed are rejected. LF and CRLF remain valid CSV record
separators; line breaks inside quoted CSV cells are normalized by the parser,
then rejected as field values with a file, physical record line, and field
diagnostic. A standalone CR cannot end a record. Diagnostic values escape
quotes, backslashes, and control characters so each finding remains one stable
output line. Trip service IDs are checked only when at least one service table
provides its `service_id` column; `calendar_dates.txt` may provide service IDs
without a weekly `calendar.txt`. The calendar checks do not validate service-day
coverage, timezone behavior, or every conditional GTFS requirement. This release supports fixed
stop/platform records only. Flexible-location rows that use
`location_group_id` or `location_id` receive an
`unsupported_location_profile` finding. The directory CLI also rejects the
presence of `location_groups.txt`, `location_group_stops.txt`, or
`locations.geojson`, because it does not parse or validate those files. The
validator does not yet check stop hierarchy, flexible-location rules or ID
collisions, booking-rule references, or other conditional fields outside the
listed stop-time and service-calendar rules. GTFS defines `stop_sequence` as the order of stops
along a trip; this validator uses the numeric sequence values and does not
require CSV rows to be sorted. See the
[GTFS Schedule reference](https://gtfs.org/documentation/schedule/reference/)
for the complete specification.

GTFS also has conditional requirements and newer location and fare files.
Wayfarer does not claim to validate those yet; the supported rule set is listed
explicitly above and will grow in later increments.

## Try the built-in GTFS profile

The command reads an unzipped GTFS directory. Install the [MoonBit
toolchain](https://www.moonbitlang.com/download/), clone this repository, and
run the registry sync once, then check the bundled passing feed from the
repository root:

```text
moon update
moon run cmd/main examples/valid
```

Expected output:

```text
Wayfarer: checking examples/valid
PASS (supported checks only): 7 parsed files, 9 records, 0 findings
```

To see actionable errors, run the failing fixture:

```text
moon run cmd/main examples/invalid
```

It exits with status 1 and includes diagnostics such as:

```text
ERROR calendar_dates.txt:3 service_id,date="WK,20261031" [duplicate_primary_key] service_id and date pair is already used in this table
ERROR trips.txt:2 route_id="UNKNOWN" [unresolved_reference] referenced ID does not exist in routes.txt
ERROR trips.txt:2 service_id="MISSING" [unresolved_reference] referenced ID does not exist in calendar.txt or calendar_dates.txt
ERROR stop_times.txt:2 arrival_time="" [missing_required_time] arrival_time is required at the first and last stop of a trip
ERROR stop_times.txt:2 departure_time="25:61:00" [invalid_time] time must use H:MM:SS or HH:MM:SS with minutes and seconds from 00 to 59
ERROR stop_times.txt:4 arrival_time="25:00:00" [time_order_violation] time precedes an earlier defined time in this trip's stop_sequence order
FAIL: 6 parsed files, 9 records, 6 findings
```

The following isolated fixtures demonstrate the minimum-record and GTFS field
value checks. The field-value fixture covers a quoted tab, CRLF normalized
inside a quoted value, and an unquoted tab. Each command exits with status 1:

```text
moon run cmd/main examples/header-only-required-table
```

```text
ERROR agency.txt:1 [empty_required_table] required table must contain at least one data record
FAIL: 6 parsed files, 7 records, 1 finding
```

```text
moon run cmd/main examples/single-stop-trip
```

```text
ERROR trips.txt:2 trip_id="T1" [insufficient_stop_times] trip must have at least two stop_times records
FAIL: 6 parsed files, 6 records, 1 finding
```

```text
moon run cmd/main examples/field-value-errors
```

```text
ERROR stops.txt:2 stop_name="Platform \"East\"\tA" [forbidden_field_character] GTFS field values must not contain tabs, carriage returns, or newlines
ERROR stops.txt:3 stop_name="North\nAnnex" [forbidden_field_character] GTFS field values must not contain tabs, carriage returns, or newlines
ERROR stops.txt:5 stop_name="South\tGate" [forbidden_field_character] GTFS field values must not contain tabs, carriage returns, or newlines
FAIL: 6 parsed files, 9 records, 3 findings
```

Diagnostic output also escapes other control characters in values. This
synthetic record uses an unresolved service ID containing an escape character:

```text
moon run cmd/main examples/control-character-diagnostic
ERROR trips.txt:2 service_id="WK\u001b[31m" [unresolved_reference] referenced ID does not exist in calendar.txt or calendar_dates.txt
FAIL: 6 parsed files, 8 records, 1 finding
```

The CLI also enforces the GTFS service-calendar file requirement. A feed must
include `calendar.txt` or `calendar_dates.txt`; this fixture shows the result
when both are absent:

```text
moon run cmd/main examples/no-service-calendar
```

```text
Wayfarer: checking examples/no-service-calendar
ERROR calendar.txt/calendar_dates.txt [missing_service_calendar] at least one service calendar file is required
FAIL: 5 parsed files, 7 records, 1 finding
```

Fixed-stop rows may use a paired on-demand pickup/drop-off window. This fixture
is intentionally invalid: it combines a window with event times and forbidden
enum choices, and includes an invalid `timepoint` value:

```text
moon run cmd/main examples/stop-time-conditional-errors
```

```text
ERROR stop_times.txt:2 timepoint="2" [invalid_enum_value] timepoint must be empty, 0, or 1
ERROR stop_times.txt:2 arrival_time="09:00:00" [forbidden_with_pickup_drop_off_window] arrival_time must be empty when a pickup/drop-off window is defined
ERROR stop_times.txt:2 departure_time="09:01:00" [forbidden_with_pickup_drop_off_window] departure_time must be empty when a pickup/drop-off window is defined
ERROR stop_times.txt:2 pickup_type="0" [forbidden_with_pickup_drop_off_window] pickup_type must be 1 or 2 when a pickup/drop-off window is defined
ERROR stop_times.txt:2 drop_off_type="0" [forbidden_with_pickup_drop_off_window] drop_off_type must not be empty or 0 when a pickup/drop-off window is defined
ERROR stop_times.txt:2 continuous_pickup="2" [forbidden_with_pickup_drop_off_window] continuous_pickup must be 1 or empty when a pickup/drop-off window is defined
ERROR stop_times.txt:2 continuous_drop_off="0" [forbidden_with_pickup_drop_off_window] continuous_drop_off must be 1 or empty when a pickup/drop-off window is defined
ERROR routes.txt:2 continuous_pickup="2" [forbidden_with_pickup_drop_off_window] continuous_pickup must be 1 or empty when a trip on this route defines a pickup/drop-off window
ERROR routes.txt:2 continuous_drop_off="0" [forbidden_with_pickup_drop_off_window] continuous_drop_off must be 1 or empty when a trip on this route defines a pickup/drop-off window
FAIL: 7 parsed files, 9 records, 9 findings
```

The service-calendar fixture covers an invalid weekday enum, a reversed
`calendar.txt` date range, an impossible leap date, and an invalid
`calendar_dates.txt` exception type. It exits with status 1:

```text
moon run cmd/main examples/calendar-semantics-errors
```

```text
ERROR calendar.txt:2 monday="2" [invalid_enum_value] monday must be 0 or 1
ERROR calendar.txt:2 end_date="20260101" [invalid_date_range] end_date must not precede start_date
ERROR calendar_dates.txt:2 date="20230229" [invalid_date] date must be a valid Gregorian date in YYYYMMDD format
ERROR calendar_dates.txt:2 exception_type="3" [invalid_enum_value] exception_type must be 1 or 2
FAIL: 7 parsed files, 9 records, 4 findings
```

The folder must contain `agency.txt`, `stops.txt`, `routes.txt`, `trips.txt`,
and `stop_times.txt`, plus at least one of `calendar.txt` or
`calendar_dates.txt`. If either service table is available, trips' `service_id`
values are checked against the IDs it defines. Other GTFS tables are currently
ignored, except the unsupported location-profile files listed above, which are
explicitly rejected. Try the unsupported-profile fixture to see both the file
and row-level findings:

```text
moon run cmd/main examples/unsupported-location-profile
```

It exits with status 1. The diagnostic summary includes:

```text
ERROR locations.geojson [unsupported_location_profile] location-based on-demand data is outside the supported fixed-stop profile
ERROR stop_times.txt:2 location_id="ZONE-1" [unsupported_location_profile] flexible-location records using location_group_id or location_id are outside the supported fixed-stop profile
FAIL: 6 parsed files, 7 records, 2 findings
```

The checker reads files as UTF-8 and uses the host path separator. The same
relative commands work in PowerShell and POSIX shells; CI runs the parser,
checks, tests, and CLI examples on Linux and Windows. It does not extract ZIP
archives. `moon test` runs the library's unit fixtures, including parsing,
schema, forbidden field values, feed references, minimum trip stops, stop-time
conditionals and enums, service-calendar enums and dates, time formats, time
ordering, and sequence boundaries.

The public library API exposes `parse_csv` for CSV text,
`parse_csv_dataset_profile` for version 1 profile JSON, `validate_schema` for
the built-in GTFS header profile, `validate_gtfs_field_values` and
`validate_feed` for GTFS checks, and `validate_csv_dataset` for user-defined
CSV dataset contracts. Build a `CsvDatasetProfile` from table, field, and
reference rules, parse each input with `parse_csv`, place the results in a
`Map[String, CsvTable]`, and pass the map to `validate_csv_dataset`. The JSON
profile command reads the declared CSV files and constructs the same profile
model before calling that validator. The GTFS
API continues to accept partial table sets and skips checks without context;
the GTFS directory CLI additionally enforces its required files and service
calendar requirements. All parser and validator findings use structured result
types.

The `cmd/main` executable connects these APIs to a local feed directory, while
`cmd/csv-check` applies a JSON-defined generic profile to a CSV directory. Their
only external module dependency is `moonbitlang/x` 0.5.6 for filesystem, path,
and process-exit support; the parser, config decoding, and validation rules
remain implemented in MoonBit.
The upstream module declares Apache-2.0 and identifies its packages as
experimental.

`CsvRow.line` records the physical source line where a data row begins. Quoted
commas, doubled quotes, quoted newlines, CRLF input, and a UTF-8 BOM before the
header are supported. Malformed quoting and rows with the wrong number of
cells return a structured `CsvError` rather than a partial table.

## CSV dataset profile details

Non-empty rules reject empty cells without trimming or normalizing values.
Reference rules require the target column to be declared as a single-column
unique key in the target table, so every referenced value resolves to exactly
one record. The configuration describes CSV files only; it does not make JSON
or database contents into input data sources. See
[`cmd/profile-demo/main.mbt`](cmd/profile-demo/main.mbt) for profile
construction and API use.

Run the JSON-configured checker against the synthetic inventory example:

```text
moon run cmd/csv-check examples/inventory-profile.json examples/inventory-profile
```

Expected output:

```text
Wayfarer: checking CSV profile in examples/inventory-profile
PASS: 2 CSV tables, 4 records, 0 findings
```

Point the same profile at the invalid fixture to see a source-located finding
and exit status 1:

```text
moon run cmd/csv-check examples/inventory-profile.json examples/inventory-profile-invalid
```

```text
ERROR orders.csv:3 product_id="P9" [unresolved_reference] referenced value does not exist in products.csv
FAIL: 2 CSV tables, 4 records, 1 finding
```

The config requires `version`, `tables`, and `references`; each table and
reference rule specifies all fields shown in the example. Version 1 rejects an
empty table list. Files are resolved from the supplied directory and profile
filenames must be leaf names, not paths. Malformed profiles or
unreadable/malformed CSV inputs exit with status 2; data findings exit with
status 1. Cell values in findings are quoted and control characters escaped.

The synthetic inventory example demonstrates a passing multi-table dataset:

```text
moon run cmd/profile-demo examples/inventory-profile
```

```text
PASS: 2 CSV tables, 4 records, 0 findings
```

The failing fixture demonstrates a broken product reference and exits with
status 1:

```text
moon run cmd/profile-demo examples/inventory-profile-invalid
```

```text
ERROR orders.csv:3 product_id [unresolved_reference] referenced value does not exist in products.csv
FAIL: 2 CSV tables, 4 records, 1 finding
```

These files are synthetic test data, not records from a business or operator.

The same command can apply a different profile to a three-table enrollment
dataset. This example exercises a composite `(learner_id, class_id)` key and
two cross-table references:

```text
moon run cmd/csv-check examples/enrollment-profile.json examples/enrollment-profile
```

```text
PASS: 3 CSV tables, 7 records, 0 findings
```

Its failing fixture contains both a duplicate enrollment and an unknown class
reference, reported at their source rows:

```text
moon run cmd/csv-check examples/enrollment-profile.json examples/enrollment-profile-invalid
```

```text
ERROR enrollments.csv:4 learner_id,class_id="L1,C1" [duplicate_key] key value is already used in this table
ERROR enrollments.csv:2 class_id="C9" [unresolved_reference] referenced value does not exist in classes.csv
FAIL: 3 CSV tables, 7 records, 2 findings
```

## Development

```sh
moon fmt
moon info
moon check
moon test
```

The GitHub Actions workflow runs formatting, package checks, generated-interface
consistency, unit tests, and valid/invalid directory examples on Linux and
Windows for pushes and pull requests.

## Specification

Header requirements follow the [GTFS Schedule reference](https://gtfs.org/documentation/schedule/reference/).
Wayfarer is an independent open-source implementation and is not affiliated
with the GTFS working group.

## License

Apache-2.0. See [LICENSE](LICENSE).
