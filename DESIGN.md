---
name: mood.
description: A native living visual moodboard for collecting what catches your eye and turning taste into usable context.
colors:
  accent-ink: "#000000"
  accent-paper: "#FFFFFF"
  canvas-light: "#F2EDE3"
  canvas-dark: "#1A1916"
  folio-light: "#FBF8F1"
  folio-dark: "#23211D"
  cover: "#13120F"
  preview-light: "#EAE5DA"
  preview-dark: "#2A2824"
  quote-ink: "#0E0D0B"
  quote-charcoal: "#181614"
  quote-graphite: "#23211D"
  quote-slate: "#2E2B27"
  card-ink: "#000000E6"
  card-stroke: "#0000001A"
  toast-ink: "#000000D1"
  study-paper-light: "#F2EDE3"
  study-paper-dark: "#1A1916"
  study-graphite-light: "#6A655B"
  study-graphite-dark: "#A29C90"
  study-pencil-light: "#8F897C"
  study-pencil-dark: "#7E786D"
  study-ink-light: "#2C43A3"
  study-ink-dark: "#93A6F2"
typography:
  study-display:
    fontFamily: "Geist Serif (bundled, OFL), Apple system serif fallback"
    fontSize: "40pt study subject and pattern pane, 32pt close-look title on macOS; 34pt and 28pt relative to Large Title and Title on iOS"
    fontWeight: 400
    lineHeight: 1.0
    letterSpacing: "-0.2pt"
  display:
    fontFamily: "Apple system serif (New York), Georgia, serif"
    fontSize: "28pt"
    fontWeight: 600
    lineHeight: 1.15
    letterSpacing: "normal"
  title:
    fontFamily: "Apple system serif (New York), Georgia, serif"
    fontSize: "Dynamic Type Title 2 (22pt default)"
    fontWeight: 700
    lineHeight: 1.2
    letterSpacing: "normal"
  card-title:
    fontFamily: "Apple system serif (New York), Georgia, serif"
    fontSize: "13pt baseline, scaled relative to Subheadline"
    fontWeight: 600
    lineHeight: 1.15
    letterSpacing: "normal"
  quote:
    fontFamily: "Apple system serif (New York), Georgia, serif"
    fontSize: "16pt baseline"
    fontWeight: 500
    lineHeight: 1.25
    letterSpacing: "normal"
  headline:
    fontFamily: "SF Pro, -apple-system, BlinkMacSystemFont, sans-serif"
    fontSize: "Dynamic Type Headline (17pt default)"
    fontWeight: 600
    lineHeight: 1.2
    letterSpacing: "normal"
  body:
    fontFamily: "SF Pro, -apple-system, BlinkMacSystemFont, sans-serif"
    fontSize: "Dynamic Type Body (17pt default)"
    fontWeight: 400
    lineHeight: 1.25
    letterSpacing: "normal"
  label:
    fontFamily: "SF Pro, -apple-system, BlinkMacSystemFont, sans-serif"
    fontSize: "Dynamic Type Subheadline (15pt default)"
    fontWeight: 500
    lineHeight: 1.2
    letterSpacing: "normal"
  caption:
    fontFamily: "SF Pro, -apple-system, BlinkMacSystemFont, sans-serif"
    fontSize: "Dynamic Type Caption (12pt default)"
    fontWeight: 400
    lineHeight: 1.2
    letterSpacing: "normal"
rounded:
  card-dense: "3pt"
  card-standard: "4pt"
  card-spacious: "5pt"
  compact-cutout: "4pt"
  stepped-cutout: "10pt"
  drop-target: "7pt"
  panel: "12pt"
  pill: "999pt"
spacing:
  card-mat-dense: "3pt"
  card-mat-compact: "5pt"
  card-mat-standard: "8pt"
  card-mat-spacious: "10pt"
  xs: "8pt"
  sm: "12pt"
  md: "16pt"
  lg: "18pt"
  xl: "22pt"
