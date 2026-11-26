# LinearizedTreeDataProviderMixin: Cache bei `Remove(node, true)`

**Falle:** `CreateTreeDataProvider()` liefert `LinearizedTreeDataProviderMixin` (`Blizzard_SharedXML/TreeListDataProvider.lua`), das alle ausgeklappten Knoten in `self.linearized` zwischenspeichert. `GetSize(true)` und `Enumerate(..., true)` – also alles, was `ScrollBoxListTreeListViewMixin` für Anzeige, Layout und Auswahl liest – greifen auf diesen Cache zu. `self.linearized` wird nur in `Invalidate()` und `Flush()` geleert.

Ruft Addon-Code innerhalb eines gebündelten Updates ausschließlich `node:Remove(child, true)` (`skipInvalidation = true`) ohne anschließendes `Insert` oder `provider:Invalidate()` auf, zeigt `view:DataProviderContentsChanged()` danach weiter den alten, ungefilterten Cache an.

**Beispiel (behoben):** `ProfessionPlan` → `FilterMaterialRows` („Mindestens eine Zutat vorhanden“) entfernte nicht passende Kategorien und Rezepte per `parent:Remove(node, true)` in `BatchListChanges`. Weil danach kein `Insert` folgte, blieb `provider.linearized` unverändert und die Rezeptliste im Berufsfenster filterte sichtbar nicht.

**Regel:** Nach gebündelten Baumänderungen mit `skipInvalidation = true` immer `provider:Invalidate()` aufrufen, bevor die View-Callbacks wieder angehängt werden und `view:DataProviderContentsChanged()` die `ScrollBox` neu zeichnet. In Tests den `LinearizedTreeDataProviderMixin`-Cache (`self.linearized` für `excludeCollapsed = true`) mit abbilden.
