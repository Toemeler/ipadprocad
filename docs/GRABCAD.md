# GrabCAD Community integration

Open the gallery's **+ → Search GrabCAD**, enter a query, and choose a model.
Only models whose actual files include an importable STEP/STP, IPT, DXF, STL,
OBJ or 3MF are displayed. Software labels are not proof of compatibility:
STEP/IGES uploads are checked by filename, and nested folders are inspected.
ZIP-only and unsupported native CAD uploads are omitted. Compatibility means a
supported format; damaged files can still fail at import.

Inside an assembly, use **Place → Search GrabCAD**. This entry is available
even when the local gallery contains no parts. Assembly searches exclude DXF
drawings and show only importable 3D files. The selected file becomes a local
part or subassembly document and is inserted into the initiating assembly,
which remains the active document when the operation finishes or fails.
The first component is grounded; later components use the normal placement
rules. Placement is saved and supports the assembly's existing undo/redo.

Search is debounced, stale responses are discarded, and metadata requests are
limited to four at once. Up to three incompatible-only pages are scanned per
request before offering **Search more results**. If individual file listings
fail, verified models remain visible with a retryable warning; unverified
models are never displayed. Complete failures distinguish access denial,
timeout, and service errors rather than claiming that no models exist.

On iPad, Windows and Linux, opening Search GrabCAD first opens GrabCAD's own sign-in page. An
existing authenticated session proceeds automatically. Search and downloads
then use the same persistent browser session. iPad copies WebKit cookies into
native URLSession requests. Windows uses WebView2 and Linux uses WebKitGTK;
desktop metadata fetches run inside the website's origin and downloads use the
browser's native download manager. Cookies, account payloads and CSRF tokens
never cross the Dart bridge.
Access denial offers sign-in again; a protected download is retried once after
renewing the session. Cancellation and session expiry are handled explicitly. Downloads stream to a
private temporary directory, have a 250 MB limit, and are deleted after the
existing document importer has copied its required sources. Imported documents
therefore remain usable offline. STEP assemblies use the existing assembly
importer rather than being flattened by this integration.

Windows requires the Microsoft Edge WebView2 Evergreen runtime. If it is
missing, the app offers Microsoft's runtime download page. Linux requires
WebKitGTK 4.1 (`libwebkit2gtk-4.1-0` on Ubuntu/Debian); an absent runtime is
reported before search, without preventing the CAD app from launching. Linux
builds need `libwebkit2gtk-4.1-dev`. Login closes automatically for an existing
session; Done checks sign-in and closing the login cancels without starting a
search. Both gallery and assembly imports use this flow.

## Maintenance and validation

`frontend/lib/grabcad/grabcad_client.dart` is the only adapter for Community's
website API. It is reachable today but is not a documented public integration
contract; endpoint or response changes can require an adapter update. There is
no scraping fallback, shared credential service, or model redistribution.

GrabCAD's [website terms](https://grabcad.com/terms) apply to downloaded models;
the standard user-submission cross license covers non-commercial internal use.
The browser displays each model's creator.

Host tests cover file verification, folder traversal, pagination, stale-query
suppression, malformed responses, streaming downloads, and authentication/error
responses, native metadata dispatch/cancellation, and partial-result recovery.
Every bug report includes `grabcad/diagnostics.json`, even if GrabCAD was not
used. It carries the current session's search queries, result counts, selected
file, download/import outcomes and timings. On iPad, Windows and Linux it also carries native
login/navigation failures, browser process termination, native network error
domain/code, HTTP status, byte counts and active operations. Each history is
bounded to 300 events with explicit dropped-event counts; native capture has a
two-second timeout and failures are recorded without preventing the report.
Passwords, cookies, CSRF tokens, URL queries/fragments and account payloads are
excluded. Search queries and model filenames are included as diagnostic context.
Before shipping, build the Swift bridge with Xcode and test on iPad:
first login and retry, cancelled login, expired session, cancelled download,
STEP assembly import, mesh import, save/restart/offline reopen, and a download
over the size limit. Account sign-in and authenticated downloads still require real-device testing
on each supported platform. The desktop session workflow compiles both native
bridges and exercises their shared scripts; it does not automate a user login.
