# webtrees-mobile

Flutter app (Android/iOS) for [webtrees](https://webtrees.net) sites. It talks to the server through the [api4webtrees](https://github.com/thobgg/api4webtrees) module.

<a href="https://apps.apple.com/app/id6815108154"><img src="docs/app-store-badge.svg" height="40" alt="Download on the App Store"></a>
<a href="https://play.google.com/store/apps/details?id=net.webtrees.webtreesmobile"><img src="docs/google-play-badge.png" height="58" alt="Get it on Google Play"></a>

## Server requirements

| | Minimum version |
|---|---|
| webtrees | 2.2 |
| api4webtrees – app works (older versions are refused with a hint) | **1.13.0** (API level 24) |
| api4webtrees – app appears on the "App" page (connect via link/QR code) | **1.13.1** |
| api4webtrees – welcome text, registration settings, changing your name | **1.14.0** |
| api4webtrees – "waiting for approval" marker | **1.15.0** |
| api4webtrees – hiding links to disabled modules | **1.18.2** |
| Registering inside the app | only the fork [Schoaf/webtreesand-api](https://github.com/Schoaf/webtreesand-api); elsewhere "Register" opens the site's registration page |

## Features

- **Connect to any webtrees site** – by entering its address or via the connect link from the site's "App" page (no password needed), also in a subfolder or with pretty URLs; switch between trees
- **Sign in and register** – welcome text and registration settings as configured on the site; optional biometric lock
- **Home** – start person, birthdays this week, responses to "Ask for help"
- **One tab each for Home, Person, Family tree and Search** – an individual always opens on the Person tab, a tree always on the Family tree tab; both start with the start person
- **Search** – live search with photos, lifespans and markers for deceased individuals; add a person right from the search
- **Individuals** – all facts, parents/spouses/children/siblings; relatives open in place with undo/redo; ⋮ menu to ask for help, share as text or link, edit and add a person; copy any value
- **Family tree view** – pannable view of parents, siblings, partners and children; tap to move through the tree, undo/redo, back to the start person in one tap
- **Edit** – edit facts and photos, add individuals and facts with place autocompletion; changes go through webtrees moderation
- **Offline notes** – facts recorded without a connection are kept and synchronised later
- **My account** – name, linked individual, start person
- **English, German and Dutch** – follows the device language or can be picked in My account

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
