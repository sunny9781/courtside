# Courtside

## Mac

Apple Silicon Macs. Paste this into Terminal:

```sh
curl -fsSL https://github.com/sunny9781/courtside/releases/latest/download/Courtside.zip -o /tmp/Courtside.zip && rm -rf /Applications/Courtside.app && ditto -xk /tmp/Courtside.zip /Applications && xattr -dr com.apple.quarantine /Applications/Courtside.app && open /Applications/Courtside.app
```

It updates itself after that.

## Android TV and Google TV

Nvidia Shield, Chromecast with Google TV, Google TV Streamer, and TVs with Google TV or Android TV built in
(Sony Bravia, TCL, Hisense and others). It updates itself after the first install.

**1. Install the Downloader app** (by AFTVnews) from the Play Store.

- **"Can't install… see common ways to fix the problem"** (often after a few percent):
  - Unplug the TV for a minute (standby isn't a restart), then try again.
  - Free up space: Settings › System › Storage. Uninstall unused apps, clear cached data.
  - Settings › Apps › See all apps › **Google Play Store** and **Google Play services** › Force stop, Clear cache, Clear data.
  - Check Settings › System › Date & time is set to automatic.
  - Try over your phone's hotspot. If that works, a VPN or ad-blocking DNS on your network is blocking it.
  - Or install from your phone: play.google.com › Downloader by AFTVnews › Install › pick the TV.

**2. Allow Downloader to install apps.**

- **Google TV** (Chromecast, Google TV Streamer, Sony and other TVs with a "For you" tab):
  - Settings › System › About › highlight **Android TV OS build** › press OK about 7 times until it says
    you're a developer. (Chromecast: Settings is under your profile picture, top right.)
  - Settings › Apps › Security & restrictions › Unknown sources › turn on **Downloader**.
- **Nvidia Shield and other Android TV:**
  - Settings › Device Preferences › Security & restrictions › Unknown sources › turn on **Downloader**.
- **Amazon Fire TV Stick** (Fire OS 6 or newer; the 2025 Fire TV Stick 4K Select can't install apps):
  - Settings › My Fire TV › About › highlight the device name › press OK 7 times until it says you're a developer.
  - Settings › My Fire TV › Developer options › Install unknown apps › turn on **Downloader**.
  - After installing, Courtside is under Your Apps (the apps button on the home screen).
- **Unknown sources is greyed out:** turn on developer mode first (the Google TV step above).
- **Can't find Unknown sources:** Settings › Apps › Special app access › Install unknown apps › **Downloader**.

**3. Install Courtside.**

- Open Downloader, type `is.gd/courtsidetv`, choose **Install**, then **Open**.
- **"App not installed" or blocked:** Downloader isn't allowed yet. Go back to step 2.
- **The short link doesn't work:** type
  `https://github.com/sunny9781/courtside/releases/download/android/Courtside.apk` instead.

**4. Sign in** with your Xtream details. The keyboard in the Google TV app on your phone makes typing easier.

**Updates:** the version button at the top right turns into **Install update** when there's a new version.
