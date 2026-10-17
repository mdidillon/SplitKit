# SplitKit visual design

This file is the **single source of truth for SplitKit's visual design**: tokens and their defaults, the `.glass` and `.plain` styles, system appearance and accessibility behaviour, header anatomy, spacing and states, typography, view reuse rules and the Larevo reference. `Docs/Specification.md` defines behaviour and API contracts and refers here for anything visual; it never redefines a design element. If the two seem to conflict on a visual question, this file wins and the spec gets fixed.

**Status:** draft, 17 Oct 2026. Values marked **[check]** are provisional defaults that need Marc's visual check (listed in §11). Everything else follows directly from native macOS 26 behaviour and is not expected to change.

## 1. Principles

1. **Native first.** Standard SwiftUI controls (`Button`, `Menu`, `Toggle`), system materials, Liquid Glass and semantic colours. No custom component library, no custom fonts, no hand-drawn controls.
2. **Glass is for chrome, never for content.** Liquid Glass sits on the functional layer (header controls, drop overlays); content views stay opaque and undistorted. Glass is used sparingly and never stacked on glass.
3. **One definition per value.** Every number, colour and material comes from `SplitKitTokens` (§2) or the style constants (§3). Views never contain literal numbers or colours (§9).
4. **System behaviour does the adapting.** Light/dark, accent colour, Increase Contrast, Reduce Transparency and Reduce Motion are honoured through system behaviour, with no custom fallback code (§5).

## 2. Tokens (`SplitKitTokens`)

Public, environment-injected with `.splitKitTokens(_:)`, read by every style. The set is kept small on purpose; adding, removing or renaming a token is an API change that needs Marc's approval and a change to this table. Each style ships its own defaults (`SplitKitTokens.glass`, `SplitKitTokens.plain`); a host may override any token.

| Token | Type | Purpose | `.glass` default | `.plain` default |
|---|---|---|---|---|
| `metrics.headerHeight` | `CGFloat` | Height of the pane header row | 28 pt | 28 pt |
| `metrics.dividerThickness` | `CGFloat` | Visible thickness of the divider line | 1 pt | 1 pt |
| `metrics.dividerHitWidth` | `CGFloat` | Width of the divider's pointer and drag area, centred on the divider (≥ `dividerThickness`) | 8 pt | 8 pt |
| `metrics.cornerRadius` | `CGFloat` | Corner radius of the pane card (content clip and drop overlay) | 10 pt **[check]** | 0 pt **[check]** |
| `metrics.contentPadding` | `CGFloat` | Inset of each pane card inside its layout cell; the gap between cards is twice this | 4 pt **[check]** | 0 pt |
| `glass.variant` | `.regular` / `.clear` | Liquid Glass variant for chrome (maps to `Glass.regular` / `Glass.clear`) | `.regular` | not used |
| `glass.tint` | `Color?` | Optional tint on chrome glass (`Glass.tint(_:)`) | `nil` | not used |
| `colors.activeIndicator` | `Color` | Marks the active pane (§7) | `Color.accentColor` | `Color.accentColor` |
| `colors.dropHighlight` | `Color` | Stroke and tint of drop targets (§7) | `Color.accentColor` | `Color.accentColor` |

`Color.accentColor` follows the system accent colour and a host's `.tint(_:)`.

## 3. Style constants (internal)

Values every style needs but that are not public tokens. They live in **one internal type in `SplitKit/Sources/SplitKit/Styles/`** (e.g. `SplitKitStyleConstants`) and nowhere else. Changing one is a change to this file.

