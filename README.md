# Vacuum the World – Shop & „VACUUM MEGA-FACTORY“

Komplettes Ingame-Shop-System für Roblox (Rojo), bestehend aus

- **Klassischer Modus** – schnelles 2D-Shopfenster (Dark-Mode/Glassmorphism, Kategorie-Tabs, Grid, Details-/Bestätigungs-Popup), überall über den 🛒-Button im HUD erreichbar.
- **VACUUM MEGA-FACTORY** – begehbares, animiertes 3D-Shop-Gebäude in jeder Welt (Cleanville: Chrom & Neon, Dustlands: Messing, Zahnräder, Dampf).

Der **Server ist autoritativ**: Der Client schickt nur eine Item-ID. Preis, Währung, Guthaben, Freischaltbedingungen, Nacht-/Tageslimits, Zufallsergebnisse (Kapseln, Mystery Crate) und Cooldowns werden ausschließlich serverseitig aus `src/shared/Definitions` berechnet.

---

## Projektstruktur

```
default.project.json
src/
  shared/                      -> ReplicatedStorage.Shared
    Definitions/               alle Inhalte als Daten
      Shop.luau                Kategorien, Gamepasses, Coin-Packs, Mystery Crate,
                               flache Item-Liste (Id, Name, Preis, Währung, IconAssetId, Rarity, Kategorie)
      Vacuums.luau             16 Staubsauger (Stats, Preis, Freischaltung, Look)
      Upgrades / Capsules / Pets / Cosmetics / Trophies / Boosts / Bosses / Currencies
      Rarities.luau            Farben/Verläufe pro Seltenheit
      Sequences.luau           Rarity → Länge & Effekte der Shows (datengetrieben)
      Factory.luau             Grundriss, Zonen, Testkammer-Tuning, Tag/Nacht
      Worlds.luau              Welten + Fabrik-Themes
      Trash.luau               Müll-Sets für die Testkammer
      Sounds.luau              alle Sound-IDs an einer Stelle
    Models/                    Staubsauger, Pets, Trophäen, Roboter aus Parts
    Util/                      Builder, Stats, Progress, Format, DayNight, Trove, Signal, Errors
    Net.luau                   alle Remotes
    DataTemplate.luau          Spielerprofil + Reconcile
  server/                      -> ServerScriptService.Server
    Services/  DataService, ShopService, UpgradeService, MonetizationService,
               TestChamberService, FactoryService, AdminService
    Factory/FactoryBuilder.luau   baut die Fabrik (statisch, für alle gleich)
  client/                      -> StarterPlayerScripts.Client
    Controllers/ ClientData, HudController, ShopController
    Shop/      ClassicShop, ConfirmModal, FactoryHud, FactoryView, CameraDirector,
               Sequence, Effects, Audio, UI/{Theme,Components}
    Shop/Zones/  Ambience, Workers, Showroom, TestChamber, UpgradeLab,
                 CapsuleHall, PaintShop, TrophyVault, Lobby
    Shop/Shows/  EntryShow (Röhren-Einfahrt), PurchaseShow (Fertigungs-Show)
tests/lune/    automatische Checks (siehe unten)
```

## Remotes (alle in `Net.luau`)

| Remote | Richtung | Zweck |
|---|---|---|
| `PurchaseItem(itemId)` | Client → Server | Kauf (Staubsauger, Kapsel, Boost, Kosmetik, Trophäe, Mystery Crate) |
| `PurchaseUpgrade(upgradeId)` | Client → Server | Upgrade-Labor |
| `EquipVacuum`, `EquipCosmetic`, `SetSetting` | Client → Server | Ausrüsten / Einstellungen (nur whitelisted Keys) |
| `StartTestChamber(vacuumId)`, `StopTestChamber()` | Client → Server | „Try before you buy“ (Cooldown, Rate-Limit, Distanz-, Freischalt- und Lane-Prüfung, harter Server-Timeout) |
| `RequestSync` | Client → Server | Fallback, falls der erste Daten-Push verpasst wurde |
| `DataSync`, `Notify`, `TestChamberEnded` | Server → Client | Profil-Snapshot, Toasts, Testende |
| `ShopBroadcast` | Server → alle | Käufe anderer Spieler (Feed, Konfetti, jubelnde Roboter) |

Antworten haben immer die Form `{ Ok = true, ... }` oder `{ Ok = false, Code = "NOT_ENOUGH", Error = "Not enough Coins." }` (Codes in `Util/Errors.luau`).

