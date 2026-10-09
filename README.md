# ForeverPlus

AddOn für **World of Warcraft: Forever** (Client 1.60.x, TOC-Interface `16001`, Mainline-API 12.x mit „Secret Values“).
Verbessert das originale Forever-Interface (Blizzard-Code „Camelot“) und bleibt optisch beim Original.

Einstellungen: **Esc → Optionen → AddOns → ForeverPlus** (je Thema ein Untermenü: Chat, Tooltip, Gegenstände, Quests, Mouseover, Aktionsleisten, Kampf, Buff-Erinnerung, Talente, Karten & Infos, Erfahrung & Ruf, Optik, Schrift, Rezeptradar) oder `/fp`. Auf der Hauptseite: „Alle Meldungen stumm“, „Verschieben, Skalieren, Sperren“, „Alle Positionen sperren“, „Alle Positionen zurücksetzen“, „Mehrere Fenster zugleich“.

Alles Bewegliche (Fenster und ForeverPlus-Anzeigen wie Koordinaten, FPS/MS, Weltkarten-Koordinaten) wird gleich bedient und ist anfangs gesperrt: **Alt + Rechtsklick** entsperrt/sperrt einzeln, dann verschiebt **Alt + Ziehen** und **Strg + Mausrad** skaliert. Gesperrte Fenster lassen das Mausrad in Ruhe (Kamera-Zoom, Aktionsleisten-Blättern); „Zurücksetzen“ sperrt alles wieder. ForeverPlus-Anzeigen gehen zusätzlich ohne Taste (Ziehen, Mausrad, Rechtsklick); bei Blizzard-Fenstern würde das mit Gegenstände-Ziehen, Listen-Scrollen und Rechtsklick-Menüs kollidieren.
`/rl` lädt das Interface neu, `/fp fehler` öffnet die Fehlerliste, `/fp schrott` die Schrottmarkierungen, `/fp radar` zeigt den Zustand des Rezeptradars (Index, Berufe, Händler der aktuellen Karte und warum ihre Rezepte fehlen: bekannt, Fertigkeit, anderer Beruf, Fraktion, Optionen), `/fp karte` prüft die Weltkarten-Daten zur offenen Karte, `/fp talente` öffnet den Talentbaum (vor Stufe 10 zum Planen), `/fp mausrad` prüft eine Minute lang, wer das Mausrad bekommt (auch Elemente ohne Mausfokus), wie Shift + Mausrad belegt ist und ob Blizzards Blätter-Befehl läuft, `/fp kopieren` die letzten 50 Chatzeilen zum Kopieren, `/fp messen` und `/fp zeiten` die Laufzeitmessung, `/fp hilfe` alle Befehle.

## Funktionen