components:
  button-primary:
    backgroundColor: "{colors.accent-ink}"
    textColor: "{colors.accent-paper}"
    typography: "{typography.label}"
    height: "44pt minimum on iOS; platform default on macOS"
  collection-card:
    backgroundColor: "{colors.folio-light}"
    textColor: "{colors.card-ink}"
    typography: "{typography.card-title}"
    rounded: "{rounded.card-standard}"
    padding: "{spacing.card-mat-standard}"
  quote-preview:
    backgroundColor: "{colors.quote-ink}"
    textColor: "{colors.accent-paper}"
    typography: "{typography.quote}"
    rounded: "{rounded.card-standard}"
    padding: "{spacing.lg}"
  scope-tab-active:
    backgroundColor: "{colors.canvas-light}"
    textColor: "{colors.accent-ink}"
    typography: "{typography.label}"
    height: "44pt"
  search-field:
    backgroundColor: "{colors.folio-light}"
    textColor: "{colors.card-ink}"
    typography: "{typography.body}"
    rounded: "{rounded.pill}"
    height: "44pt minimum"
  toast:
    backgroundColor: "{colors.toast-ink}"
    textColor: "{colors.folio-light}"
    typography: "{typography.label}"
    rounded: "{rounded.pill}"
    padding: "0 {spacing.md}"
    height: "44pt minimum"
---

# Design System: mood.

## Overview

**Creative North Star: "The Working Sketchbook"**

mood. feels like a designer's sketchbook that happens to be native software: warm paper pages inside a black cover, with saved work pasted in as white prints and the thinking about it written around them. Quiet Apple chrome recedes around expressive imagery, quotations, provenance, and notes. The collection provides the color and surprise; the interface supplies calm structure, dependable capture, and an inviting rhythm for rediscovery. Every board, the moodboard and a study's board alike, is a page of the same book.

The visual language juxtaposes material, editorial cards with familiar SwiftUI navigation, search, forms, menus, sheets, context menus, and keyboard behavior. It is artful, human, and collectible without becoming ornamental. iOS, iPadOS, and macOS share the same moodboard character while preserving each platform's own layout and interaction conventions.

This system explicitly rejects a generic Pinterest clone, a utilitarian bookmark manager, and a web-style SaaS dashboard. It also rejects engagement-driven feeds, anonymous thumbnail grids, dense administrative chrome, and decorative interface effects that compete with saved items.

**Key Characteristics:**

- Collected content is the expressive layer; native controls are restrained and familiar.
- Neutral black, white, and gray surfaces support permanent white card mats in both appearances.
- Editorial serif type belongs to saved content and select identity moments; SF Pro carries the interface.
- Cards feel printed and collectible through shallow depth, fine borders, and stepped captions.
- Layout density adapts to device, accessibility settings, and user-controlled pinch zoom.
- Motion communicates hover, press, selection, loading, and layout state, and disappears under Reduce Motion.

**The Quiet Frame Rule.** Interface chrome must disappear into the task; personality comes from the collection, not invented controls.

## Colors

The palette is warm paper, white prints, and a black cover, with inverted ink for primary actions. Every neutral is warm, the same temperature as the paper; collected imagery supplies every chromatic moment.

### Primary

- **Ink** (`{colors.accent-ink}`): the light-appearance tint for current scope, primary actions, and focus—not decoration. Primary buttons are black with white labels.
- **Paper** (`{colors.accent-paper}`): the dark-appearance interactive equivalent. Primary buttons, tints, and drop-target ink invert to white on the black canvas.

### Secondary

- **Selection Ink** (`{colors.accent-ink}`): a black keyline on the permanent white card mat, so selection stays visible in both appearances.

### Tertiary

- **Quote Ink**, **Charcoal**, **Graphite**, and **Slate** (`{colors.quote-ink}`, `{colors.quote-charcoal}`, `{colors.quote-graphite}`, `{colors.quote-slate}`): deterministic warm-black backgrounds for text-only X references. They make missing imagery feel intentional, never like an error state.

### Neutral

