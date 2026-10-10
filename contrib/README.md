# Eingesandte Funde

Hier liegen die Exporte (`/fp daten export`) der Spieler, eine Datei je Beitragender (`<GitHub-Name>.txt`);
ein neuer Export ersetzt den alten, weil das Addon immer alles bisher Aufgezeichnete ausgibt.

Einsenden: im Spiel `/fp daten export`, Text kopieren, im Formular „Daten einsenden“ des Projekts einfügen
(Link in der ersten Zeile des Exports).

Einrechnen (der Text aus dem Issue kommt nach Durchsicht als `contrib/<GitHub-Name>.txt` ins Projekt):

```
python3 -I tools/contrib.py                       # was in den Dateien steht
python3 -I tools/build_eg.py <Efficient-Games-Checkout>   # Beute, Gasthäuser, Questdaten, Fahrten neu erzeugen
```

Was eingerechnet wird: Beutefenster (Zähler werden addiert), Gastwirte (die Lage, auf die sich die meisten einigen),
NPC-Quests, Fundorte von Questzielen und Kreaturen, Fahrten (mittlere Zeit je Strecke). Namen nur aus englischen Clients.
Bücher werden gelesen, aber noch nicht eingerechnet (`Data/Library.lua` ist von Hand gepflegt).
Obergrenzen je Eintrag und Beitragendem stehen in `tools/contrib.py`.
