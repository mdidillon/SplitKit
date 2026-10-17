# Glass and accessibility manual checklist: Phase 2 entry verification

For the Phase 2 entry gate (spec §11 P2) and `Docs/Design.md` §5. The system must adapt glass, materials and separators by itself; the example screen contains **no fallback code** for any setting. If a setting is not honoured, that is a deviation report, not a workaround.

## Setup

Open `SplitKitTestApp/SplitKitTestApp.xcodeproj` in Xcode 27.1 and run the `SplitKitTestApp` scheme (or run the built app). Then choose **Window ▸ Glass & Accessibility Check** (⌥⌘G). The existing placeholder window can stay open or be closed.

The window shows, top to bottom, over a busy gradient background:

1. **Live environment values:** `colorScheme`, `colorSchemeContrast`, `accessibilityReduceTransparency`, `accessibilityReduceMotion`.
2. **glassEffect(_:in:):** `Glass.regular`, `Glass.clear`, `Glass.regular.tint(.orange)`, `Glass.regular.interactive()`.
3. **GlassEffectContainer(spacing: 4):** pill buttons (icon only); the button below adds two pills with a `.smooth` morph.
4. **Button styles:** `.glass`, `.glassProminent`, `.glass` at `.controlSize(.small)`.
5. **.thinMaterial** overlay over a busy shapes-and-gradient background.
6. **Semantic text** (`.primary`, `.secondary`) and a 1 pt line in `Color(nsColor: .separatorColor)`.

Switch each setting below (System Settings is separate from the app; the window updates live), look at every element, and record the result. Reset all settings at the end.

## Checks

| # | Setting and System Settings path | Expected (system adapts, nothing custom) | Result (PASS/FAIL + notes) |
|---|---|---|---|
| 1 | **Light:** Appearance ▸ Appearance ▸ Light | Environment shows `colorScheme: light`. Glass samples are legible and tinted by what is behind them; `Glass.clear` is more transparent than `.regular`; the tinted one is visibly orange; primary text is dark, secondary text is lighter; the separator line is visible but subtle; `.thinMaterial` blurs the backdrop. | |
| 2 | **Dark:** Appearance ▸ Appearance ▸ Dark | `colorScheme: dark`. Same elements adapt: text flips to light, glass turns dark, separator remains visible, nothing is unreadable. | |
| 3 | **Increase Contrast:** Accessibility ▸ Display ▸ Increase contrast (test in light and dark) | `colorSchemeContrast: increased`. Separator line and glass edges become stronger; text stays readable; the buttons get more defined borders. | |
| 4 | **Reduce Transparency:** Accessibility ▸ Display ▸ Reduce transparency (test in light and dark) | `accessibilityReduceTransparency: true`. Glass samples and `.thinMaterial` render opaque or nearly so (the busy background no longer shines through); all text stays readable; buttons still look like buttons. | |
| 5 | **Reduce Motion:** Accessibility ▸ Display ▸ Reduce motion | `accessibilityReduceMotion: true`. Click **Expand pills (morphing)** several times: the pills change without the fluid glass morph (or with a much reduced one); hover and press feedback on the interactive glass sample is reduced. Compare with Reduce Motion off. | |
| 6 | **VoiceOver:** toggle with ⌘F5 (or Accessibility ▸ VoiceOver). Move through the window with VO+→ | Every control announces a label: the pills ("Title", "Overflow", "Focus", "Close"), the three button-style buttons, "Expand pills with morphing animation", the four glass samples ("Glass sample: …"), the material block, and the environment values as one element. The background gradient is skipped. Buttons are announced as buttons. | |
| 7 | **Keyboard:** Accessibility ▸ Keyboard ▸ Full Keyboard Access, then Tab through the window | Standard focus rings on the buttons; nothing custom drawn. | |
| 8 | **Accent colour:** Appearance ▸ Accent colour (try Graphite and Pink) | `.glassProminent` and any accent-dependent fills follow the accent colour. | |

For each failing row, write down exactly what is not honoured; do not add code to compensate.

## Design.md §11 [check] values that can be judged on this screen

Only values that depend on glass, materials or the semantic colours are visible here; the rest need the first chrome build.

| Value (Design.md §11) | Judge on this screen | Result |
|---|---|---|
| 5. Drop overlay: `.thinMaterial` in `.glass` (the fill 0.18 and stroke 2 pt are not on this screen) | Is `.thinMaterial` over a busy background the right strength in light and dark? | |
| 8. `.glass` window background: standard, no custom window material | Does the standard window background look right behind the glass samples and pills? | |
| 9. Empty state: `.glassProminent` Add button (the 28 pt symbol, `.title3` title and 8 pt spacing are not on this screen) | Does `.glassProminent` look right as the primary action, in light and dark and with different accent colours? | |
| Header controls (§4.1): `.buttonStyle(.glass)` pills in one `GlassEffectContainer(spacing: 4)` | Does the 4 pt spacing read as one group? Is the small `.glass` button readable at header size? | |

Not judgeable here (first chrome build): 1 corner radius, 2 content padding, 3 header padding and item spacing, 4 active indicator, 6 dragged-source opacity, 7 divider on hover and drag, 10 drag handle symbol.

## Sign-off

- Tester / date:
- macOS version and Xcode version:
- Display (built-in / external):
- Overall: PASS / FAIL
- Deviations to report (API shape or behaviour differing from Design.md §5):