- **Paper** (`{colors.canvas-light}` / `{colors.canvas-dark}`): the page behind every board, with a faint tiled grain, on both platforms.
- **Sheet** (`{colors.folio-light}` / `{colors.folio-dark}`): a lighter slip laid on the page, such as a close look, a detail surface, or a move's index card. The collected card mat itself stays pure white in both appearances to preserve the physical-print metaphor.
- **Cover** (`{colors.cover}`): the Mac window's frame and sidebar in both appearances, the sketchbook's binding around the page.
- **Wash** (`{colors.preview-light}` / `{colors.preview-dark}`): quiet image-loading and web-reference backing on every platform.
- **Card Ink**, **Hairline Ink**, and **Toast Ink** (`{colors.card-ink}`, `{colors.card-stroke}`, `{colors.toast-ink}`): permanent ink for the white card mat, its half-point border, and transient confirmation capsules.

**The Ink Rule.** Black (light) and white (dark) identify interaction and current state. They must never become a decorative wash across inactive surfaces.

**The Content Color Rule.** Chromatic color belongs to captured imagery. Application chrome and text-only quote fills stay warm black, white, paper, or warm gray. The one exception is the study board's ink (see "Study Board: Pencil and Ink"): a single blue-black for the person's own judgments, never for chrome or decoration.

## Typography

**Display Font:** Apple system serif / New York (with Georgia fallback)
**Body Font:** SF Pro (with Apple system fallbacks)
**Label/Mono Font:** SF Pro, using monospaced digits only for compact counts

**Character:** The pairing is editorial without feeling themed. System serif restores the personality of a printed caption or collected quotation; SF Pro preserves instant native familiarity for every task and control.

### Hierarchy

- **Display** (`{typography.display}`): macOS detail titles and the largest editorial reading moments. Keep it content-facing and selectable.
- **Title** (`{typography.title}`): iOS detail titles and high-value editorial headings that need Dynamic Type.
- **Card Title** (`{typography.card-title}`): the stepped white caption inset; its baseline scales with density and the user's text size.
- **Quote** (`{typography.quote}`): text-only X previews and image-less editorial previews, with short line lengths and restrained line limits.
- **Headline** (`{typography.headline}`): native screen identity, toolbar titles, and compact section emphasis.
- **Body** (`{typography.body}`): notes, descriptions, and form content; longer reading stays near 65–75 characters per line when the layout permits.
- **Label** (`{typography.label}`): scope tabs, actions, and transient confirmation messages.
- **Caption** (`{typography.caption}`): provenance, source, project counts, dates, and tertiary metadata.

**The Serif Lives with Content Rule.** Serif is reserved for saved titles, quotations, editorial previews, the mood. wordmark on the Mac sidebar (Geist Serif, 28pt), and each page's title. Buttons, fields, navigation labels, and data remain SF Pro.

**The Dynamic Type Rule.** iOS typography must use semantic styles or `ScaledMetric`; accessibility sizes collapse the canvas to one column and must never be defeated with fixed text.

## Elevation

mood. uses a hybrid of tonal layering and shallow ambient shadow. The gallery canvas, folio panels, and preview grounds establish most depth through color. Cards receive just enough soft shadow and a half-point dark hairline to read as prints resting on a surface; elevation increases only for hover, drag preview, selection context, or transient feedback.

### Shadow Vocabulary

- **iOS Card Rest** (`0 1pt 1–2pt rgba(0,0,0,0.06–0.09)`): density-aware separation for collected cards.
- **macOS Card Rest** (`0 2pt 4pt rgba(0,0,0,0.075)` light; `0 2pt 4pt rgba(0,0,0,0.24)` dark): ambient paper lift at rest.
- **macOS Card Hover** (`0 5pt 8pt rgba(0,0,0,0.14)` light; `0 5pt 8pt rgba(0,0,0,0.36)` dark): paired with a 2pt upward offset and subtle image scale.
- **Transient Capsule** (`0 5pt 12pt rgba(0,0,0,0.15–0.16)`): toasts only.

