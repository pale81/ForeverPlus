# Eingesandte Funde

Hier liegen die Exporte (`/fp daten export`) der Spieler, eine Datei je Beitragender (`<GitHub-Name>.txt`);
ein neuer Export ersetzt den alten, weil das Addon immer alles bisher Aufgezeichnete ausgibt.

Einsenden: im Spiel `/fp daten export`, Text kopieren, im Formular „Daten einsenden“ des Projekts einfügen
(Link in der ersten Zeile des Exports).

Ein Workflow (`.github/workflows/data.yml`) legt aus jedem Beitrag einen Pull Request mit `contrib/<GitHub-Name>.txt` an
(Voraussetzung: in den Einstellungen des Projekts unter Actions → General „Allow GitHub Actions to create and approve pull
requests“ einschalten). Zusammengeführt wird nach Durchsicht.

Einrechnen:

```
python3 -I tools/contrib.py                       # was in den Dateien steht
python3 -I tools/build_eg.py <Efficient-Games-Checkout>   # Beute, Gasthäuser, Questdaten, Fahrten neu erzeugen
```

Was eingerechnet wird: Beutefenster (Zähler werden addiert), Gastwirte (die Lage, auf die sich die meisten einigen),
NPC-Quests, Fundorte von Questzielen und Kreaturen, Fahrten (mittlere Zeit je Strecke). Namen aus jedem Client: englische gehen vor, andere füllen die Lücken (die Beta ist noch nicht ganz übersetzt).
Bücher werden gelesen, aber noch nicht eingerechnet (`Data/Library.lua` ist von Hand gepflegt).
Obergrenzen je Eintrag und Beitragendem stehen in `tools/contrib.py`.
