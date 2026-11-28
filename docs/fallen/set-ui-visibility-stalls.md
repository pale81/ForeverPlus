# `SetUIVisibility(false/true)` verursacht 20–60 ms Frame-Ruckler

**Falle:** `SetUIVisibility(false)` und `SetUIVisibility(true)` schalten `UIParent` vollständig um und lösen im Forever-Client `OnHide`/`OnShow`, Layout-Invalidierung und Neuaufbau für den gesamten UI-Baum aus. Jeder Umschaltvorgang kostet im Spiel typisch 20–60 ms in einem einzelnen Frame. Zudem kollidiert ein fremdes `SetUIVisibility(false)` mit Wanderlusts Soft-Hide (`UIParent:OnHide` wertet es als `Alt+Z`).

**Beispiele (behoben):**
- `Wanderlust` (`fdb8a6a`, `b7194a6`): beim Einblenden und Minimap-Mouseover entstanden 30–60 ms Hänger → auf sanftes Ausblenden über Transparenz (`SetAlpha(0)` auf sichtbaren direkten `UIParent`-Kindern + `Minimap:Hide()` gegen Spiel-Blips) umgestellt.
- `Helpers` (`fishingHideUI`): `RefreshFishingPresentation` rief bei jedem Auswerfen und Einholen `SetUIVisibility(false/true)` auf (im Spiel gemessen: 6–50 ms pro Aufruf) → nutzt jetzt den gemeinsamen Soft-Hide-Mechanismus über `Wanderlust.SetFishingHidden`, entprellt mehrfache Kanalereignisse im selben Bild und koordiniert `QoL`, `PortraitModes` und `ChatMinimize`.

**Regel:** Für wiederkehrendes automatisches Ausblenden der Oberfläche nicht `SetUIVisibility` aufrufen, sondern die gemeinsame Soft-Hide-Schicht in `Modules/Wanderlust.lua` nutzen, damit Original-Alphas bei Überlagerungen (z. B. Wanderlust + Angeln) erhalten bleiben und `UIParent` sichtbar bleibt.