| Constant | Value | Used for |
|---|---|---|
| Header horizontal padding | 6 pt **[check]** | Leading/trailing inset of the header row |
| Header item spacing | 4 pt **[check]** | Space between header elements; also the `GlassEffectContainer(spacing:)` value |
| Header control size | `.controlSize(.small)` | All header buttons, menus and toggles |
| Header symbol scale | `.imageScale(.small)` | All header SF Symbols |
| Header title minimum width | 64 pt **[check]** | Narrowest the title (middle-truncated) gets before `.high` toolbar items collapse into the overflow; below it the title is hidden (spec §7.4) |
| Active indicator thickness | 2 pt **[check]** | Accent line along the top edge of the active pane's header (§7) |
| Drop overlay fill opacity | 0.18 **[check]** | `colors.dropHighlight` fill over the target zone |
| Drop overlay stroke | 2 pt **[check]** | `colors.dropHighlight` stroke around the target zone |
| Inactive chrome opacity | none: inactive uses `.secondary` foreground, not opacity | Inactive header |
| Dragged-source opacity | 0.5 **[check]** | Header and content of the pane being dragged |
| Empty-state symbol size | 28 pt **[check]** | Symbol in the empty pane and empty window |
| Empty-state spacing | 8 pt **[check]** | Vertical spacing in empty and placeholder views |
| Animations | `.smooth` (system default) | State changes (active, drop target, pending close); no custom curves or durations |
| Header control labels | "Focus Pane", "Close Pane" **[check]** | VoiceOver label and tooltip of the focus toggle and close button (§5); the pending-close value is "Closing" |

The same internal type also holds the §4.3 semantic colours, the §6/§7 symbols and the §8 text styles, so no view spells them out.

## 4. Styles

Three style protocols (`PaneHeaderStyle`, `PaneDividerStyle`, `EmptyPaneStyle`, applied with `.paneHeaderStyle(_:)`, `.paneDividerStyle(_:)`, `.emptyPaneStyle(_:)`) work like `ButtonStyle`. Milestone 1 ships two styles, each a set of these three plus its token defaults. `.compact` is deferred until after Phase 3.

### 4.1 `.glass` (default)

| Element | Rendering |
|---|---|
| Window background | Standard window background; no custom window material **[check]** |
| Pane card | Content clipped to `RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)`, opaque `.background(.background)`, inset by `metrics.contentPadding` |
| Header row | Sits at the top of the card, no background of its own; a hairline of thickness `metrics.dividerThickness` in `Color(nsColor: .separatorColor)` below it |
| Header controls | Title menu, toolbar items, overflow, focus and close use `.buttonStyle(.borderless)` (menus `.menuStyle(.borderlessButton)`) plus `.glassEffect(_:in: .capsule)` with the glass built from `glass.variant` and `glass.tint` and made `.interactive()`, all inside **one** `GlassEffectContainer(spacing:)` per header **[check]** |
| Divider | The gap between cards (`2 × contentPadding`); a `dividerThickness` line in `Color(nsColor: .separatorColor)` appears on hover and while dragging, accent-coloured (`colors.activeIndicator`) while dragging **[check]** |
| Drop overlay | `Material.thin` (`.thinMaterial`) in the card shape over the target zone, with the `dropHighlight` fill and stroke from §3 |
| Empty pane / empty window | Centred symbol + title + **Add Content** button in `.buttonStyle(.glassProminent)` **[check]** |

### 4.2 `.plain`

| Element | Rendering |
|---|---|
| Window background | Standard window background |
| Pane card | Opaque `.background(.background)`, square corners (`cornerRadius` 0), flush (`contentPadding` 0) |
| Header row | Opaque `Color(nsColor: .windowBackgroundColor)` with a hairline of thickness `metrics.dividerThickness` in `Color(nsColor: .separatorColor)` below |
| Header controls | `.buttonStyle(.borderless)`; menus `.menuStyle(.borderlessButton)`; no glass |
| Divider | Always-visible `dividerThickness` line in `Color(nsColor: .separatorColor)`, accent-coloured (`colors.activeIndicator`) while dragging |
| Drop overlay | No material: `dropHighlight` fill and stroke from §3 only |
| Empty pane / empty window | Centred symbol + title + **Add Content** button in `.buttonStyle(.borderedProminent)` |

### 4.3 Semantic colours (both styles)

