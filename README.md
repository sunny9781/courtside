# Courtside

Install on a Mac (Apple Silicon) by pasting this into Terminal:

```sh
curl -fsSL https://github.com/sunny9781/courtside/releases/latest/download/Courtside.zip -o /tmp/Courtside.zip && rm -rf /Applications/Courtside.app && ditto -xk /tmp/Courtside.zip /Applications && xattr -dr com.apple.quarantine /Applications/Courtside.app && open /Applications/Courtside.app
```

## Android TV (Nvidia Shield, Chromecast with Google TV)

Courtside isn't in the Play Store, so it's installed with the free **Downloader** app. After that it updates itself
(an "Install update" button appears in its top bar).

**1. Install Downloader** (by AFTVnews) from the Play Store.

**2. Allow Downloader to install apps**

- *Nvidia Shield:* Settings › Device Preferences › Security & restrictions › Unknown sources › turn on **Downloader**.
  (On some versions it's under Settings › Apps › Security & restrictions.) Developer options aren't needed.
- *Chromecast with Google TV:* turn on developer mode first, or Unknown sources stays greyed out:
  1. Profile picture (top right) › Settings › System › About › click **Android TV OS build** quickly until it says
     you're a developer.
  2. Back to Settings › Apps › Security & restrictions › Unknown sources › turn on **Downloader**.
     (Newer versions: Settings › Apps › Special app access › Install unknown apps.)

**3. Install Courtside:** open Downloader, type `is.gd/courtsidetv`, choose **Install**, then **Open**.
(The full link is `https://github.com/sunny9781/courtside/releases/download/android/Courtside.apk`.)

Typing your Xtream login is easier with the keyboard in the Google TV app on your phone.
