# Courtside

Install on a Mac (Apple Silicon) by pasting this into Terminal:

```sh
curl -fsSL https://github.com/sunny9781/courtside/releases/latest/download/Courtside.zip -o /tmp/Courtside.zip && rm -rf /Applications/Courtside.app && ditto -xk /tmp/Courtside.zip /Applications && xattr -dr com.apple.quarantine /Applications/Courtside.app && open /Applications/Courtside.app
```

## Android TV and Google TV

Works on Google TV and Android TV devices: Nvidia Shield, Chromecast with Google TV, Google TV Streamer, and TVs
with Google TV or Android TV built in (Sony Bravia, TCL, Hisense and others). Courtside isn't in the Play Store, so
it's installed once with the free **Downloader** app; after that it updates itself (the version button in its top
bar turns into "Install update").

**1. Install Downloader** (by AFTVnews) from the Play Store.

**2. Allow Downloader to install apps.** Which steps depends on the device:

- **Google TV** (Chromecast with Google TV, Google TV Streamer, Sony Bravia and other TVs with the "For you" tab):
  developer mode has to be on first, or Unknown sources stays greyed out.
  1. Settings › System › About (on a Chromecast: profile picture, top right › Settings › System › About). Highlight
     **Android TV OS build** and press OK quickly about 7 times, until it says you're a developer.
  2. Settings › Apps › Security & restrictions › Unknown sources › turn on **Downloader**
     (on newer versions: Settings › Apps › Special app access › Install unknown apps › Downloader).
- **Nvidia Shield and other Android TV devices:** Settings › Device Preferences › Security & restrictions ›
  Unknown sources › turn on **Downloader** (on some versions it's under Settings › Apps). Developer mode isn't needed.

**3. Install Courtside:** open Downloader, type `is.gd/courtsidetv`, choose **Install**, then **Open**.
(The full link is `https://github.com/sunny9781/courtside/releases/download/android/Courtside.apk`.)

Typing your Xtream login is easier with the keyboard in the Google TV app on your phone.

**If Downloader won't install** ("Can't install… see common ways to fix the problem", often after a few percent):

- Unplug the TV for a minute (standby isn't a restart).
- Free up space: Settings › System › Storage; uninstall unused apps and clear cached data.
- Settings › Apps › See all apps › Google Play Store and Google Play services › Force stop, Clear cache, Clear data.
- Make sure Settings › System › Date & time is automatic.
- Try once over your phone's hotspot: if it works there, something on your network (a VPN or ad-blocking DNS) is
  blocking Google's downloads.
- Or install it from your phone: play.google.com › Downloader by AFTVnews › Install › pick the TV.
