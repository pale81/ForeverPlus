# Taint über Blizzard-Zustand, den Addon-Code anlegt

**Falle:** Blizzard-Funktionen, die beim ersten Aufruf internen Zustand anlegen oder zwischenspeichern, verunreinigen
diesen Zustand dauerhaft (bis `/reload`), wenn der erste Aufruf aus Addon-Code kommt. Jede spätere Blizzard-Ausführung,
die ihn liest, läuft mit Taint, und geschützte Aufrufe werden blockiert, ohne dass ForeverPlus im Aufrufweg auftaucht.

**Beispiel (behoben, e1068ac):** Wanderlust rief beim Login und jede Sekunde `IsAnyBagOpen()` auf.
`IsBagOpen` → `ContainerFrameUtil_GetShownFrameForID` → `ContainerFrameUtil_EnumerateContainerFrames` legt die lokale
Liste `containerFrames` erst beim ersten Aufruf an (nach `VARIABLES_LOADED` zurückgesetzt). Danach lief jedes Öffnen der
Bank (`OnShow` → `OpenAllBags` → `IsAnyBagOpen`) verunreinigt: `BankPanel.bankType` → Kauf-Popup → `ADDON_ACTION_FORBIDDEN: PurchaseBankTab()`.

**Regel:** Aus Addon-Code keine Blizzard-Hilfsfunktionen mit verstecktem Zustand aufrufen (Taschen: `IsAnyBagOpen`,
`IsBagOpen`, `OpenBag`/`ToggleBag`, `ContainerFrameUtil_*`, `ContainerFrameSettingsManager:*`; Popups: `StaticPopup_Show/Hide`;
Fenster: `ShowUIPanel`/`HideUIPanel` für verwaltete Fenster). Stattdessen die Frames selbst lesen (`frame:IsShown()`),
z. B. `ContainerFrameCombinedBags` und `ContainerFrameContainer.ContainerFrames`.

**Diagnose im Spiel (statt raten):**
1. `/console taintLog 2`, `/reload`, Fehler auslösen, `/console taintLog 0`; `Logs/taint.log` zeigt den ersten
   verunreinigten Lesezugriff (nur Globale werden einzeln protokolliert, Felder/Upvalues nicht).
2. Felder prüfen: `/run print(issecurevariable(<Tabelle>, "<Feld>"))` → `false ForeverPlus` = mit Taint geschrieben.
   Felder entlang des Blizzard-Ablaufs eingrenzen (Taint klebt ab dem ersten verunreinigten Lesen an der Ausführung).
3. Aufrufweg: `/run hooksecurefunc(<Objekt>, "<Methode>", function() print(debugstack(2,20,0)) end)`.
