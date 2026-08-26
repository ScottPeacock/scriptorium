# foliate-js

[foliate-js](https://github.com/johnfactotum/foliate-js) (MIT) gets vendored
here at milestone M4, alongside the `reader.html` shim that hosts it.

It is the same engine Grimmory's own web reader uses — Grimmory vendors it at
`frontend/src/assets/foliate/`. Running it here too is what makes reading
positions round-trip exactly: Grimmory stores EPUB progress as an EPUB CFI, and
CFIs are only meaningful between engines that agree on how to generate them.

Keep this directory in sync with the foliate-js revision Grimmory ships. If the
two drift far enough apart, positions written by one reader may not resolve
cleanly in the other.
