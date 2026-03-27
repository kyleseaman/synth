# TODO

- [x] Extract reusable SidebarModeButton to eliminate sidebar button duplication in ContentView
- [x] Extract `updateIndexes(for:content:)` helper in DocumentStore to deduplicate 4-index update pattern
- [x] Replace DispatchQueue.main.async with structured concurrency in @MainActor contexts
- [x] Move extensions and helpers out of ContentView.swift into dedicated ViewHelpers.swift
- [x] Remove dead toolbar code (settingsToolbarButton, openWorkspaceButton) from ContentView
