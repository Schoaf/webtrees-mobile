# Stammbaum App

Flutter-Begleit-App (Android/iOS) für die selbst gehostete [webtrees](https://webtrees.net)-Instanz der Familie Scharf. Die App spricht über das Custom-Modul `webtreesand-api` mit dem Server — es gibt keine eigene Backend-API.

## Funktionen

### Start
Startperson und Suche auf einen Blick (eine neue Person legt man über den "Neu"-Tab unten an — kein eigener Button mehr auf dem Start-Bildschirm). Darunter, falls zutreffend, ein Block **"Geburtstage diese Woche"** (mit Torten-Icon) — lebende Personen mit Geburtstag in den nächsten 7 Tagen, als einfache Liste (Name, klein darunter "wird 31 · am Sonntag"), kein Foto, keine Card-Optik wie bei Suchergebnissen. Zeilen bleiben antippbar. Verstorbene werden nie angezeigt. Bottom-Navigation: **Start / Suche / Neu**.

Oben rechts: Initialen oder Foto der mit dem Konto verknüpften Person — antippbar, öffnet **"Mein Konto"**.

![Start](docs/screenshots/home.png)

### Suche
Personensuche mit Live-Ergebnissen. Jede Zeile zeigt:
- Foto oder Silhouette, nach Geschlecht eingefärbt
- einen farbigen Balken am linken Rand als zusätzliches Geschlechts-Kennzeichen (auch erkennbar, wenn ein Foto hinterlegt ist)
- ein Grabstein-Symbol für verstorbene Personen
- darunter: bei lebenden Personen das **volle Geburtsdatum** (kein Bindestrich); erst bei verstorbenen Personen "Jahr–Jahr". Gilt überall, wo diese Zeile erscheint (Suche, Eltern/Ehepartner/Kinder, Mein Konto).

![Suche](docs/screenshots/search.png)

### Person — Ansicht
Alle bekannten Fakten zu einer Person, dazu Eltern/Ehepartner/Kinder als verlinkte Karten. Reihenfolge und Sichtbarkeit der Felder:

- **Immer sichtbar:** Geburt, Tod, Geschlecht
- **Unter "Mehr anzeigen":** Titel, Wohnsitz, Datensatz-ID
- **Nicht angezeigt (nur beim Bearbeiten):** Name — steht bereits über dem Foto, eine zweite Anzeige in der Liste wäre redundant
- **Aktuell nicht verfügbar:** "Aktualisiert am" (GEDCOM `CHAN`) — wird vom `webtreesand-api`-Modul serverseitig herausgefiltert (`SKIP_FACTS`) und kann derzeit nicht abgerufen werden

Die Feld-Reihenfolge ist an einer einzigen Stelle im Code dokumentiert und leicht änderbar: `kFactDisplayOrder` in [`lib/screens/search/person_detail_screen.dart`](lib/screens/search/person_detail_screen.dart).

Ab der dritten verschachtelten Person (z. B. Eltern → Groß­eltern → Urgroß­eltern) erscheint unten links ein schwebender Home-Button, damit man nicht mehrfach "Zurück" tippen muss.

![Person](docs/screenshots/person_detail.png)

### Person — Bearbeiten
Der Stift-Button oben rechts schaltet die Ansicht auf bearbeitbar um (Stift wird zu X zum Abbrechen). Alle vorhandenen Fakten sind editierbar, auch die sonst unter "Mehr anzeigen" versteckten. Ein Ort-Feld (z. B. Wohnsitz) bietet Autovervollständigung aus den vorhandenen Orten des Stammbaums. Unten ein fixierter **Speichern**-Button.

Im Bearbeiten-Modus bekommt das Foto ein kleines Kamera-Symbol; antippen öffnet direkt Upload/Kamera zum Ändern, statt das Foto (falls vorhanden) nur anzuzeigen — genau wie beim erstmaligen Hinzufügen ohne Foto.

Der schwebende **Fakt hinzufügen**-Button (unten rechts) bleibt für neue Fakten separat erhalten und wird nur im Ansichtsmodus angezeigt.

Änderungen von Rollen ohne Auto-Freigabe landen wie gewohnt in der webtrees-Moderationswarteschlange.

![Person bearbeiten](docs/screenshots/person_edit.png)

### Neue Person / Fakt hinzufügen
Formular mit Vorname/Nachname, Geschlecht, Geburtsdatum/-ort (mit Orts-Autovervollständigung), Verknüpfung zu einer bestehenden Person sowie beliebig vielen "weiteren Angaben" (Beruf, Konfession, Wohnort, Notiz, …) — auch Wohnort nutzt die Orts-Autovervollständigung.

### Offline-Fallback
Ist der Server beim schnellen Fakt-Erfassen nicht erreichbar, wird der Eintrag lokal als Notiz gespeichert und kann später synchronisiert werden.

### Mein Konto
Eigene Seite (nicht dasselbe wie eine Personen-Detailseite): Benutzername, Name und Rolle des webtrees-Kontos, dazu die damit **verknüpfte Person** und die **Startperson** des Baums, je als anklickbare Karte zur jeweiligen Personen-Detailseite. Erreichbar über den Kreis oben rechts am Start-Bildschirm.

Der Stift oben rechts schaltet auf Bearbeiten um: **Name** wird zum Textfeld, die **Startperson** lässt sich über "Startperson ändern" per Personensuche neu wählen, unten ein fixierter Speichern-Button. Benutzername und Rolle bleiben absichtlich schreibgeschützt (Rolle ist serverseitig festgelegt), die **verknüpfte Person** ebenfalls — das Ändern der Verknüpfung ist in webtrees selbst eine Admin-Funktion (Benutzerverwaltung), keine Selbstbedienung, und die App hält sich an diese Grenze.

![Mein Konto](docs/screenshots/account.png)

## Design

Das komplette UI-Design (alle Screens, bearbeitbar) liegt als Claude-Design-Canvas vor: **"Stammbaum App Screens"**. Es spiegelt jeweils den aktuellen Stand der App wider und wird bei größeren UI-Änderungen aktualisiert.

## Entwicklung

- State-Management: Riverpod
- Netzwerk: `dio`, eigenes Cookie-Handling (siehe Kommentar in [`lib/api/webtrees_client.dart`](lib/api/webtrees_client.dart))
- Lokaler Speicher: `sqflite` (Offline-Notizen)
- Ziel-Server: Produktion `stammbaum.familiescharf.at` (Standard) oder eine lokale Dev-Instanz (`lib/state/app_providers.dart`)

### Bekannte Lücken (noch nicht umgesetzt)
- Mehrsprachigkeit (Deutsch/Englisch)

### Hinweis zum Server
"Geburtstage diese Woche" nutzt den bestehenden `Anniversaries`-Endpunkt des `webtreesand-api`-Moduls. Dessen Julian-Day-Berechnung (`->julianDay()` auf `CarbonImmutable`, nie eine echte Carbon-Methode) führte serverseitig zu einem 500-Fehler — behoben in `modules_v4/webtreesand-api/WebtreesAndApiModule.php` (nutzt jetzt `Fisharebest\ExtCalendar\GregorianCalendar`, dieselbe Kalender-Bibliothek, die webtrees selbst mitliefert). Geprüft: Der Fehler existiert **nicht** in webtrees-Core selbst — daher kein Pull-Request nötig, nur der third-party-Modul-Fix. (Ein erster Versuch nutzte `TimestampFactory::todayJulianDay()`, das es in webtrees-Core zwar gibt, aber erst ab einer neueren Version als der auf Produktion laufenden 2.2.6 — das brach kurzzeitig die Produktion, bevor auf die versionsunabhängige Variante gewechselt wurde.) Ist auf Produktion deployt und verifiziert.
