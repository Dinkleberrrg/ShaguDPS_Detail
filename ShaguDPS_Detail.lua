--[[
    ShaguDPS Details
    ---------------------------------------------------------------------------
    ShaguDPS speichert pro Zauber nur die Summe. Fuer Anzahl, Mittelwert,
    Maximum, Crit-Quote und die Ziele fehlt die Datenhaltung - dieses Addon
    legt sie daneben an, ohne ShaguDPS anzufassen.

    Zwei Einhaengepunkte:
      * parser.AddData  - liefert Quelle, Zauber, Ziel, Wert, Schule, Typ
      * parser OnEvent  - die Crit-Information wirft AddData weg, deshalb wird
                          die Rohmeldung vorher gegen die Crit-Muster geprueft

    Bedienung: Klick auf einen Balken im Meter, oder /sdd

    Lua 5.0 / WoW 1.12: kein #, kein string.gmatch, kein select.
]]

local ADDON = "ShaguDPS_Detail"
local FONT = "Fonts\\FRIZQT__.TTF"

local ROWS = 14
local ROWH = 14
local WIDTH = 430

-- Spaltenpositionen, gemessen vom linken Rand der Zeile
local COL = {
    name  = { x = 4,   w = 168, just = "LEFT"  },
    count = { x = 176, w = 38,  just = "RIGHT" },
    avg   = { x = 216, w = 54,  just = "RIGHT" },
    max   = { x = 272, w = 54,  just = "RIGHT" },
    sum   = { x = 328, w = 62,  just = "RIGHT" },
    pct   = { x = 392, w = 34,  just = "RIGHT" },
}

local CLASSTOKENS = {
    WARRIOR = true, MAGE = true, ROGUE = true, DRUID = true, HUNTER = true,
    SHAMAN = true, PRIEST = true, WARLOCK = true, PALADIN = true,
    __other__ = true,
}

local DEFAULTS = {
    crits = 1,   -- Crit-Erkennung mitlaufen lassen
    short = 1,   -- grosse Zahlen kuerzen
}

local backdrop = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    tile = false, tileSize = 0, edgeSize = 1,
    insets = { left = -1, right = -1, top = -1, bottom = -1 },
}

local function Msg(text)
    DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00Shagu|cffffffffDPS |cff888888Details:|r " .. text)
end

-- ------------------------------------------------------------------ Config

local cfg

local function LoadConfig()
    if not ShaguDPS_Detail_Config then ShaguDPS_Detail_Config = {} end
    cfg = ShaguDPS_Detail_Config
    local k, v
    for k, v in pairs(DEFAULTS) do
        if cfg[k] == nil then cfg[k] = v end
    end
end

-- Schriftgroesse und Deckkraft vom Skin uebernehmen, falls installiert
local function SkinValue(key, fallback)
    if ShaguDPS_UI_Config and ShaguDPS_UI_Config[key] ~= nil then
        return ShaguDPS_UI_Config[key]
    end
    return fallback
end

local OUTLINES = { none = "", thin = "THINOUTLINE", thick = "OUTLINE" }

local function FontSize() return SkinValue("fontsize", 11) end
local function Outline() return OUTLINES[SkinValue("outline", "thin")] or "THINOUTLINE" end
local function BgAlpha() return SkinValue("bgalpha", 0.75) end

-- ------------------------------------------------------------------ Zahlen

local function Num(n)
    if not n then return "-" end
    if cfg.short == 1 then
        if n >= 1000000 then return string.format("%.2fM", n / 1000000) end
        if n >= 10000 then return string.format("%.1fk", n / 1000) end
    end
    return string.format("%d", math.floor(n + 0.5))
end

-- ------------------------------------------------------------------ Ablage

-- store[datatype][segment][source][action] = {
--   n, sum, min, max, crit, targets = { [ziel] = { n = , sum = } }
-- }
local store = {
    damage = { [0] = {}, [1] = {} },
    heal   = { [0] = {}, [1] = {} },
}

