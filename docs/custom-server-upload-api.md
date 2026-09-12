# Custom server upload API

The custom GlucoScope backend accepts one standalone sensor reading at `POST /api/s1/entries`.
Writes require the server's `api_token`; a deployment without `api_token` keeps the existing
read-only endpoints available but rejects writes. Send the token as `Authorization: Bearer <token>`.

The request uses `application/json`, is limited to 4 KiB, and has this shape:

```json
{"id":"84a146be-1a63-4d09-8f8d-704da981f6a4","time":1742644800,"value":7.0}
```

- `id` is the app's stable reading UUID and is stored as diagnostic provenance.
- `time` is the original sample time in Unix seconds.
- `value` is mmol/L and must be within 1.0 through 33.3, matching the iOS store's accepted
  18 through 600 mg/dL range after conversion by 18.0182.

Success returns HTTP 201 with `{"saved":"<id>"}`. Authentication failures return 401, invalid
JSON or values return 400, oversized requests return 413, and storage failures return 500.

`GET /api/s1/status` includes `uploadsEnabled`. The app's Test connection action requires this to
be true as well as requiring successful bearer authentication, so a tokenless read-only deployment
is not reported as writable.

Influx identifies these points by measurement and timestamp. Retrying a reading therefore updates
the same point. If two local record variants have exactly the same sample second, the later request
coalesces with the earlier point; the server's Viewer format represents one value per timestamp.
The reading ID is a field rather than a tag so per-reading IDs do not create unbounded series
cardinality.

LibreLink credentials are optional. If neither username nor password is present, LibreLink sync is
disabled and direct app uploads still run. If either is present, both are required. The realm defaults
to `EU` when omitted. Existing deployments with complete LibreLink settings continue to sync.
