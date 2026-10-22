local _, ns = ...

-- The text of every string the addon shows. The English text is the key, so a string with no
-- translation (or any string on an English client) simply reads as written. Locales/<code>.lua adds the
-- translations for one client language; they load before any code that uses `L`.
ns.L = setmetatable({}, { __index = function(_, key) return key end })