local function WipeSegment(seg)
    store.damage[seg] = {}
    store.heal[seg] = {}
end

local function WipeSegmentType(datatype, seg)
    store[datatype][seg] = {}
end

local function Bucket(datatype, seg, source, action)
    local segdata = store[datatype][seg]
    if not segdata[source] then segdata[source] = {} end
    if not segdata[source][action] then
        segdata[source][action] = { n = 0, sum = 0, min = nil, max = nil, crit = 0, targets = {} }
    end
    return segdata[source][action]
end

local function Record(datatype, source, action, target, value, isCrit)
    local seg
    for seg = 0, 1 do
        local b = Bucket(datatype, seg, source, action)
        b.n = b.n + 1
        b.sum = b.sum + value
        if not b.min or value < b.min then b.min = value end
        if not b.max or value > b.max then b.max = value end
        if isCrit then b.crit = b.crit + 1 end

        if target and target ~= "" then
            if not b.targets[target] then b.targets[target] = { n = 0, sum = 0 } end
            b.targets[target].n = b.targets[target].n + 1
            b.targets[target].sum = b.targets[target].sum + value
        end
    end
end

-- ------------------------------------------------------------------ Crits

-- AddData bekommt kein Crit-Flag. Die Rohmeldung wird deshalb vor dem
-- eigentlichen Parser gegen die Crit-Muster des Clients geprueft. sanitize()
-- ist eine globale Funktion aus ShaguDPS' parser-vanilla.lua, wir benutzen
-- dieselbe Umwandlung und denselben Cache.
local critPatterns = {}
local pendingCrit = nil

local function BuildCritPatterns()
    if not sanitize then return end
    local names = {
        "COMBATHITCRITSELFOTHER", "COMBATHITCRITSCHOOLSELFOTHER",
        "COMBATHITCRITOTHEROTHER", "COMBATHITCRITSCHOOLOTHEROTHER",
        "COMBATHITCRITOTHERSELF", "COMBATHITCRITSCHOOLOTHERSELF",
        "SPELLLOGCRITSELFSELF", "SPELLLOGCRITSCHOOLSELFSELF",
        "SPELLLOGCRITSELFOTHER", "SPELLLOGCRITSCHOOLSELFOTHER",
        "SPELLLOGCRITOTHERSELF", "SPELLLOGCRITSCHOOLOTHERSELF",
        "SPELLLOGCRITOTHEROTHER", "SPELLLOGCRITSCHOOLOTHEROTHER",
        "HEALEDCRITSELFSELF", "HEALEDCRITSELFOTHER",
        "HEALEDCRITOTHERSELF", "HEALEDCRITOTHEROTHER",
    }
    local i
    for i = 1, table.getn(names) do
        local raw = getglobal(names[i])
        if raw then table.insert(critPatterns, sanitize(raw)) end
    end
end

local function LooksLikeCrit(msg)
    if not msg then return nil end
    local i
    for i = 1, table.getn(critPatterns) do
        if string.find(msg, critPatterns[i]) then return true end
    end
    return nil
end

-- ------------------------------------------------------------------ Hooks

-- Pro Datentyp gemerkt: ShaguDPS legt bei Kampfbeginn neue Tabellen an, und
-- damage und heal haben getrennte. Mit nur einem Merker wuerde jeder Wechsel
-- zwischen den beiden faelschlich als Segmentwechsel gelten.
local lastCurrentRef = { damage = nil, heal = nil }

