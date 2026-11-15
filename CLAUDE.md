# Courtside notes for Claude

- Every release that changes what the user sees: add an entry at the top of `Shared/Changelog.swift`
  (date, short title, and each change tagged with the apps it applies to: mac, tv, ios). It shows in
  Settings › Updates › What's new, filtered to that app.
- Never log or share stream URLs (they contain the Xtream username and password).
- Check builds with `gh workflow run check.yml --ref <branch>` before merging to main.
