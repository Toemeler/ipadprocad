# Live icon preview

Draw an icon on the PC, save, look at the iPad. About one second, no build, no
install.

Both devices have to be on the same Wi-Fi. Nothing leaves the network and
there is no account, no upload and no cloud anywhere in this.

## Once, on the Windows PC

1. Install Python from python.org if you have not (tick **Add python.exe to
   PATH** in the installer).
2. Open PowerShell and install the one dependency:

       py -m pip install pillow

## Once, in Blender

**Render Properties → Film → Transparent** — tick it.

Without this the render has a white background baked in, which arrives on the
iPad as a white tile on the dark ribbon. The script keys the white out and
warns you, but a hard key leaves a faint fringe on the edges; ticking the box
is the real fix.

Then **Output Properties → Output Path**: point it at the `renders` folder
beside this README, and set the file format to **PNG, RGBA**.

## Every session

In PowerShell:

    py C:\path\to\ipadprocad\tools\icon-sync\serve.py

It prints the address to type on the iPad:

        192.168.1.42:8080

On the iPad: **Settings → Diagnostics → Icon Preview**, type that in, tap
**Connect**. The status line says how many icons are live.

Now render (F12) and save into the `renders` folder. The tablet picks it up on
the next poll.

## Naming the files

The file name says which icon it replaces:

| File | Replaces |
| --- | --- |
| `CR.extrude.png` | `CR['extrude']` — Create panel, Extrude |
| `MO.fillet.png` | `MO['fillet']` — Modify panel, Fillet |
| `extrude.png` | the same as `CR.extrude.png` |
| `layerBigIcon.png` | the standalone `layerBigIcon` |

The short form works whenever no other map has a key by that name. Where one
does — `split` is in both `MD` and `MO`, `plane` in both `WF` and `PL` — only
the qualified name resolves. `docs/icon-inventory.html` lists every name.

**Delete a render** and that icon goes straight back to the one built into the
app, which is the quickest way to answer "is mine actually better?".

## What the script does to each render

Crops away everything that is not artwork, centres what is left in a square,
adds a 6% margin and resizes to 256×256 RGBA. So it does not matter that
Blender renders 1920×1080 with the icon somewhere in the middle — frame it
however you like.

    py serve.py [folder] [--port 8080] [--size 256]

## Notes

- **The first connection asks for permission.** iOS shows "…would like to find
  and connect to devices on your local network". Allow it, or nothing will
  load. If you tapped no by accident: iPad Settings → the app → Local Network.
- **The address changes** when your PC gets a new DHCP lease. Retype it, or
  give the PC a static lease in your router.
- **Nothing ships.** The override is empty until you type a host, and empty
  means every icon is the one compiled into the app. Clear the field (or tap
  **Turn off**) to go back.
- **Preview only.** These are PNGs, so they do not follow the accent colour the
  way the built-in SVGs do — `themedIcon()` only recolours vectors. Fine for
  judging shape and weight; see the note in `frontend/lib/icon_preview.dart`
  before deciding what actually ships.
