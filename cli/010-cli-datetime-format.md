- Start Date: 2021-06-11
- RFC PR:
- Issue:

### Format timestamp fields using a flag

When printing data in `--table` or `--card` views, allow switching the format of the timestamp fields (ie. `google.protobuf.Timestamp`) 

Add `--format-time` flag with possible values:
- `relative` to print in a format `6 hours ago`. Use as default format in tty environment
- `raw` to print in a format  `2021-06-16 00:21:24.472487365 +0000 UTC`.
- `iso` flag to print in a format `2021-06-16T00:21:24Z` (ISO 8601, time.RFC3339). Use as default in non-tty environment
- `Jan 2 15:04:05 2006 MST` # ie. custom format using https://golang.org/pkg/time/#Time.Format