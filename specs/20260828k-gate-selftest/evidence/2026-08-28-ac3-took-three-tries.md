# One assertion needed three tries before it could fail

**Date:** 2026-08-28 · while validating this spec's gates before opening it.

Every gate here was checked the way `specs/amendments.md` now requires: run at baseline, run
against a reference implementation, then one mutant per assertion. Nine of ten mutants were
killed by their own assertion on the first attempt. `T03/ac3` — *"the workspace is restored
between mutants"* — took **three**, and each failure was a different way of not exercising the
thing.

| try | what I did | why nothing happened |
|---|---|---|
| 1 | removed the restore *before* each mutant is installed | the reference tool also restores *after* each run, so isolation survived. **The mutant did not disable the behaviour it named.** |
| 2 | removed **both** restore points | mutants run in glob order, and `harmless` sorts before `kills-ac1`. The harmless one ran first, on a clean tree, so there was no contamination for it to be measured against. |
| 3 | renamed to `a-kills-ac1` / `b-harmless` so the destructive one runs first | `b-harmless.txt` carried the *complete good content* of `subject.txt`, so installing it repaired the previous mutant's damage itself. |

It only became falsifiable when the second mutant targeted a **different file** (`other.txt`), so
the first mutant's damage was still present and unrepaired when the gate ran.

## Why this is worth a page

Three times in a row the reading was *"the assertion cannot detect this"* and three times the
assertion was fine. Had the tool existed and scored only "did the gate fail", it would have
reported `ac3` as a weak assertion, and the obvious response — rewrite the assertion — would have
made a correct check worse.

**That is the argument for `WRONG-REASON` as a distinct outcome** (§3.2), and for the rule that a
mutant must be confirmed to exercise the path its assertion covers. The same shape appeared twice
more the same day while validating `20260828j`, on a mutant that patched a code path the assertion
never ran and on one that modelled a bash trap belonging to a different construct.

It also sharpens the guidance for anyone writing a corpus:

- **A mutant must actually disable the behaviour**, not merely delete one of the places that
  implement it. Defensive code with two restore points needs both removed.
- **Order matters** when a corpus is measuring interference. Mutants run in glob order; name them
  so the destructive one runs first.
- **A mutant that supplies complete, valid content repairs its predecessor.** When the property
  under test is isolation, the second mutant must touch a file the first one did not.

Generalising: a mutant is itself a check, and the amendment applies to it —
*name the states it must tell apart*. Here the states were "isolation works" and "isolation does
not", and for two rounds the corpus produced the same reading for both.
