local addonName, ns = ...

ns = ns or {}

local SkinningData = {}
ns.SkinningData = SkinningData

local EVENT_FRAME = CreateFrame("Frame")
local SCHEMA_VERSION = 1
local SKINNING_SPELL_ID = 8613
local CORRELATION_WINDOW_SECONDS = 5

local TRACKED_NPCS = {
    [245688] = "Gloomclaw",
    [245699] = "Silverscale",
    [245690] = "Lumenfin",
    [247096] = "Umbrafang",
    [247101] = "Netherscythe",
}

local TRACKED_ITEMS = {
    [238528] = "Majestic Claw",
    [238530] = "Majestic Fin",
    [238529] = "Majestic Hide",
}

local listeners = {}
local recentSkinningEvent = nil

local function IsSkinningKnown()
    if C_SpellBook and C_SpellBook.IsSpellKnown then
        return C_SpellBook.IsSpellKnown(SKINNING_SPELL_ID) == true
    end

    if IsSpellKnown then
        return IsSpellKnown(SKINNING_SPELL_ID) == true
    end

    return false
end

local function API_GetNumLootItems()
    if C_Loot and C_Loot.GetNumLootItems then
        local count = C_Loot.GetNumLootItems()
        if type(count) == "number" then
            return count
        end
    end

    if GetNumLootItems then
        return GetNumLootItems() or 0
    end

    return 0
end

local function API_GetLootSlotInfo(slotIndex)
    if C_Loot and C_Loot.GetLootSlotInfo then
        local info = C_Loot.GetLootSlotInfo(slotIndex)
        if type(info) == "table" then
            local quantity = tonumber(info.quantity) or 1
            local itemLink = info.hyperlink or info.itemLink
            return itemLink, quantity
        end
    end

    local itemLink = GetLootSlotLink and GetLootSlotLink(slotIndex) or nil
    local quantity = 1
    if GetLootSlotInfo then
        local _, _, legacyQuantity = GetLootSlotInfo(slotIndex)
        quantity = tonumber(legacyQuantity) or 1
    end
    return itemLink, tonumber(quantity) or 1
end