local function InstallHooks()
    local parser = ShaguDPS.parser

    -- Crit-Erkennung vor dem Parser
    local origEvent = parser:GetScript("OnEvent")
    parser:SetScript("OnEvent", function()
        if cfg.crits == 1 then
            pendingCrit = LooksLikeCrit(arg1)
        else
            pendingCrit = nil
        end
        if origEvent then origEvent() end
        pendingCrit = nil
    end)

    -- Datenaufnahme
    local origAdd = parser.AddData
    parser.AddData = function(self, source, action, target, value, school, datatype)
        local wasCrit = pendingCrit
        origAdd(self, source, action, target, value, school, datatype)

        -- dieselben Ausschluesse wie im Original
        if type(source) ~= "string" then return end
        local num = tonumber(value)
        if not num then return end
        if datatype == "damage" and source == target then return end
        if not store[datatype] then return end

        source = string.gsub(source, "^%s*(.-)%s*$", "%1")

        -- ShaguDPS hat den Eintrag verworfen (unbekannte Einheit)
        local classes = ShaguDPS.data.classes
        if not classes[source] then return end

        -- Pets genau wie ShaguDPS in den Besitzer einrechnen, damit die
        -- Detailansicht zu dem passt, was der Balken anzeigt
        if ShaguDPS.config.merge_pets == 1 then
            local owner = classes[source]
            if owner and not CLASSTOKENS[owner] then
                action = "Pet: " .. source
                source = owner
            end
        end

        -- Segmentwechsel: ShaguDPS legt bei Kampfbeginn neue Tabellen an
        if ShaguDPS.data[datatype][1] ~= lastCurrentRef[datatype] then
            lastCurrentRef[datatype] = ShaguDPS.data[datatype][1]
            WipeSegmentType(datatype, 1)
        end

        Record(datatype, source, action, target, num, wasCrit)
    end
end

-- ------------------------------------------------------------------ Fenster

-- Farbcode der Klasse, damit der Name in der Kopfzeile dieselbe Farbe hat
-- wie der Balken im Meter. Bei Pets steht in classes der Besitzername, dann
-- wird dessen Klasse genommen.
local function ClassColorCode(name)
    if not name or not ShaguDPS.data or not ShaguDPS.data.classes then return "|cffffffff" end
    local class = ShaguDPS.data.classes[name]
    if class and not CLASSTOKENS[class] then
        class = ShaguDPS.data.classes[class]
    end
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if not c then return "|cffffffff" end
    return string.format("|cff%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255)
end

local frame
local expanded = {}   -- [zaubername] = true
local current = { unit = nil, datatype = "damage", segment = 1 }
local scroll = 0

local function SortedPairs(t, cmp)
    local keys, n = {}, 0
    local k, v
    for k, v in pairs(t) do
        n = n + 1
        keys[n] = k
    end
    table.sort(keys, function(a, b) return cmp(t, a, b) end)
    local i = 0
    return function()
        i = i + 1
        if keys[i] then return keys[i], t[keys[i]] end
    end
end

-- Sichtbare Zeilen aufbauen: Zauber, darunter bei Bedarf die Ziele
local function BuildList()
    local list = {}
    if not current.unit then return list end

    local segdata = store[current.datatype][current.segment]
    local unitdata = segdata and segdata[current.unit]
    if not unitdata then return list end

    local total = 0
    local action, b
    for action, b in pairs(unitdata) do
        total = total + b.sum
    end
    if total <= 0 then total = 1 end

    for action, b in SortedPairs(unitdata, function(t, a, c) return t[a].sum > t[c].sum end) do
        table.insert(list, {
            kind = "spell", name = action, n = b.n, sum = b.sum,
            avg = b.sum / b.n, max = b.max, crit = b.crit,
            pct = b.sum / total * 100,
            expandable = next(b.targets) and true or nil,
        })

        if expanded[action] then
            local tname, td
            for tname, td in SortedPairs(b.targets, function(t, a, c) return t[a].sum > t[c].sum end) do
                table.insert(list, {
                    kind = "target", name = tname, n = td.n, sum = td.sum,
                    avg = td.sum / td.n, max = nil,
                    pct = td.sum / b.sum * 100,
                })
            end
        end
    end

    return list
end

local function MakeText(row, spec)
    local fs = row:CreateFontString(nil, "OVERLAY")
    fs:SetFont(FONT, FontSize() - 1, Outline())
    fs:SetPoint("LEFT", row, "LEFT", spec.x, 0)
    fs:SetWidth(spec.w)
    fs:SetHeight(ROWH)
    fs:SetJustifyH(spec.just)
    return fs
end

-- Der Elternframe wird uebergeben und nicht aus der Modulvariable "frame"
-- gelesen: die ist waehrend CreateWindow() noch nil. Ohne Eltern haengen die
-- Zeilen an UIParent und bleiben beim Schliessen als Fragment stehen.
local function CreateRow(parent, i)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROWH)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 2, -(22 + (i - 1) * ROWH))
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -2, -(22 + (i - 1) * ROWH))

    row.hl = row:CreateTexture(nil, "BACKGROUND")
    row.hl:SetAllPoints()
    row.hl:SetTexture(1, 1, 1, 0.06)
    row.hl:Hide()

    row.name  = MakeText(row, COL.name)
    row.count = MakeText(row, COL.count)
    row.avg   = MakeText(row, COL.avg)
    row.max   = MakeText(row, COL.max)
    row.sum   = MakeText(row, COL.sum)
    row.pct   = MakeText(row, COL.pct)

    row:SetScript("OnEnter", function() this.hl:Show() end)
    row:SetScript("OnLeave", function() this.hl:Hide() end)
    row:SetScript("OnClick", function()
        if this.spell then
            expanded[this.spell] = not expanded[this.spell] or nil
            parent:Update()
        end
    end)

    return row
