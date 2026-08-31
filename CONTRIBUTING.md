# Contributing

Jig eats its own dogfood: a change to Jig is gated exactly the way Jig gates anyone
else's repo. Three rules cover almost everything — the long form is
`specs/constitution.md`.

- **Pull requests only.** Nothing lands on `main` directly — not docs, not generated
  artifacts, not one-line fixes. The checkpoint is the point.
- **Specs bring gates.** Work arrives as a spec directory (`specs/<slug>/` with
  `spec.md`, `tasks.txt`, `verify.sh`). The gate decides done, never the model — and
  never the author.
- **Red before green.** A gate must prove it can fail: run it against the pre-work tree
  (or a deliberate near-miss), record the red in the spec's `evidence/`, then show it
  green after. A gate that has never failed proves nothing.

Start from `specs/TEMPLATE.md` — its §11 traps were each paid for. Slugs are
`YYYYMMDD<letter>-<name>` and the date+letter prefix must be unique;
`specs/README.md` indexes every spec, both directions gated.