**Anti-Exploit:** Typprüfung aller Argumente, Token-Bucket-Rate-Limits pro Remote, Kauf-Sperre gegen Doppelkäufe, Preis nur aus Server-Definitionen, atomares Prüfen+Abziehen, Rückerstattung falls die Gutschrift fehlschlägt, Kapsel-/Crate-Würfe nur serverseitig, Robux-Käufe nur über `ProcessReceipt` mit Beleg-Deduplizierung und erzwungenem Speichern.

---

## Die Fabrik

| Bereich | Was passiert |
|---|---|
| **Fassade** | Zahnräder drehen sich, Pumpen „atmen“, Neon-Kanten, ein riesiger Dach-Staubsauger saugt Müll aus der Luft, Kamine dampfen (Dustlands). |
| **Einfahrt** | In die Ansaugröhre laufen → Kamerafahrt durch die Glasröhre in den Showroom (Partikel, Speedlines, FOV-Kick, Sound). Skip-Button für Wiederholer, Einstellung „Always Skip Intro“. |
| **Showroom** | Karussell aus Podesten. Wischen, ←/→, A/D, D-Pad, LB/RB; Kamera gleitet zum Podest. Hologramm mit animierten Stat-Balken gegen den ausgerüsteten Sauger (grün/rot, Zahlen zählen hoch). Gewähltes Modell rotiert, fährt in die Explosionsansicht und setzt sich wieder zusammen. Gesperrte Sauger hinter Glas mit Schloss und animierter Bedingung – beim Freischalten zerspringt das Glas. |
| **Kauf-Show** | Münzen fliegen aus dem HUD in den Münzschlitz → Roboterarme (IK) montieren den Sauger Teil für Teil mit Funken → Fließband → Röhre → dein Charakter tritt heraus (Cheer-Pose + Konfetti). Rarity steuert alles über `Sequences.luau` (Legendary: Lichtshow; Mythic: Fabrik bebt, Lampen flackern, Himmel färbt sich). |
| **Testkammer** | 4 Bahnen. 20 s mit jedem freigeschalteten Sauger: Förderband, Zähler, Tankfüllung mit Auto-Verkauf, „TOO HEAVY“ bei zu schwerem Müll, Saugeffekt und -sound. Ergebnis-Tafel „+340 % faster than your current vacuum“. Andere Spieler sehen laufende Tests. |
| **Upgrade-Labor** | 4 Maschinen (Tank, Düse, Turbine, Motor) wachsen sichtbar mit jeder Stufe. |
| **Kapselhalle** | Greifautomaten: Greifer holt eine Kapsel, Kugelbahn mit Kamerafahrt, Wackeln, Aufplatzen, Pet-Enthüllung (Intensität nach Seltenheit). |
| **Lackiererei** | Der eigene Sauger fährt durch die Sprühkabine; Skins werden Teil für Teil aufgesprüht, Trails angebracht. |
| **Trophy Vault** | Tresortür öffnet sich nur mit Boss-Kernen. Trophäen als Hologramm (kaufbar) oder animiert (Mini Rust Dragon spuckt Feuer). |
| **Lobby** | Förderband bringt alle 24 h (UTC) eine Mystery Crate mit Countdown-Bildschirm; Night-Deals-Stand leuchtet nachts. |
| **Leben** | Roboter-Arbeiter laufen synchron für alle Spieler (Serverzeit), drehen sich bei seltenen Käufen zum Käufer und jubeln. Käufe anderer erscheinen im Feed mit Konfetti am Käufer. |

### Premium-Effekte („AAA-Politur“)

