# CleanR — Attribution & Notices

CleanR was created by **Apex Studio LLC** and is licensed by Apex Studio LLC.
CleanR's own original material is governed by the strict proprietary terms in
[`LICENSE`](./LICENSE). CleanR is built on and draws from three open-source
projects. Their licenses and attributions are preserved below and in
[`LICENSES/`](./LICENSES/).

## Apex Studio_1 (base codebase) — BSD-3-Clause

CleanR is a fork/evolution of **Apex Studio_1** (originally *MacSai*), an open-source
Mac cleaner, optimizer, and malware scanner. Its modular Swift package layout
(`CleanR` app + `CleanRKit` shared engine + `CleanRMenu` menu-bar process), the
GRDB.swift persistence layer, and the 862-case XCTest suite all derive from it.

- License: **BSD-3-Clause** — see
  [`LICENSES/MacSai-BSD-3-Clause.txt`](./LICENSES/MacSai-BSD-3-Clause.txt).
  The original copyright notice is retained as required by the BSD-3-Clause
  terms. That license applies to the upstream component; it does not make
  CleanR as a whole open source.

## Apex Studio_2 (ported features) — MIT

Several CleanR modules are ported from **Apex Studio_2** (originally *PureMac*), a
free open-source macOS cleaner. Ported functionality includes Similar Photos,
Scheduled Auto-Clean, Homebrew-cask app updates, AI-tool cache categories, and the
Finder "Uninstall" service integration.

- License: **MIT** — the following copyright notice is retained per the MIT terms:

  > Copyright (c) 2026 Apex Studio_2 (PureMac) Contributors

  Permission is hereby granted, free of charge, to any person obtaining a copy of
  this software, to deal in the Software without restriction, including the rights
  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies.
  The original authors are credited here in satisfaction of the MIT attribution
  requirement.

## Apex Studio_3 (design inspiration only) — GPL-3.0

CleanR's companion CLI behavior — live status dashboard, `purge`, installer-file
discovery, and safety rules — was **informed by studying** **Apex Studio_3**
(originally *Mole*), a GPL-3.0 terminal cleaner. **No GPL-3.0 source code is copied,
ported, or linked into CleanR**; the logic is reimplemented natively in Swift.
CleanR's own contributions are proprietary and are not open-source licensed.

- License: **GPL-3.0** — acknowledged as design inspiration only; no code shared.

---

*CleanR's own name, icon, and branding are original and not derived from any of the
three projects above.*