| Role | Colour |
|---|---|
| Primary text and symbols | `.primary` (hierarchical) |
| Secondary text, inactive chrome, hints | `.secondary` |
| Separators and divider line | `Color(nsColor: .separatorColor)` |
| Accent (active indicator, drop target, dragging divider) | tokens `colors.activeIndicator`, `colors.dropHighlight` (default `Color.accentColor`) |
| Destructive emphasis | none in chrome; confirmations use the system alert styling |

No hard-coded RGB values anywhere in SplitKit.

## 5. System appearance and accessibility

| Setting | Behaviour | Our code |
|---|---|---|
| Light / dark | Semantic colours and glass adapt | nothing |
| Accent colour | `Color.accentColor` / host `.tint` | nothing |
| Increase Contrast | The system raises glass and separator contrast | nothing; verified in the entry example |
| Reduce Transparency | The system renders glass and materials opaque | nothing; verified in the entry example |
| Reduce Motion | System animations and glass morphing reduce themselves; we only use `.smooth` | nothing |
| VoiceOver | Every header control has a label (`title`); the active pane carries `.isSelected`; a pending close exposes the value "Closing"; the focus toggle exposes the value "On"/"Off"; drop targets are not the only way to move (menu commands exist) | labels and traits only |
| Keyboard | Standard focus rings on header controls; no custom focus drawing | nothing |

**No custom fallback code:** styles do not branch on `accessibilityReduceTransparency`, `colorSchemeContrast` or `accessibilityReduceMotion`. If the entry verification shows a setting is not honoured, that is a deviation report, not a silent workaround.

**Phase 2 entry verification (the example screen):** one window showing, side by side, `glassEffect(_:in:)` with `Glass.regular`, `Glass.clear` and a tinted glass, a `GlassEffectContainer` of pill buttons, `.buttonStyle(.glass)` and `.glassProminent`, a `.thinMaterial` overlay over a busy image, semantic text and separator colours, and the live values of `colorScheme`, `colorSchemeContrast`, `accessibilityReduceTransparency` and `accessibilityReduceMotion`. It is checked in light and dark, with Increase Contrast, Reduce Transparency and VoiceOver on, and the observed behaviour is recorded. Any API or behaviour that differs from this file gets a deviation report before chrome is built.

## 6. Header anatomy

The element order and behaviour are in spec §7.1 and the layout and overflow rules in spec §7.4. Visually:

| Element | Visual |
|---|---|
| Row | `metrics.headerHeight`, header padding and item spacing from §3, vertically centred |
| Drag handle | SF Symbol `line.3.horizontal`, `.secondary` **[check]** |
| Content icon | The type's `systemImage`, `.secondary` when inactive, `.primary` when active |
| Title + ▾ | Title text (§8) followed by `chevron.down` at the header symbol scale; the whole pill is the menu |
| Toolbar items | Icon-only when a `systemImage` exists (title as tooltip and label), otherwise the title text |
| Overflow | `ellipsis`, shown only when an item does not fit; its menu lists the collapsed items in declaration order (`.callout`) and never holds focus or close |
| Title and toolbar region | Title pill and toolbar items share the flexible space between the icon and the focus toggle; items are right-aligned. Order of giving way as the row narrows: `.low` items, `.normal` items (later declared first), title truncation (middle) down to the title minimum width (§3), `.high` items, then the title itself |
| Focus toggle | `arrow.up.left.and.arrow.down.right` to enter, `arrow.down.right.and.arrow.up.left` to exit focus mode |
| Close | `xmark` |

## 7. States

