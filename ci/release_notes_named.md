Prototype `@TAG@` — the same app on an iPad, a Linux desktop and a Windows PC.

One Flutter tree, one set of CAD kernels, one path tracer, one Liquid Glass
chrome. Built from `@REF@` at `@SHA@` by [this run](@RUN@), which launched the
desktop builds and checked that the kernels, the path tracer and the GPU
viewport all came up before packaging anything.

## Which file

| | |
|---|---|
| `ipadprocad-@TAG@.ipa` | iPad. Unsigned — install with SideStore or AltStore, which re-sign on install. See `AUTOINSTALL.md`. |
| `Prototype-@TAG@-x86_64.AppImage` | Linux, one file. `chmod +x` it and run it. |
| `prototype-@TAG@-linux-x64.tar.gz` | Linux, unpacked. `./install.sh` puts it in `~/.local` with its icon, its desktop entry and the `.ptp` / `.pts` / `.pas` associations; `./uninstall.sh` takes it back out and leaves your documents alone. |
| `prototype-@TAG@-windows-x64.zip` | Windows. Unzip anywhere and run `prototype.exe`. |

A platform whose build was not green is simply absent — the release is
assembled by three workflows that each attach their own build.

## What each one wants from the system

**Linux:** the GTK 3 stack, which a desktop already has. Qt and OCCT travel
inside the bundle, so there is nothing else to install. `zenity` is worth
having — it is what backs the file chooser.

**Windows:** Windows 10 or newer and the Visual C++ 2015-2022 runtime, which
almost every machine already has. Everything else travels in the zip. Windows
will show a SmartScreen warning the first time, because the build is not
code-signed: "More info", then "Run anyway".

**iPad:** iPadOS 17 or newer.

## The two renderers

The shaded viewport is flutter_scene on Flutter GPU (RealityKit on the iPad);
rendered mode is Cycles, the same renderer and the same shim on all three,
picking the fastest backend the build has and the machine can run.

The chrome is a real shader rather than a picture of one, and it costs two
backdrop passes per surface. On a desktop with no GPU worth the name — a VM, a
remote desktop, an old integrated chip — set `PROTOTYPE_GLASS=0` in the
environment and it draws the painted panels instead. `PROTOTYPE_GPU=0` does
the same for the 3D viewport, which falls back to a CPU painter.

## Sharing between devices

Settings has a share code. Type the same twelve characters on two devices on
one network — an iPad and a PC count — and they keep the same documents and
the same settings, live. No account, no server, nothing leaving the network.
Adding, changing or deleting a document on one device does the same on all of
them.

The connection is authenticated by the code but NOT encrypted, so use it on a
network you trust. Windows Firewall will ask the first time: allow it on
private networks, or sharing does nothing. The iPad asks for local network
permission for the same reason.

Checksums are in `SHA256SUMS-linux.txt` and `SHA256SUMS-windows.txt`.

See `LINUX.md` in the tree for what is shared between the three and what had
to be written more than once.
