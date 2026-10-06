# webtrees-mobile

Flutter app (Android/iOS) for [webtrees](https://webtrees.net) sites. It talks to the server through the [api4webtrees](https://github.com/thobgg/api4webtrees) module.

<a href="https://apps.apple.com/app/id6815108154"><img src="docs/app-store-badge.svg" height="40" alt="Download on the App Store"></a>

## Server requirements

| | Minimum version |
|---|---|
| webtrees | 2.2 |
| api4webtrees – app works | **1.13.0** (API level 24) |
| api4webtrees – app appears on the "App" page (connect via link/QR code) | **1.13.1** |
| In-app registration, welcome text/registration settings, changing your name | currently only in the fork [Schoaf/webtreesand-api](https://github.com/Schoaf/webtreesand-api) |

## Features

- **Connect to any webtrees site** – by entering its address or via the connect link from the site's "App" page (no password needed); switch between trees
- **Sign in and register** – welcome text and registration settings as configured on the site; optional biometric lock
- **Home** – start person, birthdays this week, responses to "Ask for help"
- **Search** – live search with photos, lifespans and markers for deceased individuals
- **Individuals** – all facts, parents/spouses/children/siblings, copy any value, share as text or link
- **Family tree view** – pannable view of parents, siblings, partners and children; tap to move through the tree, undo/redo
- **Edit** – edit facts and photos, add individuals and facts with place autocompletion; changes go through webtrees moderation
- **Offline notes** – facts recorded without a connection are kept and synchronised later
- **My account** – name, linked individual, start person
- **German and English**

<p>
<img src="docs/screenshots/home.png" width="150" alt="Home">
<img src="docs/screenshots/search.png" width="150" alt="Search">
<img src="docs/screenshots/person_detail.png" width="150" alt="Individual">
<img src="docs/screenshots/tree_view.png" width="150" alt="Family tree view">
<img src="docs/screenshots/account.png" width="150" alt="My account">
</p>

## Development

Flutter, Riverpod, `dio`, `sqflite`. A local dev server is configured in [`lib/state/app_providers.dart`](lib/state/app_providers.dart).

## License

[GPL-3.0](LICENSE). Bundled Roboto font: [OFL-1.1](assets/fonts/OFL.txt).