| Bereich | Funktion | Option |
|---|---|---|
| Chat | Drei Symbole links vom Chat (Soziales, Kanäle, Chatmenü) ausblenden | ja |
| | Mittelklick auf einen Chatreiter wechselt zur nächsten Sprache | ja |
| | Reiterbeschriftungen blenden mit dem Chat aus (sichtbar bei Mouseover oder neuen Nachrichten) | ja |
| | Chatschrift mit Outline | – |
| | Reiter-Hintergründe (Allgemein, Kampflog, …) entfernt | – |
| | Eingabefeld oben über den Reitern, ohne Rahmen/Hintergrund | – |
| | Chathintergrund-Regler auf 0 (100 % transparent) | ja |
| | Pfeil hoch/runter holt gesendete Zeilen zurück (letzte 50, auch aus früheren Sitzungen) | ja |
| | Mausrad scrollt den Chat (auch wenn Blizzards Einstellung beim Laden aus war); Shift + Mausrad springt an Anfang/Ende | ja |
| | Kopierknopf oben rechts im Chat (bei Mouseover): letzte 50 Zeilen als markierter Text (Strg+C), Links als Klartext | ja |
| | Chat der letzten Sitzung behalten (je Fenster einstellbare Zeilenzahl, geschützte Nachrichten ausgenommen) | ja |
| | Kanalnamen abgekürzt: [2. Handel - Stadt] → [2. H], LokaleVerteidigung → LV | ja |
| | Zeitstempel in eigener Farbe | ja |
| | Wiederkehrende Meldungen zusammenfassen: Fertigkeitsanstiege und Rufänderungen erscheinen nach einer Wartezeit (Standard 30 s) als eine Zeile mit letztem Wert bzw. Summe und Anzahl („… auf 11 erhöht (×8)“) | ja |
| | Schlagwort-Alarm: Klang (wählbar) bei eigenen Schlagwörtern als ganzes Wort („it“ meldet nicht „invite“); Schlagwörter optional farbig; Liste je Charakter, vorbelegt mit Name und Klasse | ja |
| | Beute zusammenfassen: eigene Beute, selbst hergestellte Gegenstände und eigenes Geld als je eine anklickbare Zeile nach einer Pause (einstellbar); Klick öffnet ein Popup am Mauszeiger mit Symbol, Anzahl und Herkunft (Shift-Klick verlinkt im Chat); Gegenstände ab gewählter Qualität zusätzlich direkt in der Zeile | ja |
| | Beute-Popup mit Alt + Rechtsklick entsperren und an den gewünschten Platz ziehen; ohne gespeicherten Platz erscheint es am Mauszeiger | ja |
| Tooltip | Gesundheitsleiste unten im Tooltip | – |
| | Herkunft im Gegenstands-Tooltip (Beute von, Objekte, Behälter, Händler, startet Quest; je max. 3 Namen) und Quests im NPC-Tooltip (Gegenstands- und Questnamen in der Sprache des Clients, soweit er sie kennt; annehmbar laut Daten: nicht erledigt, Stufe, Rasse, Klasse, Vorquests; Abgabe für Quests im Log) | ja |
| | Name (optional mit Nachname und Stufe) der Einheit unter der Maus mittig über dem Zeiger (Tooltip-Farbe); optional nach Gesundheit: verbleibender Anteil farbig, Rest entsättigt | ja |
| | Spieler im Tooltip: Name und Klasse in Klassenfarbe | ja |
| | Stückpreis bei Stapeln direkt hinter dem Verkaufspreis | ja |
| | Stapelgröße bei stapelbaren Gegenständen | ja |
| | Beim Lehrer: neben dem Tooltip eines Rezepts die ausgerüsteten Gegenstände des passenden Platzes (wie der Vergleich in der Tasche, eigene Vergleichs-Tooltips) | ja |
| | Scharfer Rahmen (1 Pixel, leicht abgerundete Ecken) in Qualitätsfarbe bei Gegenständen | ja |
| Minimap | Koordinaten (größer, Outline, Klassenfarbe) oben unter dem Norddreieck; verschieb- und sperrbar | – |
| | Aufspüren-Menü: Zaubersymbole (z. B. Schatzsucher) auf die sichtbare Größe der übrigen Symbole verkleinert | ja |
| Weltkarte | Unentdeckte Gebiete durchscheinend (Deckkraft einstellbar, Standard 60 %), optional leicht grün getönt; Kartenteile aus den Spieldaten, Karten mit abweichenden Daten bleiben unverändert; `/fp karte` prüft die offene Karte | ja |
| | Symbole für Instanzeingänge (Dungeons, Schlachtzüge) und Flugmeister der eigenen Fraktion und neutrale auf Gebiets- und Kontinentkarten, Gasthäuser auf Gebiets- und Stadtkarten, Namen der Orte (Gebietskarten) und Hauptstädte (Gebiets- und Kontinentkarten); alles einzeln abschaltbar, Namen per Mouseover | ja |
| | Eigene Koordinatenanzeige (Mauszeiger, Spieler) fester Größe unten links, verschieb-, skalier- und sperrbar (Position relativ zur Karte); Blizzards Anzeige wird ausgeblendet | ja |
| Gegenstände | Schrott verkaufen, reparieren (optional aus der Gildenbank) | ja |
| | Beutel-Knopf beim Händler verkauft nach denselben Regeln (behaltene graue Gegenstände bleiben), Tooltip mit Anzahl und Wert | ja |
| | Mittelklick (Maustaste 3/4/5 wählbar) oder frei belegbare Taste (Tastaturbelegung → AddOns) markiert/entmarkiert als Schrott (gelbe Münze), wird mitverkauft; alles, was verkauft wird, trägt die Münze; graue Gegenstände lassen sich so vom Verkauf ausnehmen; Liste aller Markierungen als Popup direkt am Einstellungsknopf, Klick entfernt einzeln (`/fp schrott`); Gegenstände mit Zufallssuffix („des Affen“, „des Frostschutzes“) werden einzeln markiert | ja |
| | Aufstockliste: Alt + Mittelklick setzt einen stapelbaren Gegenstand auf die Liste (kleines Taschensymbol unten links); bei der Bank (Charakter- und, falls nutzbar, Kontofächer) wird er auf einen vollen Stapel aufgefüllt, bei der Gildenbank aus dem angezeigten Fach im Rahmen der Abhebungsrechte; Liste je Charakter, als Popup in den Einstellungen | ja |
| | Schrottliste wahlweise je Charakter (beim ersten Einschalten wird die gemeinsame Liste übernommen) | ja |
| | Wertvollste Questbelohnung mit der Schrott-Münze hervorheben | ja |
| | Grüner Pfeil nur bei echter Verbesserung für Klasse und Talentbaum: beste Rüstungsart der Klasse (Kette/Platte ab Stufe 40), höherer gewichteter Wert als das schwächste getragene Teil des Platzes (Wertgewichte je Talentbaum, aus der Spielmechanik abgeleitet), verwendbar; keine Berufswerkzeuge; Pfeil oben rechts (die Schrott-Münze bleibt oben links); optional Wertung im Tooltip | ja |
| | Neuer besserer Gegenstand in den Taschen (Beute, Questbelohnung, Kauf; gleiche Wertung wie der Pfeil): Pergament-Fenster mit Symbol, ersetztem Teil und Wertung, „Anlegen“ oder „Nicht jetzt“; mehrere nacheinander, im Kampf ausgeblendet | ja |
| | Schnelles Plündern (schaltet automatisches Plündern mit ein) | ja |
| | Chatmeldungen: je Funktion abschaltbar (Verkauf, Reparatur, Markierung, Wegpunkt, Sperren); Hauptseite: alle Meldungen stumm | ja |
| | Taschen voll: billigste graue Gegenstand (Händlerwert) wird angezeigt, nur wenn er weniger wert ist als die Beute im offenen Beutefenster (Questgegenstände gehen vor), nach Bestätigung aufgenommen; Vernichten über Blizzards eigene Abfrage | ja |
| | Seelengebunden beim Aufheben automatisch bestätigen (Plündern und Würfeln) | ja |
| | Würfelfenster: Anzahl Bedarf/Gier/Passen auf den Knöpfen, Namen beim Überfahren | ja |
| Auktionshaus | Warnsymbol bei Auktionen mit Stückpreis ≤ Händlerpreis, Warnung beim Einstellen | ja |
| | Laufzeit 24 Std. je Sitzung vorgewählt (über Blizzards eigene Einstellung) | ja |
| Komfort | Eigene Seite „Mouseover“: Mikromenü, Questtracker, Taschenleiste, Aktionsleisten 1–8, Haltungs- und Begleiterleiste, Statusleisten (Erfahrung, Ruf), Spieler-, Ziel- und Fokusfenster, Minimap nur bei Mouseover (jedes Element einzeln wählbar; Aktionsleisten und Fenster standardmäßig aus), optional im Kampf immer sichtbar; dort auch EP-/Rufzahlen bei Mouseover und die ausblendenden Chatreiter | ja |
| | Gegnerische Namensplaketten nur im Kampf | ja |
| | Namensplaketten außerhalb des Kampfes transparent (Standard 70 %, einstellbar), im Kampf voll sichtbar | ja |
| | Rote Fehlermeldungen in der Bildschirmmitte ausblenden (Standard an) | ja |
| | Questtracker-Überschrift „Quests 7/25“ (angenommen/Maximum) | – |
| | Questtracker-Sortierung (Questlog, Stufe, Zone, Entfernung, Name, Fortschritt) per Knopf neben dem Zuklapp-Knopf | ja |
| | Questtracker: Klassenquests immer oben; Reiter „Welt“/„Instanz“ für Dungeon- und Schlachtzugsquests (wechselt beim Betreten einer Instanz); optional nur Quests der aktuellen Region | ja |
| | Questtracker: Maus über einem Questtitel zeigt eine Kartenvorschau mit den offenen Zielen (rote Punkte: Gegner, Gegenstandsquellen, Orte) oder dem Abgabe-NPC, dazu Ziele, weitere Gebiete und die eigene Position (Daten: QuestieDB) | ja |
| | Fehlerfenster unterdrückt, Fehler gesammelt; Tag/Nacht-Anzeige der Minimap ist der Knopf, leuchtet bei neuen Fehlern; Liste neueste zuerst; Detailfenster mit Vor/Zurück und Kopier-Symbol; Rechtsklick löscht alle Fehler, Shift-Klick lädt das Interface neu | ja |
| | Tastenbelegungs-Nummern und Makronamen auf Aktionstasten ausblenden (einzeln) | ja |
| | Neuer Zauberrang ersetzt auf den Aktionsleisten den Rang direkt darunter; bewusst gesetzte niedrigere Ränge bleiben | ja |
| | Freie/gesamte Taschenplätze am Rucksack | ja |
| | Taschen beim Öffnen mit Blizzards Aufräumfunktion sortieren (höchstens alle 3 s, nicht im Kampf/beim Schrottverkauf) | ja |
| | Nach jedem Sortieren (auch mit Blizzards Knopf) liegen markierte Gegenstände direkt neben den grauen | ja |
| | Minimap-Buttons anderer Addons ausblenden (Karten-Pins bleiben) | ja |
| | Gespielte Zeit aller Charaktere im Uhr-Tooltip (ohne Chatmeldung erfasst) | ja |
| | FPS/MS unten in der Minimap (Zahlen in Klassenfarbe); Mouseover: CPU-Zeit aller Addons (Durchschnitt der letzten Bilder, höchster Wert, Zahl der Bilder über 1 ms; grün/orange/rot nach dem höchsten Wert); verschieb- und sperrbar | ja |
| | Blizzard-Koordinaten unter der Minimap einmalig ausgeschaltet (wieder einschaltbar in den WoW-Optionen) | – |
| Gruppensuche | Dungeongruppen für 5 und 10 Spieler: Klassen der Gruppe (nach Rolle sortiert) und fehlende Rollen nach einstellbarer Aufstellung (5er: 1 Tank, 1 Heiler, 3 Schaden; 10er: einstellbar) | ja |
| Quests | Questklänge (abschaltbar) bei Questfortschritt und erledigter Quest (Peon „Arbeit abgeschlossen“ bzw. „Bereit zur Arbeit“ u. a.), Questsymbol mit Fortschritt an Namensplaketten | ja |
| | Forever-Quests (ID ab 10000) im Questlog und Tracker mit Stern vor dem Namen oder hellblau | ja |
| | Quest- und Gesprächsfenster sowie Bücher, Briefe und Schilder als Pergamentseite: ohne Rahmen, Porträt, Hintergrund, Schließen-Knopf und Bildlaufleiste; Papierschatten, Name oben; bei Büchern „Zurück“/„Weiter“ als Text und Seitenzahl unten; Knöpfe als Text unten im Pergament (z. B. „Lebt wohl“ rechts, „Annehmen“ links), weiterhin Blizzards Knöpfe; ein Pfeil unten zeigt, dass der Text weitergeht (Mausrad scrollt); Leertaste nimmt an, geht weiter oder schließt die Quest ab (nicht im Kampf; PvP-Quests, Quests mit Kosten und ungewählte Belohnungen per Mausklick, da Blizzards Bestätigungsdialoge nicht aus Addon-Code geöffnet werden), Escape schließt | ja |
| | Extra-Knopf für den Questgegenstand der nächsten Quest (in Reichweite), Bearbeitungsmodus, Tastenbelegung | ja |
| Flugzeiten | Jeder Flug wird gemessen und je Strecke gespeichert; Dauer im Tooltip der Flugkarte, Restzeit-Leiste während des Flugs (verschieb- und sperrbar) | ja |
| Erfahrung & Ruf | Zahlen immer oder nur bei Mouseover (Standard: Mouseover); EP- und Rufleiste: Prozent, Zahl und Prozent, Rest bis Stufe/Rufstufe, alles (EP inkl. Erholung, Quest-EP); EP abgabebereiter Quests (nur Quests mit Zielen, alle erfüllt) als dunkler Balkenteil | ja |
| Talente | „Zauber beim Lehrer“ (erlernte grau; künftige Zauber aus der beim Lehrerbesuch gespeicherten Liste; das Symbol funkelt, solange es Neues zu lernen gibt, bis zum nächsten Öffnen); Builds speichern, exportieren, importieren, übernehmen (Blizzard-Loadout-Format); Talentplaner als eigenes Fenster wie ein Talentrechner (`/fp talente`, „Builds“ → „Planer öffnen“, vor dem ersten Talentpunkt auch Talenttaste und Talentsymbol): alle drei Bäume nebeneinander, Linksklick plant einen Rang, Rechtsklick nimmt ihn zurück, Punkte je Baum, Gesamtpunkte und nötige Stufe, Pfeile zwischen Voraussetzungen; Regeln wie im Spiel (5 Punkte je Reihe im selben Baum, Talente hinter einem Pfeil erst mit voll ausgebautem Ausgangstalent), bis Stufe 60; der Plan erscheint in Blizzards Talentfenster als blauer Zähler, „Plan übernehmen“ merkt die Ränge vor (Bestätigung mit Blizzards Knopf); der Tooltip zeigt aktuellen und nächsten Rang | ja |
| Anprobe | Knöpfe „Ausziehen“/„Wieder anziehen“; Klick auf einen Eintrag der Vorlagenliste blendet das Teil aus/ein | – |
| Buff-Erinnerung | Klickbare Aktionstasten für fehlende Klassen-Buffs, Richtung rechts/links/oben/unten, Größe, Vorwarnzeit, leuchtet wie Blizzards Zauberhinweise, bald ablaufende Buffs blass (Deckkraft einstellbar), Zauberwahl je Gruppe (Rüstung, Aspekt, Segen, Aura, Gift …), optional Buffen per Mausrad (Kamera-Zoom solange aus, Shift + Mausrad blättert weiter), in Ruhezonen standardmäßig aus; ausgeblendet, solange Mana, Wut oder Energie für den Zauber fehlen; Talent-Buffs erscheinen, sobald gelernt; verschiebbar im Bearbeitungsmodus | ja |
| Optik | Qualitätsrahmen (2 Pixel, leicht runde Ecken, wie beim Tooltip) auf Gegenstandsknöpfen ab „Ungewöhnlich“; runde Knöpfe (Berufe) behalten Blizzards runden Ring | – |
| | iSquidMod-Endkappen (mit Autorenangabe) | ja |
| | Aktionstasten: außer Reichweite rot, kein Mana blau, nicht verwendbar grau, aktive Selbstbuffs (Siegel, Aspekte, Rüstungen, Schilde) entsättigt, je Zauber abschaltbar (einzeln) | ja |
| | Drache um das eigene Porträt: Gold, Silber, Bronze, jeweils mit/ohne Flügel; am Porträt ausgerichtet, Größe einstellbar | ja |
| | Buff-Symbole, Questgegenstände im Questtracker und Questbelohnungen mit Aktionstasten-Rahmen und abgerundeten Ecken (Stil: freistehend/Aktionsleiste) | ja |
| | Erfahrungs-, Ruf- und Tooltip-Gesundheitsleiste mit der Leistentextur der Einheitenfenster | ja |
| | Outline für alle Schriften (bereits umrandete werden übersprungen; dunkle Schrift auf Pergament – Quests, Gespräche, Bücher, Zauberbuch – bleibt ohne) | – |
| Schrift | Globale Schriftart und -größe; je Gruppe (klein, normal, Überschriften, Zahlen, Tooltip, Questtext, Chat) eigene Schriftart und Größe; Schriften aus SharedMedia (LibSharedMedia-3.0) werden angeboten | ja |
| Helfer | Alt: verarbeitbare Taschengegenstände leuchten (lila Entzaubern, gelb Schlossknacken), Alt + Rechtsklick führt es aus | ja |
| | Knopf für öffnbare Gegenstände (Muscheln, Beutel, geknackte Kassetten), Bearbeitungsmodus | ja |
| | Doppel-Rechtsklick in die Welt wirft die Angel aus | ja |
| | Bereits bekannte Rezepte in Taschen und beim Händler ausgegraut | ja |
| Rezeptradar | Händler mit unbekannten Rezepten deiner Berufe auf Welt- und/oder Minimap; Klick setzt Wegpunkt; NPCs ohne festen Ort (in mehr als drei Zonen gesehen, z. B. der beschwörbare Reagent Bot) zählen nicht als Händler | ja |
| | Rezeptquellen im Tooltip: Händler + Zone, Quests, Anzahl droppender Gegner | ja |
| Fenster | Anfangs gesperrt; Alt + Rechtsklick entsperrt, dann verschiebt Alt + Ziehen jedes Fenster und jede ForeverPlus-Anzeige, Strg + Mausrad skaliert; Position/Größe je Element gespeichert, als Abstand zur nächsten Ecke, Kante oder Mitte (bei Minimap-Anzeigen zur Minimap), damit Auflösung und UI-Skalierung nichts verschieben | ja |
| | Mehrere Fenster gleichzeitig offen (z. B. Taschen + Charakter + Händler); nicht verschobene Fenster reihen sich rechts neben Blizzards Fenster (z. B. Zauberbuch) | ja |