end

local function CreateWindow()
    local f = CreateFrame("Frame", "ShaguDPSDetailFrame", UIParent)
    f:SetWidth(WIDTH)
    f:SetHeight(22 + ROWS * ROWH + 6)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    f:EnableMouseWheel(1)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() this:StartMoving() end)
    f:SetScript("OnDragStop", function()
        this:StopMovingOrSizing()
        cfg.pos = { this:GetCenter() }
    end)

    f:SetBackdrop(backdrop)
    f:SetBackdropColor(0, 0, 0, BgAlpha())
    f:SetBackdropBorderColor(0.28, 0.28, 0.28, 1)

    f.titlebg = f:CreateTexture(nil, "ARTWORK")
    f.titlebg:SetTexture(0, 0, 0, 0.55)
    f.titlebg:SetHeight(20)
    f.titlebg:SetPoint("TOPLEFT", 2, -2)
    f.titlebg:SetPoint("TOPRIGHT", -2, -2)

    f.caption = f:CreateFontString(nil, "OVERLAY")
    f.caption:SetFont(FONT, FontSize(), Outline())
    f.caption:SetPoint("LEFT", f, "TOPLEFT", 8, -12)
    f.caption:SetJustifyH("LEFT")

    f.close = CreateFrame("Button", nil, f)
    f.close:SetWidth(16)
    f.close:SetHeight(16)
    f.close:SetPoint("TOPRIGHT", -4, -4)
    f.close.txt = f.close:CreateFontString(nil, "OVERLAY")
    f.close.txt:SetFont(FONT, FontSize(), Outline())
    f.close.txt:SetAllPoints()
    f.close.txt:SetText("x")
    f.close.txt:SetTextColor(0.8, 0.8, 0.8, 1)
    f.close:SetScript("OnEnter", function() this.txt:SetTextColor(1, 0.4, 0.4, 1) end)
    f.close:SetScript("OnLeave", function() this.txt:SetTextColor(0.8, 0.8, 0.8, 1) end)
    f.close:SetScript("OnClick", function() f:Hide() end)

    f.rows = {}
    local i
    for i = 1, ROWS do
        f.rows[i] = CreateRow(f, i)
    end

    f:SetScript("OnMouseWheel", function()
        scroll = arg1 > 0 and scroll - 1 or scroll + 1
        if scroll < 0 then scroll = 0 end
        f:Update()
    end)

    f.Update = function(self)
        local list = BuildList()
        local total = table.getn(list)
        if scroll > total - ROWS then scroll = total - ROWS end
        if scroll < 0 then scroll = 0 end

        local label = current.datatype == "heal" and "Heilung" or "Schaden"
        local seg = current.segment == 1 and "Aktuell" or "Gesamt"
        self.caption:SetText(string.format("%s%s|r  |cff888888%s / %s|r",
            ClassColorCode(current.unit), current.unit or "-", label, seg))

        local i
        for i = 1, ROWS do
            local entry = list[i + scroll]
            local row = self.rows[i]
            if not entry then
                row:Hide()
            else
                row:Show()
                if entry.kind == "target" then
                    row.spell = nil
                    row.name:SetText("   |cff888888>|r " .. entry.name)
                    row.name:SetTextColor(0.72, 0.72, 0.72, 1)
                    row.max:SetText("")
                else
                    row.spell = entry.name
                    local mark = ""
                    if entry.expandable then
                        mark = expanded[entry.name] and "|cffffcc00-|r " or "|cffffcc00+|r "
                    end
                    row.name:SetText(mark .. entry.name)
                    row.name:SetTextColor(1, 1, 1, 1)
                    -- Crit-Quote hinter das Maximum, wenn es Crits gab
                    if entry.crit and entry.crit > 0 then
                        row.max:SetText(string.format("%s |cff888888%d%%|r",
                            Num(entry.max), math.floor(entry.crit / entry.n * 100 + 0.5)))
                    else
                        row.max:SetText(Num(entry.max))
                    end
                end
                row.count:SetText(entry.n)
                row.avg:SetText(Num(entry.avg))
                row.sum:SetText(Num(entry.sum))
                row.pct:SetText(string.format("%.1f", entry.pct))

                local g = entry.kind == "target" and 0.72 or 0.92
                row.count:SetTextColor(g, g, g, 1)
                row.avg:SetTextColor(g, g, g, 1)
                row.max:SetTextColor(g, g, g, 1)
                row.sum:SetTextColor(g, g, g, 1)
                row.pct:SetTextColor(g * 0.8, g * 0.8, g * 0.8, 1)
            end
        end
    end

    -- Kopfzeile der Spalten
    f.head = CreateFrame("Frame", nil, f)
    f.head:SetHeight(ROWH)
    f.head:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -22)
    f.head:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -22)
    local labels = { name = "Zauber", count = "N", avg = "Avg", max = "Max", sum = "Summe", pct = "%" }
    local key, spec
    for key, spec in pairs(COL) do
        local fs = MakeText(f.head, spec)
        fs:SetText(labels[key])
        fs:SetTextColor(0.6, 0.6, 0.65, 1)
    end
    -- Zeilen um die Kopfzeile nach unten schieben
    for i = 1, ROWS do
        f.rows[i]:ClearAllPoints()
        f.rows[i]:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -(22 + ROWH + (i - 1) * ROWH))
        f.rows[i]:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -(22 + ROWH + (i - 1) * ROWH))
    end
    f:SetHeight(22 + ROWH + ROWS * ROWH + 6)

    -- Escape schliesst das Fenster wie jedes andere Dialogfenster
    table.insert(UISpecialFrames, "ShaguDPSDetailFrame")

    if cfg.pos then
        f:ClearAllPoints()
        f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cfg.pos[1], cfg.pos[2])
    end

    f:Hide()
    return f