local function API_GetLootSourceInfo(slotIndex)
    if C_Loot and C_Loot.GetLootSourceInfo then
        local sourceData = C_Loot.GetLootSourceInfo(slotIndex)
        if type(sourceData) == "table" then
            local packed = {}
            for i = 1, #sourceData do
                local source = sourceData[i]
                if type(source) == "table" then
                    packed[#packed + 1] = source.guid
                    packed[#packed + 1] = source.quantity or source.count or 1
                end
            end
            return packed
        end
    end

    if GetLootSourceInfo then
        return { GetLootSourceInfo(slotIndex) }
    end

    return {}
end

local function BuildCharacterKey()
    local name = UnitName("player") or "Unknown"
    local realm = GetNormalizedRealmName() or GetRealmName() or "UnknownRealm"
    return string.format("%s-%s", name, realm), name, realm
end

local function ParseNPCIDFromGUID(guid)
    if type(guid) ~= "string" then
        return nil
    end

    local unitType, _, _, _, _, npcID = strsplit("-", guid)
    if unitType ~= "Creature" and unitType ~= "Vehicle" then
        return nil
    end

    npcID = tonumber(npcID)
    return npcID
end

local function ParseItemIDFromLink(itemLink)
    if type(itemLink) ~= "string" then
        return nil
    end

    local itemID = itemLink:match("item:(%d+):")
    if not itemID then
        itemID = itemLink:match("item:(%d+)")
    end

    return tonumber(itemID)
end

local function GetServerDailyKey(now)
    now = now or GetServerTime()

    if C_DateAndTime and C_DateAndTime.GetSecondsUntilDailyReset then
        local secondsUntilReset = C_DateAndTime.GetSecondsUntilDailyReset()
        if type(secondsUntilReset) == "number" and secondsUntilReset >= 0 then
            local dayStart = now + secondsUntilReset - 86400
            local day = date("!*t", dayStart)
            return string.format("%04d-%02d-%02d", day.year, day.month, day.day)
        end
    end

    local day = date("!*t", now)
    return string.format("%04d-%02d-%02d", day.year, day.month, day.day)
end

local function EnsureDB()
    if type(SkinningDataDB) ~= "table" then
        SkinningDataDB = {}
    end

    SkinningDataDB.version = SkinningDataDB.version or SCHEMA_VERSION
    SkinningDataDB.characters = SkinningDataDB.characters or {}
    SkinningDataDB.history = SkinningDataDB.history or {}
end

local function EnsureCharacterRecord()
    EnsureDB()

    local charKey, charName, realmName = BuildCharacterKey()
    local characters = SkinningDataDB.characters
    local character = characters[charKey]

    if type(character) ~= "table" then
        character = {}
        characters[charKey] = character
    end

    character.key = charKey
    character.name = charName
    character.realm = realmName
    character.hasSkinning = character.hasSkinning == true
    character.skinnedBeasts = character.skinnedBeasts or {}
    character.totals = character.totals or {}
    character.daily = character.daily or {}
    character.dailySkinned = character.dailySkinned or {}

    return character
end

local function NotifyListeners()
    for i = 1, #listeners do
        local callback = listeners[i]
        if type(callback) == "function" then
            callback()
        end
    end
end

local function IsCharacterEligible(character)
    return type(character) == "table" and character.hasSkinning == true
end

local function UpdateCurrentCharacterProfessionState()
    local character = EnsureCharacterRecord()
    character.hasSkinning = IsSkinningKnown()
    NotifyListeners()
end

local function AddDropToCharacter(character, npcID, itemID, quantity)
    if not IsCharacterEligible(character) then
        return
    end

    if TRACKED_ITEMS[itemID] == nil or quantity <= 0 then
        return
    end

    character.totals[itemID] = (character.totals[itemID] or 0) + quantity

    local dayKey = GetServerDailyKey()
    local dayBucket = character.daily[dayKey]
    if type(dayBucket) ~= "table" then
        dayBucket = {}
        character.daily[dayKey] = dayBucket
    end

    dayBucket[itemID] = (dayBucket[itemID] or 0) + quantity
end

local function RecordTrackedSkinningAndDrops()
    local character = EnsureCharacterRecord()
    if not IsCharacterEligible(character) then
        return
    end

    local now = GetServerTime()
    local numLootItems = API_GetNumLootItems()
    if numLootItems <= 0 then
        return
    end

    local trackedSourceNpcID = nil
    local countedNpcThisLoot = {}
    local skinnedThisLoot = 0
    local pendingDrops = {}

    for slotIndex = 1, numLootItems do
        local itemLink, quantity = API_GetLootSlotInfo(slotIndex)
        local itemID = ParseItemIDFromLink(itemLink)

        if itemID and TRACKED_ITEMS[itemID] then
            pendingDrops[itemID] = (pendingDrops[itemID] or 0) + math.max(1, quantity)
        end

        local sources = API_GetLootSourceInfo(slotIndex)
        for i = 1, #sources, 2 do
            local guid = sources[i]
            local npcID = ParseNPCIDFromGUID(guid)
            if npcID and TRACKED_NPCS[npcID] then
                trackedSourceNpcID = trackedSourceNpcID or npcID
                if not countedNpcThisLoot[npcID] then
                    character.skinnedBeasts[npcID] = (character.skinnedBeasts[npcID] or 0) + 1
                    countedNpcThisLoot[npcID] = true
                    skinnedThisLoot = skinnedThisLoot + 1
                end
            end
        end
    end

    if skinnedThisLoot > 0 then
        local dayKey = GetServerDailyKey(now)
        character.dailySkinned[dayKey] = (character.dailySkinned[dayKey] or 0) + skinnedThisLoot
    end

    if trackedSourceNpcID then
        recentSkinningEvent = {
            ts = now,
            npcID = trackedSourceNpcID,
            charKey = character.key,
        }
    end

    if trackedSourceNpcID and recentSkinningEvent and (now - recentSkinningEvent.ts) <= CORRELATION_WINDOW_SECONDS then
        for itemID, quantity in pairs(pendingDrops) do
            AddDropToCharacter(character, trackedSourceNpcID, itemID, quantity)
        end
    end

    NotifyListeners()
end

local function MigrateIfNeeded()
    if SkinningDataDB.version == SCHEMA_VERSION then
        return
    end

    SkinningDataDB.version = SCHEMA_VERSION
end

function SkinningData.RegisterListener(callback)
    if type(callback) ~= "function" then
        return
    end
    table.insert(listeners, callback)
end

function SkinningData.GetTrackedItems()
    return TRACKED_ITEMS
end

function SkinningData.GetTrackedNPCs()
    return TRACKED_NPCS
end

function SkinningData.GetCharacters()
    EnsureDB()
    return SkinningDataDB.characters
end

function SkinningData.GetAccountTotals()
    EnsureDB()
    local totals = {}
    for _, character in pairs(SkinningDataDB.characters) do
        if IsCharacterEligible(character) then
            for itemID, amount in pairs(character.totals or {}) do
                totals[itemID] = (totals[itemID] or 0) + (amount or 0)
            end
        end
    end
    return totals
end

function SkinningData.GetDailyTotals()
    EnsureDB()
    local totals = {}
    local dayKey = GetServerDailyKey()
    for _, character in pairs(SkinningDataDB.characters) do
        if IsCharacterEligible(character) then
            local dayBucket = character.daily and character.daily[dayKey]
            if type(dayBucket) == "table" then
                for itemID, amount in pairs(dayBucket) do
                    totals[itemID] = (totals[itemID] or 0) + (amount or 0)
                end
            end
        end
    end
    return totals, dayKey
end

function SkinningData.GetDailyHistory()
    EnsureDB()
    local aggregate = {}
    for _, character in pairs(SkinningDataDB.characters) do
        if IsCharacterEligible(character) then
            for dayKey, bucket in pairs(character.daily or {}) do
                if type(bucket) == "table" then
                    if not aggregate[dayKey] then
                        aggregate[dayKey] = {}
                    end
                    for itemID, count in pairs(bucket) do
                        aggregate[dayKey][itemID] = (aggregate[dayKey][itemID] or 0) + count
                    end
                end
            end
        end
    end
    local days = {}
    for dayKey, items in pairs(aggregate) do
        table.insert(days, { dayKey = dayKey, items = items })
    end
    table.sort(days, function(a, b) return a.dayKey > b.dayKey end)
    return days
end

function SkinningData.GetCharacterSummary()
    EnsureDB()
    local dayKey = GetServerDailyKey()
    local summary = {}
    for charKey, character in pairs(SkinningDataDB.characters) do
        if IsCharacterEligible(character) then
            local total = 0
            local dayBucket = character.daily and character.daily[dayKey]
            for _, amount in pairs(dayBucket or {}) do
                total = total + (amount or 0)
            end
            local skinnedToday = 0
            if type(character.dailySkinned) == "table" then
                skinnedToday = character.dailySkinned[dayKey] or 0
            end
            table.insert(summary, {
                key = charKey,
                name = character.name,
                realm = character.realm,
                total = total,
                skinnedToday = skinnedToday,
            })
        end
    end

    table.sort(summary, function(a, b)
        local aLabel = string.lower(string.format("%s-%s", a.name or "", a.realm or ""))
        local bLabel = string.lower(string.format("%s-%s", b.name or "", b.realm or ""))
        if aLabel == bLabel then
            return (a.key or "") < (b.key or "")
        end
        return aLabel < bLabel
    end)

    return summary
end

function SkinningData.ClearDailyHistory()
    EnsureDB()
    for _, character in pairs(SkinningDataDB.characters) do
        character.daily = {}
        character.dailySkinned = {}
    end
    NotifyListeners()
end

function SkinningData.ResetTotals()
    EnsureDB()
    for _, character in pairs(SkinningDataDB.characters) do
        character.skinnedBeasts = {}
        character.totals = {}
        character.daily = {}
        character.dailySkinned = {}
    end
    NotifyListeners()
end

EVENT_FRAME:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        EnsureDB()
        MigrateIfNeeded()
        EnsureCharacterRecord()
        UpdateCurrentCharacterProfessionState()
        NotifyListeners()
    elseif event == "PLAYER_ENTERING_WORLD" then
        UpdateCurrentCharacterProfessionState()
    elseif event == "SKILL_LINES_CHANGED" then
        UpdateCurrentCharacterProfessionState()
    elseif event == "LOOT_OPENED" then
        RecordTrackedSkinningAndDrops()
    end
end)

EVENT_FRAME:RegisterEvent("PLAYER_LOGIN")
EVENT_FRAME:RegisterEvent("PLAYER_ENTERING_WORLD")
EVENT_FRAME:RegisterEvent("SKILL_LINES_CHANGED")
EVENT_FRAME:RegisterEvent("LOOT_OPENED")
