# Printing bug: `pdftopdf filter function failed.`

Untracked working note. Machine: **CachyOS `laptop-p16`** (hostname `laptop-p16`).
Last updated: 2026-10-06.

## Symptom

Printing a PDF fails. CUPS reports:

```
Set job-printer-state-message to "pdftopdf filter function failed.", current level=ERROR
PID ... (/usr/lib/cups/filter/pdftopdf) stopped with status 1.
```

The job stays 0 pages; nothing comes out. Observed for jobs 296/297 (document
*"Developing AI Applications with Python and Flask"*, a Typst-generated PDF).

## Root cause

A bug in **`libcupsfilters`** — not in the PDF, not in Typst, not in the printer.

`pdftopdf` first *flattens* all annotations of the input PDF into page content
(it does this whenever the PDF contains any `/Annots`). For an annotation that
has **no `/N` appearance stream** (typical for **hyperlink annotations**, and for
empty form fields), the old code:

1. registered a Form XObject under a **heap-allocated** name `Fxo<n>`,
2. then **freed that name**.

`pdfioDictSetObj()` keeps the caller's key pointer, so the page `/XObject`
dictionary ends up with dangling keys. When the flattened PDF is reopened,
pdfio fails → `cfFilterPDFToPDF()` returns failure → `pdftopdf` exits 1.

This hits any PDF whose pages carry annotations without an appearance stream,
in particular:

- Typst output containing `link(...)` / hyperlinks,
- Chrome "direct-to-CUPS" printouts (every hyperlink),
- other viewers that emit link annotations.

### Evidence

- `/var/log/cups/error_log` (jobs 296/297) repeats, right before the failure:
  - `WARNING: Appearance stream is missing required /BBox.`
  - `DEBUG: special case ignore annotation with no appearance`
  - `Key 'N' not found.`
  - then `ERROR: pdftopdf filter function failed.`
- Reproduced outside CUPS:

  ```sh
  /usr/lib/cups/filter/pdftopdf 1 "$USER" test 1 "media=A4" INPUT.pdf >/dev/null
  # -> rc=1 and "ERROR: pdftopdf filter function failed."
  ```

### Upstream fix

OpenPrinting/libcupsfilters, issue **#246**, fixed by commit:

```
d3043e3c8b32d73c80f98b7c5d59613a9d844d69
"pdftopdf: keep annotations without an appearance from aborting the job"
2026-09-22, David Reed
```

The fix skips annotations that have nothing to paint and registers any
synthesized XObject under a PDFio-owned name (no more dangling key).

## Environment at time of writing

| Component       | Version installed     |
|-----------------|-----------------------|
| OS              | CachyOS (Arch-based)  |
| cups            | `2:2.4.19-1`          |
| cups-filters    | `2.0.1-3.1`           |
| libcupsfilters  | `2.2.1-2.1`           |
| libppd          | `2.1.1-2.1`           |
| pdfio / poppler | current               |

The repo `libcupsfilters` was `2.2.1.r23.gdee3b387` (a git snapshot that still
predates the fix). So `pacman -Syu` alone did **not** fix it at the time.

## Fix

Build `libcupsfilters` from the upstream fix commit and install it. A patched
package was already built and verified (the built artifact lives under `/tmp`,
which is volatile — see "Handling updates / rebuild" below).

Install:

```sh
sudo pacman -U /tmp/opencode/patch-pkg/libcupsfilters-2.2.1.r26.gd3043e3c-1-x86_64.pkg.tar.zst
sudo systemctl restart cups
```

Revert to the distro package at any time:

```sh
sudo pacman -S libcupsfilters
```

## Immediate workaround (no root, for one file)

Strip the annotations with Ghostscript, then print the cleaned copy:

```sh
gs -q -o /tmp/clean.pdf -sDEVICE=pdfwrite -dPreserveAnnots=false INPUT.pdf
lp -d <printer> /tmp/clean.pdf
```

Caveat: this drops **all** annotations, so filled form-field values may be lost.
Fine for link-only documents (Typst/Chrome output); not ideal for filled forms.

## How to test

1. **Reproduce the bug** (before applying the fix) with any link-bearing PDF:

   ```sh
   /usr/lib/cups/filter/pdftopdf 1 "$USER" test 1 "media=A4" INPUT.pdf >/dev/null
   echo "rc=$?"        # buggy build: rc=1, prints "ERROR: pdftopdf filter function failed."
   ```

   A plain, annotation-free PDF should always return `rc=0` (good control).