| Bereich | Effekte |
|---|---|
| **Kino-Look** (`Shop/Cinematics.luau`) | Letterbox-Balken, Tiefenschärfe mit Fokusnachführung aufs Objekt, Bloom, Color-Grading, Vignette, „Impact Frames“ im Höhepunkt jeder Show (Kauf, Kapsel, Crate, Einfahrt). |
| **Fabrik-Spektakel** (`Zones/Spectacle.luau`) | Lauflichter ums Hauptschild mit Einschalt-Flackern, Suchscheinwerfer bei Nacht, zwei rotierende Hologramme (ForceField-Material) des Mythic-Saugers am Eingang, Lieferdrohnen mit Fracht über dem Dach (synchron per Serverzeit), Lichtschächte durch die Oberlichter (folgen der Sonne), schwebende Staubpartikel, Luftstrom + eingesaugtes Laub an der Röhre, Lauflicht-Pfeile auf dem Vorplatz, **Feuerwerk** über der Fabrik bei Epic+-Käufen (für alle sichtbar). |
| **Showroom** | Projektionskegel vom Podest zum Hologramm, aufsteigende Funken ab Epic, umkreisende Licht-Orbs mit Leuchtspur bei Legendary/Mythic, pulsierende Bodenringe am gewählten Podest, Glitch-Einblendung der Hologramme. |
| **Kauf-Show** | Schweißblitze mit echtem Punktlicht, Blitzbögen ab Legendary, „Hero Shot“: Kamerafahrt um das fertige Modell mit Lichtfächer, Spot-Licht und eingeblendetem Namen (ab Epic). |
| **Kapseln / Crate / Tresor / Labor** | Leuchtspur der Kapsel auf der Kugelbahn, Lichtsäule + Lichtfächer + Kamerafahrt bei der Enthüllung, goldene Strahlen aus dem aufschwingenden Tresor, „LEVEL UP“-Label über wachsenden Maschinen. |
| **Klassisches Fenster** (`UI/UIFx.luau`) | Öffnungs-Choreografie (Vignette, Akzentlinie zeichnet sich, Header gleitet herein, Tabs und Karten kaskadieren), schimmernder Glasrand, Bokeh-Hintergrund, weiche Kartenschatten, Parallax-Tilt beim Hover, Holo-Folie (Epic+), Funkeln + Strahlenkranz (Legendary+), schwebende Icons (Mythic), flüssiger Tab-Indikator, Richtungs-Übergang beim Tabwechsel, Ripple beim Klick, Call-to-Action-Glint auf kaufbaren Items, „PURCHASED!“-Stempel mit Partikel-Burst, Kartenflip-Enthüllung für Pets und Crate-Loot. |
| **Modal** | Öffnet sich aus der angeklickten Karte heraus und schrumpft beim Schließen dorthin zurück; 3D-Vorschau auf leuchtendem Drehteller mit Strahlenkranz, Glow und Funkeln; Schreibmaschinen-Titel. |
| **HUD** | Schwebende „+1.2K“/„−250“-Zahlen, rotierendes Währungssymbol mit Glow-Ring, Banner mit Lichtstrahlen, Glint, Unterstrich-Animation und Schreibmaschinen-Titel, Toasts mit Timer-Leiste, pulsierender „!“-Badge am Shop-Button, sobald die Mystery Crate bereitsteht. |

Alle Stärken stehen datengetrieben in `Sequences.luau` (`HeroShot`, `Lightning`, `Fireworks`, `Pillar` pro Rarity). **Low Graphics** schaltet Tiefenschärfe/Bloom ab und reduziert Lauflichter, Suchscheinwerfer, Drohnen, Lichtschächte, Partikel, Feuerwerk, Funkeln, Strahlen, Schattenlagen und Parallax; **Reduce Motion** verzichtet zusätzlich auf Hero-Shot-Kamerafahrten, Orbit-Kameras und Kamerawackeln.

**Schlankes HUD in der Fabrik:** Zonen-Schnellreise links, Kontext-Panel rechts (auf dem Handy unten), Karussell-Pfeile, Zurück-Button, Eingabehinweise. **🛒 Quick** öffnet jederzeit den klassischen Modus.

**Steuerung:** Alles per Tippen/Klicken. Tastatur: ←/→ blättern, Enter kaufen, T testen, Backspace zurück, Leertaste überspringen, Q/E Tabs. Gamepad: D-Pad/LB/RB, A, X, B, Y (Shop).

**Performance:** Alle Animationen laufen clientseitig, nur in der Nähe der Fabrik und gedrosselt (BulkMoveTo, 20–45 Hz). Low Graphics (automatisch auf schwachen Geräten, umschaltbar im ⚙-Menü) reduziert Partikel, Konfetti, Roboter, Lichtshow und Update-Raten. „Reduce Motion“ schaltet Kamerawackeln ab. Keine EditableMeshes – alles sind normale Parts.

---

## Einbau ins bestehende Projekt (v0.13.0)

Das Repository war leer, daher ist das System eigenständig lauffähig aufgebaut. Für die Übernahme:

1. **Daten:** `DataService` kapselt alles (`GetData`, `Update`, `Spend`, `Give`, `HasReceipt`, `ForceSave`). Entweder deinen bestehenden DataService mit diesen Methoden anbieten oder die Felder aus `DataTemplate.luau` in dein Profil übernehmen. Boss-Siege, Welten und Mastery liest der Shop aus `Progress.Bosses / Worlds / Mastery`.
2. **ProcessReceipt:** Ein Spiel darf nur einen Handler haben. Hast du schon einen, rufe dort `MonetizationService:HandleReceipt(receiptInfo)` auf und entferne die Zuweisung in `MonetizationService:Start`.
3. **Fabrik platzieren:** In `workspace.Worlds.<WorldId>` ein Part `FactoryAnchor` setzen (Mitte der Fassade am Boden, LookVector zeigt ins Gebäude). Ohne Anker wird `Worlds.FactoryOrigin` benutzt.
4. **Tag/Nacht:** Hat dein Spiel einen eigenen Zyklus, `Factory.DayNight.DriveClock = false` setzen. Nacht-Angebote richten sich dann nach deiner `Lighting.ClockTime`.
5. **Admin-Panel (F2):** Die Testbefehle in `AdminService` (`/coins`, `/cores`, `/boss`, `/world`, `/time`, `/crate`, `/resetshop`) lassen sich direkt an Buttons hängen.
6. **Neue Welt (Frost Kingdom):** Eintrag in `Worlds.luau` auf `Released = true`, Staubsauger/Kapseln mit `World = "FrostKingdom"` anlegen – Fabrik, Podeste, Kapselautomaten und Bahnen entstehen automatisch.

### Platzhalter, die du ersetzen solltest

- **Gamepass-/Produkt-IDs:** `GamePassId`/`ProductId = 0` in `Shop.luau` und `Boosts.luau`. Mit 0 zeigen die Karten „Soon“.
- **Icons:** `IconAssetId = 0` → Platzhalter-Icon (Rarity-Verlauf + Symbol). Echte Bild-ID eintragen, sobald vorhanden.
- **Sounds:** `Sounds.luau` nutzt eingebaute `rbxasset://sounds/...`-Dateien. Für einen hochwertigen Mix eigene Audio-IDs eintragen.
- **3D-Modelle:** Echte Mesh-Modelle unter `ReplicatedStorage.Assets.Vacuums.<ModelName>`, `Assets.Pets.<PetId>` oder `Assets.Trophies.<Model>` ablegen – sie ersetzen automatisch die Part-Modelle. Für Explosionsansicht/Lackierung Attribute `Role` (Body/Accent/Metal/Dark/Glow/Glass) an die Teile setzen.

---

## Testen

**Bereits automatisiert geprüft** (ohne Roblox Studio):

- `rojo build` erfolgreich, `luau-lsp analyze` mit Roblox-Typdefinitionen ohne Fehler/Warnungen.
- `tests/lune/server.luau` (Lune, echtes Roblox-Instanzmodell mit Property-Validierung): beide Fabriken werden gebaut (~950 Parts je Welt) und alle vom Client erwarteten Namen/Attribute existieren; 27 Kauf-Szenarien (zu wenig Geld, gesperrt, doppelt, Nacht-Angebot tagsüber, zweite Crate am Tag, Robux über Remote, Rate-Limit, volles Inventar, …).
- `tests/lune/models.luau`: alle 16 Staubsauger, 11 Kosmetiken, 14 Pets, 6 Trophäen, Roboter-Posen und Arm-IK.

```
rokit install
rojo build default.project.json -o build.rbxlx
lune run tests/lune/server.luau build.rbxlx
lune run tests/lune/models.luau build.rbxlx
```

**Noch in Studio zu prüfen** (konnte hier nicht laufen – UI, Kamera, Input, Partikel und Performance gibt es nur in der Engine):

1. `rojo serve`, in Studio verbinden, *Game Settings → Security → Enable Studio Access to API Services* (sonst nur Speicher im RAM, Warnung im Output).
2. Play → `/coins 100000000`, `/boss TrashKing`, `/world Dustlands`, `/time 22` für alle Zustände.
3. Durchspielen: Einfahrt + Skip, Showroom (Wischen/Pfeile/Gamepad), Kauf jeder Rarity (Common kurz … Mythic mit Beben/Himmel), Testkammer, Labor, Kapseln, Lackiererei, Tresor, Crate, Night Deals, klassischer Modus.
4. Unterbrechen: während jeder Show sterben/resetten, Skip drücken, Fabrik per Zonen-Reise verlassen – Kamera und Steuerung müssen immer zurückkommen.
5. Mehrspieler: *Test → Clients and Servers* mit 2–3 Spielern (Feed, Konfetti, jubelnde Roboter, belegte Testbahnen).
6. Handy-Ansicht über den Device Emulator (iPhone/Android, Querformat); Low Graphics an/aus.
7. FPS: Stats-Overlay (*Shift+F5*) bzw. *View → MicroProfiler* im Showroom und während einer Mythic-Show messen.