end

-- ------------------------------------------------------------------ Oeffnen

local function Open(unit, datatype, segment)
    if not frame then frame = CreateWindow() end
    current.unit = unit
    current.datatype = datatype or "damage"
    current.segment = segment or 1
    scroll = 0
    frame:Update()
    frame:Show()
end

local function Toggle(unit, datatype, segment)
    if frame and frame:IsShown() and current.unit == unit then
        frame:Hide()
        return
    end
    Open(unit, datatype, segment)
end

-- Balken im Meter klickbar machen. Die Balken werden von ShaguDPS bei jedem
-- erzwungenen Refresh neu durchlaufen, deshalb wird der Haken jedes Mal
-- nachgezogen und nicht nur einmal beim Start gesetzt.
local function HookBars()
    if not ShaguDPS.window then return end
    local w
    for w = 1, 10 do
        local win = ShaguDPS.window[w]
        if win and win.bars then
            local id, bar
            for id, bar in pairs(win.bars) do
                if not bar.__detailhook then
                    bar.__detailhook = true
                    bar:SetScript("OnMouseUp", function()
                        if not this.unit then return end
                        local wid = this.parent:GetID()
                        local view = ShaguDPS.config[wid] and ShaguDPS.config[wid].view or 1
                        local seg = ShaguDPS.config[wid] and ShaguDPS.config[wid].segment or 1
                        local dt = (view == 3 or view == 4) and "heal" or "damage"
                        Toggle(this.unit, dt, seg)
                    end)
                end
            end
        end
    end
