# ZoneBox Pro licensing

ZoneBox sells a lifetime Pro license through Creem. Core snapping stays free.

## What is free

- Layouts and the layout editor
- Shift-drag / right-click-drag snapping
- Numbered zone hotkeys
- Divider handles

## What Pro unlocks

- Workspace capture and restore
- Hover pin
- Quick Snapper

New installs get a **14-day Pro trial**. After that, Pro features ask for a license; snapping does not.

## Purchase

- Product: ZoneBox Pro
- Price: **US$29**, one-time
- Provider: [Creem](https://www.creem.io) (Merchant of Record)
- Checkout: https://zonebox-site.vercel.app/buy
- After payment, Creem emails a license key and the site shows it on /success

## Activation

The Mac app never embeds a Creem API key. It talks to https://zonebox-site.vercel.app/api/license, which proxies activate, validate, and deactivate.

Users can paste a key in Settings -> License, or open zonebox://activate?key=...

The local record lives at ~/Library/Application Support/<bundle-id>/license.json. Debug and Release keep separate files because they use different bundle IDs.

An active license stays valid offline for 7 days, then in a 30-day grace window. Past that, or if Creem reports expired/disabled, Pro features lock.

## Developer overrides

- ZONEBOX_UNLOCK_PRO=1 in Debug unlocks Pro without a key
- ZONEBOX_CHECKOUT_URL and ZONEBOX_LICENSE_API override the site endpoints
