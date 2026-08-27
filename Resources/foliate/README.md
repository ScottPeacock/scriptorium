# foliate-js

Vendored from [johnfactotum/foliate-js](https://github.com/johnfactotum/foliate-js)
(MIT — see `LICENSE`), pinned at commit `78914aef4466`.

This is the same engine Grimmory's web reader runs; Grimmory vendors it at
`frontend/src/assets/foliate/`. Running it here too is what makes reading
positions round-trip exactly. Grimmory stores EPUB progress as an EPUB CFI, and
a CFI only means the same thing to engines that agree on how to generate it —
so a position written from the phone resolves in the browser, on a Kobo, and in
KOReader.

## What's here, and what isn't

Only the EPUB path is vendored: `view.js` and what it reaches for when opening a
zip — `epub.js`, `epubcfi.js`, `paginator.js`, `progress.js`, `overlayer.js`,
`text-walker.js`, `search.js`, `fixed-layout.js`, `footnotes.js`,
`uri-template.js`, and `vendor/{zip,fflate}.js`.

Deliberately omitted: `pdf.js` and its `vendor/pdfjs` tree (tens of megabytes of
cmaps and fonts), plus `mobi.js`, `fb2.js`, `comic-book.js` and `tts.js`.
`makeBook` only imports those when it identifies that format, so an EPUB never
touches them. Adding PDF or comics support means vendoring the matching module.

## Updating

Re-download the same file list at a newer commit and update the pin above. Run
the reader bridge tests afterwards — they open a real EPUB in a real WKWebView
and assert a CFI round-trips, which is the behaviour an update could break.

Keep the revision reasonably close to the one Grimmory ships. If the two drift
far apart, positions written by one reader may stop resolving cleanly in the
other.