**The Print, Not Plastic Rule.** Shadows stay soft, low-opacity, and close to the surface. If a card looks glossy, floating, or web-dashboard-like, the elevation is too strong.

## Components

### Buttons

- **Shape:** use native SwiftUI button shapes and control sizes. Touch targets are at least 44×44pt on iOS; macOS controls preserve system sizing and keyboard focus.
- **Primary:** `.borderedProminent` with inverted ink (black on light, white on dark) and a label in the opposite ink (`inkProminentButtonStyle()`), used for the single clear action in empty states, save flows, and a close look's verdict. The system style alone keeps its label white, which vanishes on Dark Mode's white.
- **Hover / Focus:** allow platform-native hover, focus ring, pressed, disabled, loading, destructive, and keyboard states. Never approximate them with custom web-style chrome.
- **Secondary / Ghost:** plain, borderless, menu, toolbar, and standard bordered styles remain native. Destructive actions use the semantic destructive role.

### Chips

- **Style:** project and scope selectors are text-first native controls with a 7pt project-color dot where relevant. Counts use tertiary caption text and monospaced digits.
- **State:** on iOS the active scope gains semibold weight and the same short hand-drawn ink underline as the study board's current filter, sliding between scopes; counts are graphite. On macOS the sidebar row is selected natively.
- **Glass segments:** switches that sit on the canvas (Moodboard or Study board) share one floating glass capsule: the current segment is a pill concentric with the capsule that slides between segments. 34pt tall on macOS, 44pt on iOS.
- **Study board filters:** the verdict filters with their counts are written on the page, not in a capsule: the current one is semibold with a short hand-drawn ink underline that slides between them; counts are graphite. 44pt targets on iOS.

### Cards / Containers

- **Corner Style:** gently squared continuous corners respond to density: 5pt spacious, 4pt standard, and 3pt dense. The white mat uses 10/8/5/3pt insets on iOS and 10/8/6/5/4/3pt on macOS.
- **Background:** every collectible card uses permanent white Folio Paper around the preview, including in Dark Mode. Preview content adapts independently.
- **Shadow Strategy:** use the Print vocabulary above and a 0.5pt Card Stroke. Selection is an outline, not a heavier shadow.
- **Internal Padding:** caption padding contracts with density from roughly 6pt to 2.5pt. The caption is the mat's white, so on the left and below its text margin runs on to the card edge; on macOS the trailing padding adds the mat inset so the text sits as far from the image as from the edge. iOS captions add 2pt of trailing breathing room so the title never crowds the cutout edge.
- **Layout:** iOS uses 16pt horizontal canvas padding, 8–12pt horizontal card gaps, and 10–18pt vertical gaps. macOS uses 20pt canvas padding and 16pt gaps. A study board spaces its cards wider (24pt on macOS, at least 22pt on iOS) so the ink loops around kept cards never run into each other. Columns start at the same top edge; different content heights create the rhythm naturally.

### Inputs / Fields

- **Style:** use native searchable fields, `Form`, `TextField`, `Picker`, and grouped form presentation. On iOS, search stays visually prominent but platform-owned. On macOS, search appears when invoked rather than occupying a permanent toolbar.
- **Focus:** use the operating system focus ring, keyboard focus order, submit labels, and semantic tint.
- **Error / Disabled:** errors use semantic red and explanatory text; saving disables conflicting actions and exposes a native progress state.

### Navigation

