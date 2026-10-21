# Wayfarer

Wayfarer is a MoonBit toolkit for checking General Transit Feed Specification
(GTFS) Schedule data. It is being built as a reusable validator for transit
feed maintainers and developers who need clear, reproducible data-quality
checks.

The first release increment establishes the input layer: a strict CSV reader
with source locations, rectangular-row checks, and required-header checks for
the core GTFS tables listed below. It does not yet validate relationships
between files or timetable semantics.

## Current coverage

| Table | Unconditionally required headers checked |
| --- | --- |
| `agency.txt` | `agency_name`, `agency_url`, `agency_timezone` |
| `stops.txt` | `stop_id` |
| `routes.txt` | `route_id`, `route_type` |
| `trips.txt` | `route_id`, `service_id`, `trip_id` |
| `stop_times.txt` | `trip_id`, `stop_sequence` |
| `calendar.txt` | `service_id`, weekday flags, `start_date`, `end_date` |

GTFS has conditional requirements and newer location and fare files. Wayfarer
does not claim to validate those yet. In particular, a header-only check cannot
decide whether conditional fields are required for a specific row. The
validator will report its supported rule set explicitly as coverage grows.

## Try it

The package is not published to Mooncakes yet. From a checkout with the MoonBit
toolchain installed, run:

```sh
moon test
```

The public library API exposes `parse_csv` for CSV text and `validate_schema`
for checking the header profile of one supported table. Parsing failures and
schema findings use structured result types.

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
