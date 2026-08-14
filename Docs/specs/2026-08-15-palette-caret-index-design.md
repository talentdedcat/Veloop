# Palette Caret Index Correction

## Problem

The clipboard history panel can appear far from the insertion caret in applications such as Notion. The placement resolver is behaving as designed: it anchors the panel to the caret rectangle it receives. The incorrect position originates in the Palette input method helper.

`attributesForCharacterIndex:lineHeightRectangle:` interprets its index relative to the active inline input session. When no inline session exists, InputMethodKit requires index `0` to request geometry for the current selection. Veloop instead passes `selection.location`, which is a document-relative offset. Some clients return a caret-shaped rectangle for that invalid semantic input, so the response passes geometry validation and incorrectly wins as the preferred Palette result.

## Required Behavior

- Palette remains the preferred caret source.
- With no inline input session, Palette requests the current selection rectangle using character index `0`.
- The selected document range is still read and must be collapsed before any caret geometry is accepted.
- `firstRectForCharacterRange:` continues to use `selection.location`, because that API expects a document-relative range.
- Accessibility remains an independent validation and fallback source.
- Panel placement behavior remains unchanged: prefer the caret's lower-right side, then upper-right when required by screen bounds.

## Design

Change only the Palette helper's `attributesForCharacterIndex:lineHeightRectangle:` argument from `selection.location` to `0`. Do not add application-specific rules, coordinate offsets, timing delays, or placement compensation.

The caret data flow remains:

1. Identify the frontmost target process.
2. Query Palette and Accessibility for caret geometry.
3. Prefer valid Palette geometry unless it falls outside the focused Accessibility element.
4. Fall back to valid Accessibility geometry when Palette is unavailable or stale.
5. Convert the accepted global CG rectangle into AppKit coordinates and place the panel beside it.

## Alternatives Rejected

- Prefer Accessibility over Palette: this would discard the more direct InputMethodKit source and regress clients with incomplete Accessibility text support.
- Compare Palette and Accessibility rectangles by distance: the two APIs can legitimately report slightly different caret rectangles, so a distance threshold would introduce heuristic failures.
- Correct the panel position after placement: the placement layer cannot distinguish a valid caret rectangle from a semantically incorrect one and would only hide the source defect.

## Verification

- Add a source-contract regression test requiring the Palette line-height query to use index `0`.
- Require the range fallback to continue using `selection.location`.
- Run the focused Palette/caret tests and observe the new test fail before the production change.
- Apply the one-line production fix and rerun the focused tests.
- Run the complete Swift test suite and build the Palette product.

## Scope

This fix changes only the InputMethodKit query argument and its regression coverage. It does not alter UI layout, panel dimensions, shortcut behavior, Accessibility permissions, or application-specific behavior.