- **iOS / iPadOS:** `NavigationStack`, inline mood. title, system search drawer, horizontal scope bar, toolbar menu, system sheets, context menus, swipe actions, alerts, and edge-swipe back.
- **macOS:** a collapsible sidebar on the cover lists All inspiration, General, and projects; the page fills the rest of the window, and switching spaces crossfades to the new page, opened at its top. Find (`⌘F`) and Switch Project (`⌘K`) invoke search and navigation. Selecting an item opens its close look over the dimmed page, large enough to look properly: the image on the left, details and actions in a column beside it (stacked when the window is narrow). Item editing starts from there. Menus, context menus, drag and drop, and keyboard shortcuts remain native. There is no toolbar; search and the board switch float as glass capsules over the page, and the page softens as it scrolls under them.
- **Page header:** every board opens with the same line on the paper, with no panel: the page's title in Geist Serif (the space, project, or study subject) with a line beside it (a study's brief), over a pencil rule. Clicking a project's or study's title edits it. An empty page writes a short note under the rule, on its left edge, with what to do next.
- **Study board:** the page header carries the verdict filters at its right edge, on the title's baseline; when the line can't hold both, the filters drop below. The agent is not in the header. On macOS it is a glass capsule in the canvas chrome, beside the board switch, that says what it is doing or will do next ("Find more", "Codex · 3 found", "Codex · 5 new"); clicking it opens a card with one heading, the nudge as a soft well, one full-width primary action, and quiet secondary actions. On iOS a sparkles toolbar button opens the same card to copy a prompt.
- **Iconography:** SF Symbols only, using semantic weights and platform alignment.

### Stepped Caption Cutout

The signature collected-card caption grows from the preview's lower-left corner as white paper. At low density the source sits on a rounded shelf above the title, each as wide as its own text, so the step follows the words and never cuts across a line or lets a glyph run onto the image; Mac and iOS share the one caption. At high density it collapses to one compact rounded edge. A title that is only the image's file name ("IMG_2041.jpeg", a browser's "name (1200×800)") is left off, so an image-only save carries just its source. The cutout must fully mask the image beneath it, including the lower-left inner corner, and its right edge must always retain visible breathing room after the last glyph.

### Image-less Reference Preview

Text-only X captures become serif quotation cards chosen deterministically from Quote Ink, Charcoal, Graphite, and Slate. Image-less web captures become quiet editorial title/excerpt/domain cards on Preview Ground. Both are first-class collected objects, never placeholders that apologize for missing imagery.

### Motion and Density

Pinch zoom interpolates the whole canvas continuously between adjacent column counts, then settles with a short interactive spring. On the study board, a find that arrives while the board is open develops into place: its image resolves out of monochrome grain in sixteen visible steps over about 1.7s, coarse shape and color first and detail last, like a diffusion sampler; pencil-hatched tiles at the end of the board, breathing slowly, hold the slots a running agent is still filling. A new pattern's pencil frame is sketched in over 0.9s, and a verdict given while its card is in view is drawn in ink: the loop in 0.5s, the strike in 0.22s. The grain stays gray so color still belongs to the imagery, and Reduce Motion replaces all of it with the usual fade or an immediate mark. Most state changes use 160–220ms ease-out timing; loading images crossfade in 200ms. Pressed cards scale only to 0.985, while macOS hover lifts by 2pt and scales imagery to 1.018. Reduce Motion removes the spring, lift, and scale while preserving state legibility through opacity or immediate layout changes.

**The Natural Shelf Rule.** Every column begins at the same top edge. Never add decorative per-column offsets; varying card heights already create the collected rhythm.

**The Native First Rule.** Standard Apple affordances remain standard. Brand expression belongs in the card, content, tint, and quiet editorial type—not in replacements for navigation, forms, menus, alerts, or system gestures.

## Study Board: Pencil and Ink

Every board is a page of the sketchbook, but the study board is where a direction is worked out, so it is the page with two hands on it. The agent drafts in pencil and writes in graphite; the person decides in ink. Saved work stays crisp and is never drawn on: a kept find is circled, not marked up.

- **Paper** (`{colors.study-paper-light}` / `{colors.study-paper-dark}`): the same page as every board. The white card mat stays white on it.
- **Graphite** (`{colors.study-graphite-light}` / `{colors.study-graphite-dark}`): the agent's words, such as why a find is here, how much a pattern rests on ("Seen in 3 of your saves"), and the lens a move is seen through (after an eyeglasses glyph, under the move, never as an uppercase label over it). At least 4.5:1 on paper.
- **Pencil** (`{colors.study-pencil-light}` / `{colors.study-pencil-dark}`): the agent's marks, such as a proposed pattern's frame, the hatching of slots still being filled, and the rule under the header. Strokes only, never text.
- **Ink** (`{colors.study-ink-light}` / `{colors.study-ink-dark}`): everything the person decides, such as the loop around a kept card, the stroke through a rejected one, their reasons (serif italic), the current filter's underline, a chosen lens, and a confirmed pattern's frame.
- **Display type:** Geist Serif (`{typography.study-display}`), bundled under the SIL Open Font License and registered at first use, for the study subject, the close-look title, and a pattern given a whole pane. Its hairlines are cut for headlines, so it never goes below 28pt; pattern cards and reasons stay in the system serif.
- **Marks** are drawn from each entry's ID, so a card's loop looks the same every time. The loop runs a rounded box about 7pt outside the card and a little past where it started; the strike crosses the whole card; the pattern frame is four quick lines that cross at the corners. Strokes are 1.8–2.2pt for ink, 1–1.1pt for pencil, with round caps.
- **Margin notes** sit 12pt under a find, past the loop: the person's reason in ink once judged, or two lines of the agent's rationale in graphite while it waits. They show at four columns or fewer on macOS and two or fewer on iOS.
- **Lenses:** the close look offers Dieter Rams' principles (As little design as possible, Understandable, Unobtrusive, Honest, Useful, Thorough to the detail, Long-lasting) as chips that add their words to the reason; a chosen one is circled in ink. They wrap on macOS and scroll in one row on iOS.

**The Two Hands Rule.** Pencil means the agent proposed it and nothing is decided; ink means the person decided it. Never draw in ink for the agent, never use pencil for the person, and never draw on a saved image itself.

**The Marks Stay Off Controls Rule.** The current filter's (and on iOS, the current scope's) underline and a chosen lens are the only marks on controls. Buttons, menus, sheets, and the canvas chrome stay native.