end

-- ------------------------------------------------------------------ Befehle

local function Handle(msg)
    local text = msg or ""
    local _, _, cmd, rest = string.find(text, "^%s*(%S*)%s*(.-)%s*$")
    cmd = string.lower(cmd or "")

    if cmd == "crits" then
        cfg.crits = (rest == "1" or rest == "on") and 1 or 0
        Msg("Crit-Erkennung: |cffffffff" .. (cfg.crits == 1 and "an" or "aus") .. "|r")
        return
    end

    if cmd == "short" then
        cfg.short = (rest == "1" or rest == "on") and 1 or 0
        if frame and frame:IsShown() then frame:Update() end
        Msg("Kurzzahlen: |cffffffff" .. (cfg.short == 1 and "an" or "aus") .. "|r")
        return
    end

    if cmd == "reset" then
        WipeSegment(0)
        WipeSegment(1)
        if frame and frame:IsShown() then frame:Update() end
        Msg("Detaildaten geleert.")
        return
    end

    if cmd == "help" then
        Msg("Klick auf einen Balken im Meter oeffnet die Aufschluesselung.")
        DEFAULT_CHAT_FRAME:AddMessage("  /sdd            eigene Werte anzeigen")
        DEFAULT_CHAT_FRAME:AddMessage("  /sdd <Name>     Werte eines Mitspielers")
        DEFAULT_CHAT_FRAME:AddMessage("  /sdd heal       eigene Heilung statt Schaden")
        DEFAULT_CHAT_FRAME:AddMessage("  /sdd crits 0|1  Crit-Erkennung")
        DEFAULT_CHAT_FRAME:AddMessage("  /sdd short 0|1  grosse Zahlen kuerzen")
        DEFAULT_CHAT_FRAME:AddMessage("  /sdd reset      Detaildaten leeren")
        return
    end

    if cmd == "heal" then
        Toggle(UnitName("player"), "heal", 1)
        return
    end

    if cmd == "" then
        Toggle(UnitName("player"), "damage", 1)
        return
    end

    -- alles andere als Spielername deuten
    local name = text
    -- Gross-/Kleinschreibung des Kampflogs treffen
    local segdata = store.damage[1]
    local k
    for k in pairs(segdata) do
        if string.lower(k) == string.lower(name) then name = k break end
    end
    Toggle(name, "damage", 1)
end

-- ------------------------------------------------------------------ Start

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_ENTERING_WORLD")
loader:SetScript("OnEvent", function()
    if loader.done then return end
    if not ShaguDPS or not ShaguDPS.parser then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000" .. ADDON .. ":|r ShaguDPS nicht gefunden.")
        return
    end
    loader.done = true

    LoadConfig()
    BuildCritPatterns()
    InstallHooks()

    SLASH_SHAGUDPSDETAIL1 = "/sdd"
    SlashCmdList["SHAGUDPSDETAIL"] = Handle

    -- Balken-Haken nachziehen; ShaguDPS baut Balken erst beim Refresh
    local ticker = CreateFrame("Frame")
    local elapsed = 0
    ticker:SetScript("OnUpdate", function()
        elapsed = elapsed + (arg1 or 0)
        if elapsed < 1 then return end
        elapsed = 0
        HookBars()
    end)
end)