| State | `.glass` | `.plain` |
|---|---|---|
| **Active** | `activeIndicator` line (§3) along the top of the header; icon and title `.primary` | same |
| **Inactive** | No indicator; icon and title `.secondary`; controls keep their normal look | same |
| **Hover** | System hover feedback of the button styles only; divider line appears (§4.1) | System hover feedback; divider unchanged |
| **Drop target** | Edge zone = that half of the card; centre = the whole card; overlay per §4.1; animated with `.smooth` | Same zones; overlay per §4.2 |
| **Dragged source** | Header and content at the dragged-source opacity (§3) | same |
| **Pending close** | The close button is replaced by a `ProgressView().controlSize(.small)`; the other header controls are disabled; content is not dimmed (it may show a sheet) | same |
| **Empty pane** | Header shows "Add Content" as the title (spec §7.1); body shows `plus.rectangle.on.rectangle` at the empty-state size, `.secondary`, a title and the Add Content button (§4) | same with §4.2 button |
| **Empty window** (no panes) | Same composition as the empty pane, centred in the window; title "No Content" **[check]** | same |
| **Unavailable placeholder** | The type's symbol (or `questionmark.square.dashed` when unknown), the message from spec §8 in `.secondary`, **Restore** (`.glass`) and **Close** buttons | same with `.bordered` buttons |
| **Focus mode** | The focused card fills the window; no extra decoration besides the toggled focus symbol | same |

The **Drop target** overlay is rendered by the P3 drag chrome (drag targets), reading the same tokens (§3, §4); the header configuration carries `isDropTarget` for it.

## 8. Typography

System font only (SF Pro via SwiftUI text styles); no custom fonts, no fixed point sizes in views.

| Use | Style |
|---|---|
| Header title | `.callout` (12 pt on macOS), `.medium` weight in every state (colour shows state, so the text never shifts) |
| Toolbar item labels, overflow menu | `.callout` |
| Empty state / placeholder title | `.title3` (15 pt) **[check]** |
| Empty state / placeholder body and hints | `.callout`, `.secondary` |
| Numbers that change (e.g. the counter dummy) | `.monospacedDigit()` |

Title truncation follows spec §7.4.

## 9. Reuse rules for views

- All chrome lives in `SplitKit/Sources/SplitKit/Chrome/`; styles, tokens and the style constants live in `SplitKit/Sources/SplitKit/Styles/`. `SplitKitModel`, `SplitKitContent` and the content products contain no chrome styling.
- **One shared component per concept:** pane header, header control, divider, drop overlay, empty state, unavailable placeholder. Every screen composes these; nothing is re-implemented, even slightly differently. Search with `rg` before adding a view.
- **Values only from tokens** (§2) or the style constants (§3). No literal numbers, colours, fonts or materials in views.
- Host customisation goes only through the style protocols and tokens; hosts never reach into chrome views.
- Content draws nothing into the chrome; toolbar items are laid out by SplitKit (spec §7.4).
- A new token, style constant or state look is first added to this file, then implemented once.

## 10. Larevo reference

`Docs/larevo-glass-reference.png` is a **reference, not a clone**. It shows the mood to aim for: dark translucent panels, soft gradient tints, rounded cards, compact pill chips (a header row with icon, title and ▾), thin dividers and a quiet, dense layout. Use it to tune the **[check]** values above. Do not copy its colours, gradients, fonts or brand elements; tints come only from glass and `glass.tint`.

## 11. Values that need Marc's visual check

Checked on the Phase 2 example screen and the first chrome build, in light and dark:

1. `metrics.cornerRadius` (10 pt `.glass`, 0 pt `.plain`)
2. `metrics.contentPadding` (4 pt `.glass`)
3. Header padding 6 pt and item spacing 4 pt
4. Active indicator: 2 pt accent line on top of the header
5. Drop overlay: 0.18 fill, 2 pt stroke, `.thinMaterial` in `.glass`
6. Dragged-source opacity 0.5
7. `.glass` divider: line only on hover and drag
8. `.glass` window background: standard, no custom window material
9. Empty state: 28 pt symbol, `.title3` title, 8 pt spacing, `.glassProminent` Add button
10. Drag handle symbol `line.3.horizontal`
11. Header control labels "Focus Pane" and "Close Pane"
12. `.glass` header controls: borderless buttons with token-driven interactive `glassEffect` capsules in one `GlassEffectContainer`
13. Empty window title copy "No Content"
14. Header title minimum width 64 pt