## Technik / CPU

- Nur offizielle API des Forever-Clients (geprüft gegen den Blizzard-UI-Quellcode, Branch `forever`, Build 1.60.1.70205).
- Ausschließlich `hooksecurefunc`/`HookScript`, `TooltipDataProcessor`, Settings-API, `EventRegistry` (Bearbeitungsmodus) – keine Ersetzung von Blizzard-Funktionen.
- Ereignisse werden nur registriert, solange eine Funktion aktiv ist. Dauerhafte `OnUpdate`-Schleifen gibt es nur für das Mouseover-Ausblenden (Prüfung alle 0,1 s, Überblendung nur während des Übergangs). Koordinaten und Minimap-Pins aktualisieren nur während der Bewegung, der Skalierungs-Fänger nur bei gedrückter Strg-Taste.
- Lua-Fehler werden aus Blizzards eigenem `ScriptErrorsFrame` gelesen (kein eigener Error-Handler); das Popup wird über die CVar `scriptErrors` unterdrückt und beim Deaktivieren wiederhergestellt.

## Bekannte Grenzen / ungeprüft

- Kein Test im laufenden Spiel möglich gewesen; geprüft wurden Syntax, `luacheck`, ein Lade-/Initialisierungstest mit simulierter API sowie alle verwendeten Funktionen gegen den Forever-UI-Quellcode.
- Buff-Erinnerung nutzt Classic-Zauber-IDs; nicht existierende IDs werden still übersprungen.
- „Mehrere Fenster gleichzeitig“ gilt nicht für Spielmenü, Optionen, Zauberbuch, Sammlungen, Dungeonbrowser und geschützte Fenster: deren Anzeige über Addon-Werte zu steuern würde Abmelden/Beenden bzw. Kampfaktionen blockieren (Taint).
- Kopieren in die Zwischenablage ist für Addons gesperrt (`CopyToClipboard` ist eingeschränkt); das Kopier-Symbol markiert den Text, kopiert wird mit Strg+C.
- Schrift: Namen über Köpfen und Kampftext nutzen vom Client beim Start gelesene globale Schriftpfade; diese zu ändern würde Taint riskieren, daher nicht enthalten.
- Auktionshaus: keine zusätzlichen Kategorien/Filter. Kaufen und Einstellen (`PlaceBid`, `PostItem`, …) sind eingeschränkte Funktionen; ob Änderungen an Blizzards Suchlogik sie blockieren, ist ohne Test im Spiel nicht verifizierbar. Die Warnung liest nur Daten und fügt eigene Symbole hinzu.
- Vernichten (`DeleteCursorItem`) ist für Addons gesperrt; deshalb wird der Gegenstand nur aufgenommen und über Blizzards Abfrage vernichtet.
- Sprachwechsel per Mittelklick: setzt die Sprache mit demselben Aufruf wie Blizzards Menü, der Wert stammt aber aus Addon-Code. `SendChatMessage` ist eingeschränkt; ob das Senden in Instanzen dadurch blockiert wird, ist ohne Test nicht verifizierbar. Abschaltbar.
- Talentplaner: eigenes Fenster statt Blizzards Talentfenster, weil das Öffnen von Blizzards Fenster aus Addon-Code die Aktionsleisten „verseucht“ (Taint; Folge waren `ADDON_ACTION_BLOCKED`-Fehler bei `SetShown` von Aktionstasten im Kampf).
- Zeit bis zum Tod ist nicht möglich: `UnitHealth` liefert Addons laut Forever-API-Doku immer einen geschützten Wert (`SecretReturns`), mit dem Lua nicht rechnen kann; das Kampflog ist eingeschränkt. Anzeigen geht trotzdem: die Namensfärbung nach Gesundheit schiebt den geschützten Wert in einen unsichtbaren Statusbalken, an dessen Füllung ein Clipping-Rahmen hängt (keine Rechnung in Lua). Im Spiel ungeprüft.
- Flugzeiten: Daten entstehen erst durch eigene Flüge (keine mitgelieferte Datenbank).
- Peon-Klänge: Datei-IDs 558132 (`peonbuildingcomplete1.ogg`) und 558137 (`peonready1.ogg`) laut Community-Listfile; ob der Forever-Client sie enthält, ist ungeprüft. Fehlt eine Datei, ertönt ein Blizzard-Klang.
- Questtracker-Sortierung: Blizzards Tracker zeigt beobachtete Quests in Beobachtungsreihenfolge und sortiert bei Zonenwechsel selbst nach Nähe; ForeverPlus fügt die Beobachtungen danach in der gewählten Reihenfolge neu hinzu. Ob neue Beobachtungen oben oder unten landen, wird beim ersten Sortieren erkannt.
- Das `ADDON_ACTION_FORBIDDEN`-Popup wird nur protokolliert, nicht unterdrückt (Unterdrücken würde StaticPopups tainten).

