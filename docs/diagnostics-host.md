# Local diagnostics host

The development receiver accepts GlucoScope's plain-text diagnostics exports over the local network. It has no authentication, so run it only on a trusted LAN.

Start it from the repository root:

```sh
python3 scripts/diagnostics_server.py
```

It listens on all interfaces at port `8765` and stores exports in `/tmp/glucoscope-diagnostics`. Each file has mode `0600`; the server logs only its byte count and path.

Point the app at `http://<Mac-LAN-address>:8765/diagnostics`. Check connectivity from another device on the LAN at `http://<Mac-LAN-address>:8765/health`, which returns `{"status":"ok"}`.

The API accepts `POST /diagnostics` with a UTF-8 `text/plain` body up to 1 MiB. A successful request returns HTTP 201 with `{"saved":"<filename>"}`. Other routes do not serve files.

The development app defaults to `http://10.0.0.22:8765/diagnostics`; start the receiver when needed rather than assuming a previous process is still running. The URL is editable. Keep the iPhone on a network that can reach the host, and allow GlucoScope's Local Network permission when prompted.

The temporary app has a **Send diagnostics** control and a **Send after NFC setup** option. Automatic upload sends one snapshot after each NFC setup result; Bluetooth packet logging does not trigger repeated HTTP requests. Copy/share remain available if the receiver cannot be reached.

Validation: the app-owned Swift uploader sent an exact synthetic snapshot through the running receiver and received its saved-file acknowledgement; an HTTP 404 was surfaced as a failure. The synthetic file was removed afterward. Receiver checks also cover health, UTF-8 text uploads, 1 MiB size rejection and unsupported content types. Simulator and iPhone compilation are checked separately from a real iPhone's local-network permission/reachability.

The iOS test build declares local-network access and an HTTP exception for `10.0.0.22`. If switching to another numeric host on newer iOS versions, its ATS exception may also need updating; a `.local` hostname works with the local-network allowance. No global HTTP exception is enabled.
