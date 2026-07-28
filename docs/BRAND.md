# iTelAS visual identity

iTelAS is designed as a precision terminal instrument for IBM i professionals. The interface should feel engineered, calm, and durable—not like a generic AI dashboard, a retro terminal skin, or a copy of another terminal product.

## Mark

The iTelAS mark is an original construction made from two routed data paths on a measured grid:

- The white path represents the stable system of record.
- The terminal-green path represents an active 5250 session and operator cursor.
- The blue origin node represents an intentional, inspectable action.
- The white terminal node represents a result returned to the professional.
- The chamfered instrument plate distinguishes the product from soft, template-like app iconography.

The mark is drawn as SwiftUI vectors in `BrandComponents.swift`. The macOS icon uses the same geometry and is generated at every required 1x and 2x Retina size by `scripts/render-brand-assets.swift`, then compiled into the app's `AppIcon` asset catalog for native Finder, Spotlight, and Launch Services resolution. Every release build also decodes and renders the packaged PNG and ICNS through AppKit; insufficient visible pixels, color depth, luminance range, transparent corner silhouette, or ICNS size coverage stops packaging instead of shipping a blank placeholder.

## Control language

- Primary controls use a five-point chamfer, a blue action field, and a narrow green signal rail.
- Secondary controls use a four-point chamfer, a hairline border, and no decorative gradient.
- Panels use a subtle blue registration tick in the upper-left edge.
- Environment colors communicate operational risk; they are not decorative accents.
- Dense professional information uses monospaced eyebrow labels and tabular values. Explanatory copy remains proportional for readability.
- Large pills, floating glass cards, neon glows, sparkle icons, and ornamental AI gradients are outside the product language.

## Icons

Product navigation and branded actions use the custom `WorkbenchGlyph` and `UtilityGlyph` vector families. Their square line caps, measured nodes, and shared grid connect them to the main mark. Familiar platform symbols remain appropriate for universal macOS operations such as Keychain, deletion, disclosure, and accessibility.

AI Assist uses the routed-conversation glyph, not sparkles or a magic wand. It is presented as an optional engineering tool with visible context and risk—not as the visual identity of the product.

Live Assist responses use an original routed-channel glyph, a narrow blue provisional rail, and two offset square circuits for Stop. The transport instrument and Stop control communicate state without glows, animated gradients, or generic “AI” ornament. Stopped and interrupted output remain visibly labeled.

The Assist Context Shelf uses an original vertical evidence spine with three unequal routed rails and measured endpoint nodes. Its companion unpin mark crosses the selected route above a retained baseline. Together they distinguish deliberate evidence composition from generic attachment, stack, sparkle, or cloud imagery.

The Proposal Patch Stack uses an original Patch Loom mark: staggered bounded rails converge through a measured reticle without borrowing generic layers or sparkle imagery. Its Impact Lens reticle and selection marks distinguish queued alternatives, exact assembled changes, and unresolved external evidence while preserving the same square-cap grid language.

The Continuity Casebook uses an original Relay Knot mark: two unequal evidence routes cross through a measured custody node and continue toward separate handoff endpoints. Filled and open square nodes distinguish retained evidence, unresolved questions, and receiver acknowledgement without borrowing book, sparkle, chain, or generic AI imagery.

Source completion uses an original three-port fork mark: one measured local-analysis path branches into document, catalog, and reviewed-Assist outcomes. Terminal green denotes the active local signal, registration blue denotes the inspected junction, and the Assist outcome remains visually distinct from insertable source rows.

## Language

The interface uses one language at a time. The current milestone is English, so rotating proverbs and quotations must also be English. Their sources may be international; untranslated text must not be inserted into an English screen.

## Independence

The iTelAS name, mark, icon, glyphs, layout, and component language are original. They do not reproduce third-party icons, menu structures, or visual assets.
