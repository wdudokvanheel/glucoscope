# iOS server uploads implementation audit

This audit maps the upload decisions in `ios-ble-app-experience-plan.md` to the
implementation and its executable evidence. The feature uses only committed readings from the
standalone `ReadingStore`; Viewer data sources do not feed this store.

## Requirement coverage

| Requirement | Implementation | Evidence |
| --- | --- | --- |
| Nightscout and custom backend; multiple destinations | `ServerUploadBackend` and a stable, insertion-ordered destination list. Every delivery carries a destination ID and endpoint revision. | `multipleTargetsAndNewestFirstHistory` checks independent queues. |
| Test connectivity and authentication without draining the queue | Tests use GET only. Custom servers require authenticated `/api/s1/status` with `uploadsEnabled: true`. Nightscout checks public v1 status, exchanges the configured access token for a JWT, and checks v3 `apiPermissions.entries` for create permission. An older Nightscout server that cannot expose permissions reports that write permission cannot be verified; it is not shown as writable. | `ServerUploadTransportSmoke` checks the custom writable/read-only results, Nightscout three-request check, missing introspection, and read-only permissions. The flow follows Nightscout's [API v3 authentication tutorial](https://github.com/nightscout/cgm-remote-monitor/blob/master/lib/api3/doc/tutorial.md). |
| New readings only by default; optional dated or complete history | A destination persists `automaticUploadSince` at creation. Reconciliation uses the reading's durable `createdAt`, so old samples received later through NFC are still new commits, while old rows present before destination creation stay excluded. The UI offers a start date or all available history. | `newOnlyCursorSurvivesRestart` checks refresh and relaunch behavior; history selections are covered by the store smoke. |
| No Viewer history and no duplicate local records | Uploads only snapshot existing committed `StoredReadingSnapshot` values. They never write to `ReadingStore`. Delivery deduplication is destination + endpoint revision + reading ID. | Store smokes check deduplication and independent queues. |
| Debug queue and attempt history with redaction | The Debug view lists every non-acknowledged row, last failure, attempt count, sample time, and endpoint revision. It also lists success, failure, cancellation, and interrupted attempts. Endpoint query/user credentials are removed before persistence; secrets are in Keychain; errors redact known secrets and token-shaped values. | `diagnosticsExpireWithoutRemovingPendingWork` and `newOnlyCursorSurvivesRestart` inspect persisted state and redaction. |
| 30-day attempt retention without expiring pending work | Maintenance removes only old attempt rows. Delivery rows remain until acknowledged or explicitly cleared/cancelled. | `diagnosticsExpireWithoutRemovingPendingWork`. |
| Manual retry | Retry changes failed rows back to queued, but requires an enabled destination. Draining still observes standalone mode and pause state. | UI exposes **Retry failed readings now** only when applicable; coordinator smoke verifies mode gating. |
| Newest-first sending and progress | Claims sort by sample time descending, with reading ID as a deterministic tie-breaker. Progress shows an in-flight sample time and the oldest pending sample as the target start date. | `multipleTargetsAndNewestFirstHistory`. |
| Pause, resume, cancel remaining history, and clear queue | Pause retains all rows. Cancel removes bulk/history/catch-up work and keeps live new-reading deliveries. Clear removes all pending work. Neither operation changes local readings or completed remote writes. | Destination UI has distinct controls and explanatory confirmation text; `clearWaitsForInflightOutcome` covers the in-flight rule. |
| Viewer mode | `setStandaloneActive(false)` prevents claims and retry wakes. A request already in flight completes and records its outcome. Returning to standalone reconciles and resumes. | `ServerUploadCoordinatorSmoke` exercises the complete Viewer transition with a gated in-flight request. |
| Disable and optional interval catch-up | Disable persists `disabledAt` and preserves the queue. Re-enable presents an explicit missed-reading toggle and start date constrained to the disabled interval. Catch-up selects by durable commit time, not sample time. Re-enable without consent resets the automatic cursor and skips missed commits. | `disabledCatchUpRequiresConsent`. |
| Address migration consent, optional history, and provenance | Editing backend/address exposes pending-transfer and history choices. Migration increments endpoint revision, retires declined old work, attributes old outcomes to the old revision, and deduplicates overlap between transferred pending rows and backfill. | `migrationKeepsEndpointProvenanceAndDeduplicatesOverlap`. |
| Credential-only edit | Leaving the token blank retains the Keychain reference. Supplying a token replaces the Keychain item without changing endpoint revision or queue rows. Pasted Nightscout `token=` prefixes are normalized. | `credentialOnlyEditPreservesQueue`; the editor explains blank-token behavior. |
| Every commit reaches collection consumers and uploads | `ReadingStore.commitStream()` creates an independent subscriber stream and broadcasts each commit. The uploader subscribes before its startup reconciliation to close the snapshot/subscribe race. | `ReadingStoreBroadcastSmoke` checks two subscribers receive the same commit and finish cleanly on store close. |
| Durable restart | The upload store uses atomic JSON with `NSFileProtectionCompleteUntilFirstUserAuthentication`. A row left sending at process termination returns to queued with an interrupted attempt and keeps the same stable remote identity. | Store restart smoke plus coordinator/store implementation review. |

