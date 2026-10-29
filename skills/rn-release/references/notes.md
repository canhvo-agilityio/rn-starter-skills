# Release notes and the changelog

Two texts from the same list of changes, for two readers. The dev owns the wording; you draft.

## Where the changes come from

`release-status.sh` → `changes`: commits since the last `v*` tag, with the ticket ids in their subjects. Ticket files are gone by now (rn-feature removes them when a ticket is done), so when a commit subject isn't enough to say what changed for the user, read the merged PR / MR's description (`gh pr view <n>`, `glab mr view <n>`, or ask the dev). The board stays the source for what a ticket asked; don't invent features from commit names.

Leave out what users never see (refactors, tests, CI, dependency bumps without a visible effect), unless it fixes something they noticed.

## Store "What's new"

What users read on the store page and in the update prompt.

- Short and in plain words: what they can do now, what works better. No ticket ids, no technical terms, no "various bug fixes" when there's something concrete to say.
- In each language the store listing has (ask once; record it in `docs/release-plan.md`). Translate faithfully; the dev checks a language they don't read with someone who does.
- Limits: App Store 4,000 characters, Google Play 500 characters per language. Aim for 3–5 lines.
- An OTA update has no store page: the notes go only in the changelog and the update message.

```
Save your favorite coffees with the heart on any drink and find them in the new Favorites tab.
Your bag now shows the delivery fee before checkout.
Fixed: the bag badge sometimes showed the wrong number after removing a drink.
```

## CHANGELOG.md

The team's record, newest first, one section per release, written in English like the code. Ticket ids stay here, linked when the board's URL pattern is known.

```markdown
## 1.4.0 — 2026-11-03

Store build · runtime 3f9c2a1 · release PR / MR #57

### Added
- Favorites: heart on every drink, Favorites tab (SHOP-15)

### Changed
- Bag shows the delivery fee before checkout (SHOP-12)

### Fixed
- Bag badge count after removing a drink (SHOP-31)
```

For an OTA release, the second line says `OTA update on store build 1.4.0 · runtime 3f9c2a1`. Create the file on the first release with a one-line intro (`All notable changes to this app.`).