2. **Verify the fix** after installing:

   ```sh
   /usr/lib/cups/filter/pdftopdf 1 "$USER" test 1 "media=A4" INPUT.pdf >/tmp/out.pdf 2>/tmp/err.txt
   echo "rc=$?"        # fixed build: rc=0, non-empty /tmp/out.pdf
   ```

3. **End-to-end**: print a link-bearing PDF (e.g. a Typst doc with hyperlinks)
   and confirm the job completes with pages in `lpstat`/CUPS.

## Handling updates / rebuild

`pacman` version comparison: the local package is `2.2.1.r26.gd3043e3c`, the
repo snapshot was `2.2.1.r23.gdee3b387`. Pacman will keep the **higher** one, so
a normal `pacman -Syu` will **not** silently downgrade it. But once the repo
snapshot advances past `r26` (or the repo switches to release `2.2.2`+), pacman
will replace the local build.

After any `libcupsfilters` update:

1. Check the installed version/commit:

   ```sh
   pacman -Q libcupsfilters
   ```

2. Decide whether the distro build already contains the fix. It does if the
   version's git tail is **at or after** `d3043e3`. To check the Arch package's
   pinned commit:

   ```sh
   curl -fsSL https://gitlab.archlinux.org/archlinux/packaging/packages/libcupsfilters/-/raw/main/PKGBUILD | grep _commit
   # fixed if _commit is d3043e3... or a descendant of it
   ```

   Or simply run the "How to test" step 1 — if `rc=0` on a link-bearing PDF,
   you no longer need the local build.

3. If the distro build is still buggy, rebuild the patched package. `/tmp` is
   wiped on reboot, so keep this file as the source of truth and regenerate:

   ```sh
   mkdir -p /tmp/opencode/patch-pkg && cd /tmp/opencode/patch-pkg
   # (write the PKGBUILD below to ./PKGBUILD)
   makepkg -f --noconfirm
   sudo pacman -U libcupsfilters-*.pkg.tar.zst
   sudo systemctl restart cups
   ```

### PKGBUILD used (self-contained, based on Arch's, pinned to the fix)

```bash
pkgname=libcupsfilters
pkgver=2.2.1.r26.gd3043e3
_commit=d3043e3c8b32d73c80f98b7c5d59613a9d844d69 # master 2026-09-22, includes #246 fix
pkgrel=2
pkgdesc="OpenPrinting CUPS Filters - former cups-filters as library functions"
arch=('x86_64')
url="https://github.com/OpenPrinting/libcupsfilters"
license=('Apache-2.0 WITH LLVM-exception')
depends=('libcups' 'libexif' 'pdfio' 'libjxl' 'poppler'
         'libjpeg-turbo' 'libpng' 'libtiff' 'lcms2'
         'fontconfig' 'glibc' 'dbus')
makedepends=('ghostscript' 'git')
source=("git+https://github.com/OpenPrinting/libcupsfilters#commit=$_commit")
sha256sums=('SKIP')

pkgver() {
 cd $pkgname
 git describe --tags | sed 's/-/.r/' | sed 's/-/./'
}

prepare() {
  cd "$pkgname"
  autoreconf -vfi
}

build() {
  cd "$pkgname"
  ./configure --prefix=/usr --sysconfdir=/etc --sbindir=/usr/bin \
    --localstatedir=/var --disable-mutool
  make
}

package() {
  cd "$pkgname"
  make DESTDIR="$pkgdir/" install
  mkdir -p "${pkgdir}"/usr/share/licenses/${pkgname}
  install -m644 LICENSE "${pkgdir}"/usr/share/licenses/${pkgname}/LICENSE
}
```

Alternative: AUR `libcupsfilters-git` (`paru -S libcupsfilters-git`) builds from
master and therefore also contains the fix, but pulls a `libcups-git` dependency
chain and is less reproducible than pinning the commit above.

## Do NOT change Typst PDF generation

The PDF is valid; Typst only emits standard hyperlink annotations. Stripping
links or rasterizing in the build would lose links/quality and only paper over
one input (Chrome and other viewers hit the same bug). Fix the filter instead.

## References

- Upstream issue: OpenPrinting/libcupsfilters **#246**
- Fix commit: `d3043e3c8b32d73c80f98b7c5d59613a9d844d69`
- Arch package: <https://gitlab.archlinux.org/archlinux/packaging/packages/libcupsfilters>