## Chosen open defaults

- Destinations use a user-entered name, appear in creation order, and start enabled and unpaused.
- Tokens are required when creating either backend type and are stored as
  `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` Keychain items. Editing with a blank token keeps
  the current credential.
- If address migration transfer is declined, unfinished old-address work is cancelled and recorded.
  Old acknowledgements and attempts stay attributed to the old endpoint revision.
- Cancel or clear marks an in-flight row for removal. The request finishes, its success or failure is
  logged, and the row is then removed.
- Attempt logs retain 30 days. Pending rows and their current error state have no age limit.

## Backend contract

The custom server adds authenticated `POST /api/s1/entries` for one `{id,time,value}` reading, with
a 4 KiB body limit and validation before Influx access. `GET /api/s1/status` reports whether uploads
are configured. A server without `api_token` preserves its previous public GET behavior but rejects
writes. Retry identity is Influx measurement + sample timestamp; the UUID is a field for provenance,
avoiding one Influx series per reading. Same-timestamp observations coalesce to the later write because
the Viewer contract represents one value per timestamp. See `custom-server-upload-api.md`.

Nightscout writes use the documented v1 entries array with `sgv`, epoch-millisecond `date`, ISO
`dateString`, and a stable reading UUID. Any 2xx response completes the delivery. The current v1
handler returns the stored entry array on success, as confirmed in its
[response formatter](https://github.com/nightscout/cgm-remote-monitor/blob/master/lib/api/entries/index.js)
and [batch endpoint tests](https://github.com/nightscout/cgm-remote-monitor/blob/master/tests/api.v1-batch-operations.test.js).
The request shape also follows Nightscout's
[v1 Swagger contract](https://github.com/nightscout/cgm-remote-monitor/blob/master/lib/server/swagger.yaml).
GlucoScope sends one reading per request, so a batch cannot be partially accepted; persistence errors
from that one-item pipeline produce a non-2xx response and remain queued.

## Validation commands

```sh
sh ios/ServerUploadTests/run.sh
cargo test webserver::tests --bin glucoscope
cargo test measurement:: --bin glucoscope
xcodebuild -project ios/GlucoScope.xcodeproj -scheme GlucoScope \
  -sdk iphonesimulator -configuration Debug -derivedDataPath <temporary-path> \
  CODE_SIGNING_ALLOWED=NO build
```

The Swift smoke suite covers store persistence and policy, URL request contracts, ReadingStore
broadcasting, and coordinator lifecycle. The Rust tests cover auth, body validation, upload enablement,
and deterministic Influx identity. These are contract and local lifecycle tests; they do not send a
reading to a live third-party Nightscout deployment or a live Influx instance.
