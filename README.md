# Courtside

Install on a Mac (Apple Silicon) by pasting this into Terminal:

```sh
curl -fsSL https://github.com/sunny9781/courtside/releases/latest/download/Courtside.zip -o /tmp/Courtside.zip && rm -rf /Applications/Courtside.app && ditto -xk /tmp/Courtside.zip /Applications && xattr -dr com.apple.quarantine /Applications/Courtside.app && open /Applications/Courtside.app
```
