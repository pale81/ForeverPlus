-- Zeppelin and boat rides known to ship with ForeverPlus. Empty until players'
-- recordings are merged in with an update (/fp daten export shows the lines
-- to send in). Each entry is one ride:
-- { from map ID, x, y, to map ID, x, y, seconds }   (x, y: 0–1 on the zone map)
local _, ns = ...

ns.TransportRoutes = {}