- Angeln per Doppel-Rechtsklick: nur mit angelegter Angel; erst nach dem Loslassen eines kurzen, ruhigen Rechtsklicks wird die rechte Maustaste für 0,4 s mit einem sicheren Knopf belegt. Kamera drehen (Rechtsklick halten) und Rechtsklick-Interaktion bleiben unberührt.
- Talentbaum für den Upgrade-Pfeil: Forever hat je Klasse nur eine Spezialisierung (`C_SpecializationInfo`); die drei klassischen Talentbäume sind Trait-Gruppen. Gewertet wird nach dem Baum mit den meisten Punkten, ohne Punkte nach einem Standardbaum (Krieger Waffen, Paladin Vergeltung, Schamane Verstärkung, Priester Schatten, Druide Gleichgewicht). Schamanen und Paladine zählen in Zauber- und Heilerbäumen bis Stufe 20 die Waffen-DPS voll, bis Stufe 40 abnehmend (Nahkampf beim Leveln). Fehlt die DPS in den Gegenstandswerten, wird sie aus der Tooltipzeile gelesen.
- Eigene Minimap-Symbole (wie Blipstick): nicht möglich. Solche Addons tauschen die Symboltextur mit `Minimap:SetBlipTexture`; die Minimap-API des Forever-Clients (1.60.1) enthält diese Funktion nicht mehr, nur `SetIconScale`. Die Positionen verfolgter Erze, Kräuter und NPCs sind für Addons nicht abfragbar, eigene Symbole lassen sich also auch nicht darüberlegen.
- Gruppensuche: Rollen sind die in der Gruppe zugewiesenen Rollen; Mitglieder ohne Rolle werden gezählt, aber keiner Rolle zugerechnet. Eigene Ausschreibungen behalten Blizzards Anzeige (dort liegt der Knopf zum Austragen).
- Interface-Fehler: optionaler Hinweisklang bei neuem Fehler (höchstens alle 5 s; Fehler von vor dem Laden lösen keinen Klang aus).
- Porträt-Drache: gespiegelt mit `SetTexCoord(1, 0, 0, 1)` wie in BetterBlizzFrames (Forever-Version); die vorher verwendeten absoluten Atlas-Koordinaten zeigten nur Ausschnitte. Größen und Positionen nach BetterBlizzFrames, kein Code übernommen.
- Große einmalige Durchläufe (Instanznamen aus 2500 Karten, QuestieDB-Questketten, Rezeptradar-Index) laufen in Scheiben von höchstens 0,8 ms pro Bild. Mittelklick oder Shift-Klick auf die FPS/MS-Anzeige misst ForeverPlus 30 Sekunden lang; das Ergebnis steht im Chat und im Tooltip der Anzeige. `/fp messen` misst danach alle Ereignisaufrufe sowie Taschen-, Tooltip-, Questlog- und Tracker-Aufrufe; ein zweites `/fp messen` zeigt die längsten Aufrufe. Einmalige Arbeit beim Laden (Initialisierung, Einstellungen, Login) wird immer gemessen, `/fp zeiten` zeigt den Stand ohne Neustart der Messung.
- Chatfilter laufen über Blizzards Filterliste (`ChatFrameUtil.AddMessageEventFilter`), die Addon-Filter abgeschirmt aufruft und geschützte Nachrichten gar nicht erst übergibt; solche Nachrichten bleiben unverändert.
- Kanalkürzel: Blizzards Chatcode verlangt die Kanalnummer vor dem Namen und vergleicht die Länge des Kanaltexts mit den beigetretenen Kanälen; die Nummer bleibt deshalb, und der Kurzname wird mit unsichtbaren `|r` auf die ursprüngliche Länge aufgefüllt.
- Zeitstempelfarbe: der Farbcode steht im Zeitstempelformat (CVar `showTimestamps`). Blizzards Auswahlfeld unter Soziales enthält nur die ungefärbten Formate; eine neue Auswahl dort wird sofort wieder eingefärbt. Ausschalten stellt das ungefärbte Format her; wird ForeverPlus ohne Ausschalten entfernt, bleibt der Farbcode im Format.
- Beute-Herkunft: angeklickte tote Einheit, sonst Ziel eines Zaubers bis 6 s vor dem Plündern (Kräuter, Erz, Kürschnern, Angeln), sonst geöffneter Taschengegenstand (bis 2 s), sonst totes Ziel; sonst „Unbekannt“; Hergestelltes als „Hergestellt“. Geldanteile aus fremden Beutefenstern stehen als „Anteil der Gruppe“. Die Listen gelten bis zum Ausloggen (die letzten 20).
- Questvorschau im Tracker: Ziele werden QuestieDB-Einträgen je Zieltyp in der Reihenfolge des Questlogs zugeordnet (Gegner inklusive Kill-Credit, Objekte, Gegenstände mit bis zu 12 Beute-NPCs/-Objekten, Erkundungsorte); höchstens 150 Punkte je Karte. Gezeigt wird die Karte des Spielers, wenn sie Ziele enthält, sonst die mit den meisten Punkten. Im Spiel ungeprüft.
- Weltkarten-Symbole: Blizzards Karte zeigt auf Forever weder Flugpunkte (keine Karte trägt in den Spieldaten das Kennzeichen `ShowTaxiNodes`) noch Instanzeingänge. Gezeigt werden die Instanzen der Gruppensuche (`Data/Instances.lua`, erzeugt mit `tools/instances.py` aus `GroupFinderActivity`, Build 1.60.1.70291) mit Eingangsposition aus QuestieDB; neue Forever-Instanzen ohne Position in QuestieDB (laut Spieldaten „Excavation Site: Wetlands“, „Ruins of Lordaeron“, „Hall of Thanes“, „City of Dalaran“) fehlen deshalb. Flugmeister: QuestieDB-NPCs mit Flugmeister-Kennzeichen (Bit 8). Namen der Instanzen aus dem Client, der Flugmeister aus QuestieDB. Gasthäuser: QuestieDB-NPCs mit Gastwirt-Kennzeichen (Bit 128) und dem Grundtitel „Innkeeper“ (das Kennzeichen tragen in den Daten auch einige Reittierhändler). Orts- und Städtenamen: Ortsmarken der Spieldaten (`AreaPOI`; Orte wie Goldhain, Hauptstädte wie Sturmwind), Weltposition über `C_Map.GetMapPosFromWorldPos` auf die Karte umgerechnet, Namen über die Gebiets-ID in der Sprache des Spiels. Zu welcher Karte ein Ort gehört, ergibt sich aus seinen übergeordneten Gebieten (`AreaTable`, `UiMapAssignment`); Dun Algaz hat keines und wird nach Lage dem Sumpfland zugeordnet (`Data/Places.lua`, erzeugt mit `tools/places.py`). Alle Symbole und die Rezepthändler des Rezeptradars liegen auf eigenen Rahmen über der Karte statt in Blizzards Pin-System: Pins, die Addon-Code anlegt, setzen geschützte Maus-Einstellungen (`SetPassThroughButtons`), die im Kampf blockiert werden. Im Spiel ungeprüft.
- Weltkarte: Der Client nennt Addons nur die entdeckten Kartenteile. Alle Teile stehen in `Data/MapOverlays.lua`, erzeugt mit `tools/mapoverlays.py` aus den Spieldaten-Tabellen `WorldMapOverlay` und `WorldMapOverlayTile` (Build 1.60.1.70291, CSV von wago.tools). Meldet der Client ein entdecktes Teil, das in den Daten fehlt (andere Kartenversion), bleibt die Karte unverändert. Nur die erste Kartenebene; im Spiel ungeprüft.
- Bekannte Rezepte im Auktionshaus werden nicht ausgegraut (Blizzards Tooltip zeigt dort weiterhin „Bereits bekannt“).

