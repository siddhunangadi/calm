# Calm — a strict, distraction-free Mac (phone app comes next)

Calm blocks **X (Twitter), Instagram, JioHotstar and adult sites** on your Mac — in every browser,
including private/incognito windows — and you can't switch it off on a weak moment.
Turning it off or removing it takes a **24-hour wait**.

## What it does

| Part | What you notice |
|---|---|
| **Guard** (`calmd`, runs in the background as the system) | Blocked sites never load. Firefox, Brave, Edge, Opera, Tor, VPN apps and the X/Instagram/JioHotstar apps close the moment you open them. If you edit the settings it blocks, it puts them back within seconds and your streak restarts. |
| **Chrome lock** (a settings profile) | Chrome has no incognito or guest mode. Chrome won't open until this is installed. |
| **Calm menu-bar app** (leaf icon, top-right) | Your clean streak, Focus mode, your Spotify playlist, Audible, "block more", and the 24-hour unlock. |

How sites are blocked, in short:
- Your Mac's **hosts file** (its own address book) points the blocked sites to nowhere.
- Your Mac's **DNS** (the internet's phone book) is set to CleanBrowsing's free Adult Filter, which also blocks new adult sites.
- A **firewall rule** stops apps from using "secure DNS" to get around the filter. iCloud Private Relay is turned off for the same reason.

## Install (about 10 minutes)

1. Get **Calm.pkg** in one of two ways:
   - **From GitHub:** [Releases](https://github.com/siddhunangadi/calm/releases) → newest **Calm** → download **Calm.pkg**.
   - **Build it on your Mac** (no Xcode needed, only Apple's free command-line tools). Open Terminal and run these one by one:
     ```bash
     xcode-select --install
     ```
     ```bash
     git clone https://github.com/siddhunangadi/calm.git
     ```
     ```bash
     cd calm/mac && swift test && ./scripts/build-pkg.sh
     ```
     The installer is then at `calm/mac/build/Calm.pkg`.
2. **Right-click Calm.pkg → Open** (needed because it isn't from the App Store) → enter your Mac password.
   The leaf icon appears in the menu bar.
3. Click the leaf → **Install Chrome lock** → in System Settings → General → **Device Management**, open "Calm: Chrome lock" → **Install**.
4. When macOS asks whether Calm may control Spotify, click **OK**.
5. Paste your Spotify playlist link in the leaf menu (Spotify → your playlist → ··· → Share → Copy link).

### Black page instead of an error (one time, per browser)
Blocked sites normally show the browser's "can't be reached" page. To get a plain black page instead in **Comet or Chrome**:
open `comet://extensions` (or `chrome://extensions`) → turn on **Developer mode** → **Load unpacked** →
choose **Macintosh HD → Library → Application Support → Calm → BlankPage** → in its Details, turn on **Allow access to file URLs**.
The leaf menu shows a "Black page" card with these steps until it's done. Once it's on, removing or turning it off
counts as tampering and restarts your streak. (The site stays blocked either way: the extension only changes what you see.)

### Silence notifications (one time)
1. System Settings → **Focus** → **+** → Custom → name it **Calm**.
   Allowed apps: **WhatsApp** and **Spotify** only. Allowed people: whoever you want calls from.
2. Open the **Shortcuts** app → new shortcut named **Calm Focus On** → action "Set Focus" → Calm → On.
3. Another shortcut **Calm Focus Off** → "Set Focus" → Calm → Off.

Now the Focus switch in the leaf menu hides other apps **and** silences their notifications.

## Devon Ke Dev Mahadev (one episode a day, in Comet)

JioHotstar stays blocked except for this one series. First add the Calm extension to Comet (see "Black page" above,
including **Allow access to file URLs**). Then **leaf menu → Devon Ke Dev Mahadev → Watch** opens the series in Comet
for **40 minutes, once a day**:
- the Calm extension lets only the series, its episodes, its search and Hotstar's sign-in pages open; anything else
  on Hotstar goes black;
- the first episode you open in the session is the only one that plays; other episodes and autoplay go black;
- other browsers close during the session (Comet stays because its Calm extension enforces the rules; if the
  extension is removed or turned off, Comet closes too);
- **End now** finishes the session early at any time.

## Desktop widgets

Right-click the desktop → **Edit Widgets…** → search **Calm**:
- **Clean streak** (small or medium): days clean, ring to your next milestone, Protected status.
- **Now playing** (small or medium): what's playing in Spotify (songs and podcasts) with artwork and ⏮ ⏯ ⏭.

The Calm menu-bar app keeps them up to date. macOS limits how often widgets redraw, so a new song can take a
moment to appear; the buttons always work straight away.

## The 24-hour unlock

1. Leaf menu → write why you want to unlock → **Request unlock**.
2. Wait 24 hours (you can cancel any time).
3. You then get **1 hour** to unblock a site, pause everything for 1 hour, or uninstall. Unused, it locks again.

Adding new blocks works any time — only loosening needs the wait.

**Wi-Fi login pages** (hotels, airports) sometimes need the router's DNS: use "Wi-Fi login page won't load?" in the leaf menu.
It allows that for 5 minutes, 3 times a day, and sites stay blocked.

## Updates

The leaf menu checks for a new version every 6 hours. When one is out it shows **Update available → Update now**.
Click it and enter your Mac password: Calm downloads the new version, removes the old one and restarts.
Your streak, lock and blocks stay as they are, and updating never needs the 24-hour wait.
(You can also click **Check for updates** at the bottom of the menu.)

To publish an update: raise the number in `mac/VERSION` and push. GitHub Actions tests it, builds Calm.pkg and
publishes it as the release `calm-v<version>`, which every installed Calm then offers.

## Honest limits
- You are still an admin on your Mac. Someone very determined, with Terminal and `sudo` or a full macOS reinstall, can get past any blocker. Calm makes that slow and annoying, and it logs it and resets your streak.
- Sites are blocked by name. A brand-new mirror of X or Instagram needs adding with **Block more**.

## For developers
```
mac/Sources/CalmShared   blocklists, 24-hour lock rules, hosts-file logic (unit-tested)
mac/Sources/calmd        the root guard (hosts, DNS, firewall, app quitting, requests)
mac/Sources/CalmBar      SwiftUI menu-bar app
mac/scripts/build-pkg.sh builds build/Calm.pkg on a Mac
```
Run tests on a Mac with `cd mac && swift test`. The guard logs to `/var/log/calmd.log`.
