# Courtside notes for Claude

- Read `NOTES.md` first: what the app is, the release flow, the layout, and Sunny's working preferences.
  Update it when something there changes.

- Every release that changes what the user sees: add an entry at the top of `Shared/Changelog.swift`
  (next version number — one up from the newest — date and time in Eastern time, short title, and each change
  tagged with the apps it applies to: mac, tv, ios, android). It shows in
  Settings › Updates › What's new, filtered to that app.
- Never log or share stream URLs (they contain the Xtream username and password).
- Check builds with `gh workflow run check.yml --ref <branch>` before merging to main.
