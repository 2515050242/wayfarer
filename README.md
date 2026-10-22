# Wayfarer

Wayfarer is a MoonBit toolkit for checking General Transit Feed Specification
(GTFS) Schedule data. It is being built as a reusable validator for transit
feed maintainers and developers who need clear, reproducible data-quality
checks.

The first increments establish a strict CSV input layer and core feed checks:
source-located CSV parsing, rectangular-row and required-header checks, plus
selected identifiers and references between the core GTFS tables listed below.
This is a deliberately limited validator, not a complete GTFS conformance
checker.

## Current coverage

| Table | Unconditionally required headers checked |
| --- | --- |
| `agency.txt` | `agency_name`, `agency_url`, `agency_timezone` |
| `stops.txt` | `stop_id` |
| `routes.txt` | `route_id`, `route_type` |
| `trips.txt` | `route_id`, `service_id`, `trip_id` |
| `stop_times.txt` | `trip_id`, `stop_sequence` |
| `calendar.txt` | `service_id`, weekday flags, `start_date`, `end_date` |

## Feed relationship checks

`validate_feed` accepts the core tables that are available and checks:

- `stop_id`, `route_id`, and `trip_id` are non-empty and unique within their
  supported table.
- `(trip_id, stop_sequence)` is present and unique in `stop_times.txt`.
- Each `trips.route_id` resolves to `routes.route_id`.
- Each `stop_times.trip_id` resolves to `trips.trip_id`.
- A non-empty `stop_times.stop_id` resolves to `stops.stop_id`.

Findings include the source file, physical CSV line, field, offending value,
stable code, and a short explanation. Missing table context skips checks that
need that table; callers should run `validate_schema` for each supplied table
as well. An empty `stop_times.stop_id` is allowed here because that field is
conditionally required by GTFS. The validator does not yet check service ID
relationships, stop hierarchy, location groups or GeoJSON ID collisions,
conditional field requirements, or timetable value semantics. See the
[GTFS Schedule reference](https://gtfs.org/documentation/schedule/reference/)
for the complete specification.

GTFS also has conditional requirements and newer location and fare files.
Wayfarer does not claim to validate those yet; the supported rule set is listed
explicitly above and will grow in later increments.

## Try it

The package is not published to Mooncakes yet. From a checkout with the MoonBit
toolchain installed, run:

```sh
moon test
```

The public library API exposes `parse_csv` for CSV text, `validate_schema` for
checking the header profile of one supported table, and `validate_feed` for
the relationship checks above. Parsing failures and schema/feed findings use
structured result types. A caller can build `GtfsTables` from the results of
`parse_csv` and pass the available tables to `validate_feed`.

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
