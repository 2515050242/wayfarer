# Wayfarer

Wayfarer is a MoonBit toolkit for checking General Transit Feed Specification
(GTFS) Schedule data. It is being built as a reusable validator for transit
feed maintainers and developers who need clear, reproducible data-quality
checks.

The current increments establish a strict CSV input layer and core feed checks:
source-located CSV parsing, rectangular-row and required-header checks, selected
identifiers and references between core GTFS tables, and key stop-time schedule
fields. This is a deliberately limited validator, not a complete GTFS
conformance checker.

## Current coverage

| Table | Unconditionally required headers checked |
| --- | --- |
| `agency.txt` | `agency_name`, `agency_url`, `agency_timezone` |
| `stops.txt` | `stop_id` |
| `routes.txt` | `route_id`, `route_type` |
| `trips.txt` | `route_id`, `service_id`, `trip_id` |
| `stop_times.txt` | `trip_id`, `stop_sequence` |
| `calendar.txt` | `service_id`, weekday flags, `start_date`, `end_date` |
| `calendar_dates.txt` | `service_id`, `date`, `exception_type` |

## Feed relationship checks

`validate_feed` accepts the core tables that are available and checks:

- `stop_id`, `route_id`, and `trip_id` are non-empty and unique within their
  supported table.
- `(trip_id, stop_sequence)` is present and unique in `stop_times.txt`.
- Each `trips.route_id` resolves to `routes.route_id`.
- When `calendar.txt` or `calendar_dates.txt` is supplied with a `service_id`
  column, each `trips.service_id` resolves to the union of those service IDs.
- In `calendar_dates.txt`, `(service_id, date)` pairs are unique and `date`
  is non-empty.
- Each `stop_times.trip_id` resolves to `trips.trip_id`.
- A non-empty `stop_times.stop_id` resolves to `stops.stop_id`.
- `stop_sequence` is a non-negative integer and unique within each trip. Gaps
  are accepted. Its numeric value defines stop order; CSV rows need not be
  physically sorted by that value.
- Non-empty `arrival_time` and `departure_time` values use `H:MM:SS` or
  `HH:MM:SS`; minute and second values must be from `00` to `59`. Hours above
  24 are accepted for service after midnight.
- Provided arrival and departure times do not move backward when stop rows are
  read in `trip_id` and numeric `stop_sequence` order. Equal consecutive times
  are accepted, and blank or malformed times are excluded from this comparison.

Findings include the source file, physical CSV line, field, offending value,
stable code, and a short explanation. Missing table context skips checks that
need that table; callers should run `validate_schema` for each supplied table
as well. Trip service IDs are checked only when at least one service table
provides its `service_id` column; `calendar_dates.txt` may provide service IDs
without a weekly `calendar.txt`. This check does not validate calendar date
syntax, date ranges, or `exception_type` values. An empty `stop_times.stop_id` is
allowed here because that field is conditionally required by GTFS. The
validator does not yet check stop hierarchy, location groups or GeoJSON ID
collisions, conditional field requirements, `timepoint` rules, or other
conditional stop-time fields. GTFS defines `stop_sequence` as the order of
stops along a trip; this validator uses the numeric sequence values and does
not require CSV rows to be sorted. See the
[GTFS Schedule reference](https://gtfs.org/documentation/schedule/reference/)
for the complete specification.

GTFS also has conditional requirements and newer location and fare files.
Wayfarer does not claim to validate those yet; the supported rule set is listed
explicitly above and will grow in later increments.

## Try it

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
ERROR stop_times.txt:2 arrival_time="25:60:00" [invalid_time] time must use H:MM:SS or HH:MM:SS with minutes and seconds from 00 to 59
ERROR stop_times.txt:2 departure_time="25:61:00" [invalid_time] time must use H:MM:SS or HH:MM:SS with minutes and seconds from 00 to 59
ERROR stop_times.txt:4 arrival_time="25:00:00" [time_order_violation] time precedes an earlier defined time in this trip's stop_sequence order
FAIL: 6 parsed files, 9 records, 6 findings
```

The folder must contain `agency.txt`, `stops.txt`, `routes.txt`, `trips.txt`,
and `stop_times.txt`; `calendar.txt` and `calendar_dates.txt` are checked when
present. If either service table is available, trips' `service_id` values are
checked against the IDs it defines. Other GTFS tables are currently ignored,
so location-based on-demand feeds are outside this command's supported input
profile. The checker reads files as UTF-8 and uses
the host path separator, so the same relative commands work in PowerShell and
POSIX shells. It does not extract ZIP archives. `moon test` runs the library's
unit fixtures, including parsing, schema, feed references, time formats,
time ordering, and sequence boundaries.

The public library API exposes `parse_csv` for CSV text, `validate_schema` for
checking the header profile of one supported table, and `validate_feed` for
the relationship and stop-time checks above. `GtfsTables::new` accepts the
core tables; `GtfsTables::with_services` also accepts optional `calendar.txt`
and `calendar_dates.txt` context. Parsing failures and schema/feed findings
use structured result types. A caller can build `GtfsTables` from the results
of `parse_csv` and pass the available tables to `validate_feed`.

The `cmd/main` executable connects these APIs to a local feed directory. Its
only external module dependency is `moonbitlang/x` 0.5.6 for filesystem, path,
and process-exit support; the parser and validation rules remain in this MoonBit module.
The upstream module declares Apache-2.0 and identifies its packages as
experimental.

`CsvRow.line` records the physical source line where a data row begins. Quoted
commas, doubled quotes, quoted newlines, CRLF input, and a UTF-8 BOM before the
header are supported. Malformed quoting and rows with the wrong number of
cells return a structured `CsvError` rather than a partial table.

## Development

```sh
moon fmt
moon info
moon check
moon test
```

The GitHub Actions workflow runs formatting, package checks, and tests on pushes
and pull requests.

## Specification

Header requirements follow the [GTFS Schedule reference](https://gtfs.org/documentation/schedule/reference/).
Wayfarer is an independent open-source implementation and is not affiliated
with the GTFS working group.

## License

Apache-2.0. See [LICENSE](LICENSE).
