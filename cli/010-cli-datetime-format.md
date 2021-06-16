- Start Date: 2021-06-11
- RFC PR:
- Issue:

### Format timestamp fields using a flag

When printing data in `--table` or `--card` views, allow swithing the format of the timestamp fields (ie. `google.protobuf.Timestamp`) 

Add `--time-format` flag with possible values:
- `relative` to print in a format `6 hours ago`. Use as default format in tty environment
- `raw` to print in a format  `2021-06-16 00:21:24.472487365 +0000 UTC`. Use as default in non-tty environment
- `datetime` flag to print in a format `2021-06-16T00:21:24Z` (ie. time.RFC3339)
- `date` to print in a format `2021-06-15`
- `time` to print in a format `00:21:24`
