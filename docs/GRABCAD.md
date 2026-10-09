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
request before offering **Search more results**. A metadata failure is reported
as a retryable error rather than silently claiming that no models exist.

On iPad, downloads use a persistent WebKit GrabCAD login. Credentials stay in
the website's cookie store. The first protected download opens GrabCAD's own
sign-in page; after successful sign-in the selected download is retried once.
Cancellation and session expiry are handled explicitly. Downloads stream to a
private temporary directory, have a 250 MB limit, and are deleted after the
existing document importer has copied its required sources. Imported documents
therefore remain usable offline. STEP assemblies use the existing assembly
importer rather than being flattened by this integration.

The desktop search screen also works, but authenticated downloads currently
require the iPad WebKit bridge. Desktop reports that limitation rather than
opening a login page as a model file.

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
responses. Before shipping, build the Swift bridge with Xcode and test on iPad:
first login and retry, cancelled login, expired session, cancelled download,
STEP assembly import, mesh import, save/restart/offline reopen, and a download
over the size limit. Linux host tests cannot establish these native behaviors.