- Instanzquests: mit QuestieDB Quests, deren Questzone eine Instanz aus QuestieDBs Dungeon-Tabelle ist, und (Option) Quests, die über `nextQuestInChain`, `preQuestSingle`/`preQuestGroup` oder Brotkrumen-Verweise zu einer solchen führen. Zusätzlich und ohne QuestieDB: Quests unter dem Namen einer Instanz im Questlog (Namen aus den Dungeon-Karten von `C_Map`) oder mit Quest-Tag Dungeon/Schlachtzug.
- Reiter und Regionsfilter arbeiten über die Beobachtungsliste: ForeverPlus merkt sich je Charakter, welche Quests du verfolgst, und blendet nicht passende aus der Liste aus (sie bleiben vorgemerkt).

## Danksagungen / Lizenzen

- Code: MIT (siehe `LICENSE`).
- iSquidMod-Grafiken (`Media/iSquidMod`): Ganders & Imithat, Originalautor SAM – WML 1.0, siehe `Media/iSquidMod/LICENSE.txt`.
- Quest-, NPC-, Gegenstands- und Rezeptdaten (Rezeptradar, Herkunft im Tooltip, Quests am NPC, Instanz-Vorquests; daraus auch die ID-Grenze der Forever-Quests): zur Laufzeit aus [QuestieDB](https://github.com/Questie/QuestieDB) (Questie-Team), im Paket enthalten. Gedacht ist das Release-Paket `QuestieDB-Forever.zip` aus den QuestieDB-Releases. Der Quellcode (Git-Checkout) läuft im „Source Mode“: langsamer, ohne übersetzte Namen; dessen Hinweis am oberen Bildschirmrand blendet ForeverPlus aus.
- Kartenteile der Weltkarte, Instanzliste, Orts- und Städtenamen: Blizzards Spieldaten (`WorldMapOverlay`, `WorldMapOverlayTile`, `GroupFinderActivity`, `AreaPOI`, `AreaTable`, `UiMapAssignment`), bezogen über [wago.tools](https://wago.tools).
- Ideen: oGlow (haste), Leatrix Plus, Leatrix Maps (unentdeckte Gebiete), BlizzMove, RecipeRadar, Questie/Quester/Plumber, ncHoverName, ExtraQuestButton.