## Do's and Don'ts

### Do:

- **Do** let imagery, quotations, source, author, and notes carry the expressive weight.
- **Do** use inverted ink (black in Light Mode, white in Dark Mode) only for primary action, current selection chrome, and focus.
- **Do** preserve the white card mat, half-point hairline, density-aware insets, and complete lower-left cutout mask.
- **Do** start all columns at the same top edge and let real card heights create variation.
- **Do** use SF Pro for controls and system serif for saved-content moments.
- **Do** use native Apple navigation, search, forms, menus, sheets, context menus, drag and drop, keyboard behavior, and SF Symbols.
- **Do** let the macOS canvas occupy the window: project identity is a quiet editorial heading, and search, switching, and editing appear only when invoked.
- **Do** support Dynamic Type, VoiceOver, Reduce Motion, sufficient contrast, Dark Mode, 44×44pt iOS targets, and macOS keyboard navigation.
- **Do** preserve provenance so future human and agent readers can understand why a reference mattered.

### Don't:

- **Don't** make mood. resemble a generic Pinterest clone; no engagement-driven feeds or social-feed mechanics.
- **Don't** make mood. resemble a utilitarian bookmark manager; anonymous thumbnail grids and bare links are prohibited.
- **Don't** make mood. resemble a web-style SaaS dashboard; dense administrative chrome, web-shaped controls, and dashboard ornament are prohibited.
- **Don't** add decorative interface effects that compete with saved items.
- **Don't** give the macOS library a permanent sidebar, or treat Projects as folders in file-manager chrome.
- **Don't** use artificial top staggering, masonry offsets, or rotation to manufacture personality in the resting library.
- **Don't** introduce chromatic chrome; color in the interface belongs to captured imagery and user-chosen project dots.
- **Don't** put display serif type in buttons, fields, navigation labels, or data.
- **Don't** invent custom switches, pickers, alerts, back gestures, scrollbars, or modals when SwiftUI already provides the expected control.
- **Don't** use heavy, sharp, glossy shadows; if a card looks like floating plastic instead of paper, it is wrong.
- **Don't** hide provenance, crop a caption against its right edge, or allow preview imagery to leak through any part of the white cutout.
