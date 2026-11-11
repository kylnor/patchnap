# App-list UI verification — 0.1.1

User feedback on November 11, 2026 identified overlapping app action glyphs and requested source/status filters.

## Result

- Each row uses one three-dot menu with the native indicator hidden, a dedicated 32 × 28 pt area and an app-specific accessibility label.
- Source and status filters combine with name search using AND. The count and list use the same filtered snapshot.
- Clear filters restores all results, including from the filtered empty state.
- Displayed status and filter classification share one implementation and preserve existing status precedence.
- Filters are local view state. They do not change update exclusions, holds or installation settings.

## Evidence

35 Swift Testing functions passed on Apple Silicon, including five new tests covering combined predicates, clearing filters, status precedence, open-app classification, and manual-source filtering. Native capture checks covered the 850 pt app list and 680 pt minimum window in both appearances. Demonstration captures explicitly label synthetic data; all apps (3/3), source plus status (1/3), and an empty combination (0/3) were checked. The original row-menu overlap is absent. Picker text uses semantic foreground styling; preview appearance is propagated through SwiftUI and AppKit together.

Interactive controls retain native labels and focus behavior. No actual application updates were run for this UI change. The initial alpha's pending background/helper/live-update acceptance remains unchanged.
