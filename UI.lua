local _, ns = ...
local SkinningData = ns and ns.SkinningData

if not SkinningData then
    return
end

local UI = {}
ns.UI = UI

local frame
local tabs = {}
local overviewPanel
local historyPanel
local contentArea
local itemRows = {}
local characterRows = {}
local historyScrollFrame
local historyScrollChild
local historyDayRows = {}

local ORDERED_ITEM_IDS = {
    238530,
    238528,
    238529,
}

local function ResolveItemIcon(itemID)
    if C_Item and C_Item.GetItemIconByID then
        local icon = C_Item.GetItemIconByID(itemID)
        if icon then
            return icon
        end
    end
    return _G.GetItemIcon and _G.GetItemIcon(itemID) or 134400
end

local function SetTab(index)
    for i = 1, #tabs do
        local tab = tabs[i]
        if i == index then
            tab:SetEnabled(false)
            if tab.Label then
                tab.Label:SetFontObject("GameFontNormal")
            end
            tab.panel:Show()
        else
            tab:SetEnabled(true)
            if tab.Label then
                tab.Label:SetFontObject("GameFontHighlight")
            end
            tab.panel:Hide()
        end
    end
end

local function CreateTab(index, text, panel)
    local tab = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    tab:SetID(index)
    tab:SetSize(90, 22)
    tab:SetText(text)
    tab.Label = tab:GetFontString()
    if tab.Label then
        tab.Label:SetFontObject("GameFontHighlight")
    end
    tab:SetScript("OnClick", function(self)
        SetTab(self:GetID())
    end)
    tab.panel = panel
    return tab
end

local function EnsureOverviewRows()
    if #itemRows > 0 then
        return
    end

    for i = 1, #ORDERED_ITEM_IDS do
        local row = CreateFrame("Frame", nil, overviewPanel)
        row:SetSize(320, 24)
        row:SetPoint("TOPLEFT", 16, -28 - ((i - 1) * 26))

        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(20, 20)
        row.icon:SetPoint("LEFT", 0, 0)

        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.text:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
        row.text:SetJustifyH("LEFT")
        row.text:SetText("-")

        itemRows[i] = row
    end

end

local function FormatItemCountText(itemID, count)
    local itemName = (GetItemInfo(itemID)) or (SkinningData.GetTrackedItems()[itemID]) or tostring(itemID)
    return string.format("%dx %s", count or 0, itemName)
end

local function RefreshOverview()
    EnsureOverviewRows()

    local dailyTotals, dayKey = SkinningData.GetDailyTotals()
    local summary = SkinningData.GetCharacterSummary()

    local dailyTotalCount = 0
    for _, itemID in ipairs(ORDERED_ITEM_IDS) do
        dailyTotalCount = dailyTotalCount + (dailyTotals[itemID] or 0)
    end

    overviewPanel.dailyLabel:SetText(string.format("Daily Total (%s): %d", dayKey, dailyTotalCount))

    for i, itemID in ipairs(ORDERED_ITEM_IDS) do
        local count = dailyTotals[itemID] or 0
        local row = itemRows[i]
        row.icon:SetTexture(ResolveItemIcon(itemID))
        row.text:SetText(FormatItemCountText(itemID, count))
    end

    local ROW_HEIGHT = 18
    local numChars = #summary
    for i = 1, math.max(numChars, #characterRows) do
        if i <= numChars then
            if not characterRows[i] then
                local row = CreateFrame("Frame", nil, charScrollChild)
                row:SetHeight(ROW_HEIGHT)
                row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                row.text:SetAllPoints()
                row.text:SetJustifyH("LEFT")
                characterRows[i] = row
            end
            local row = characterRows[i]
            row:SetWidth(charScrollChild:GetWidth())
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", charScrollChild, "TOPLEFT", 0, -((i - 1) * ROW_HEIGHT))
            row:Show()
            local data = summary[i]
            row.text:SetText(string.format("%s-%s: %d", data.name or "?", data.realm or "?", data.total or 0))
        else
            if characterRows[i] then
                characterRows[i]:Hide()
            end
        end
    end
    charScrollChild:SetHeight(math.max(1, numChars * ROW_HEIGHT))
end

local ROW_H = 22

local function RefreshHistory()
    local days = SkinningData.GetDailyHistory()
    local numDays = #days

    for i = 1, math.max(numDays, #historyDayRows) do
        if i <= numDays then
            if not historyDayRows[i] then
                local row = CreateFrame("Frame", nil, historyScrollChild)
                row:SetHeight(ROW_H)

                row.dateText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                row.dateText:SetPoint("LEFT", row, "LEFT", 2, 0)
                row.dateText:SetWidth(82)
                row.dateText:SetJustifyH("LEFT")

                row.itemParts = {}
                for j = 1, #ORDERED_ITEM_IDS do
                    local part = {}
                    part.icon = row:CreateTexture(nil, "ARTWORK")
                    part.icon:SetSize(16, 16)
                    part.count = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                    part.count:SetWidth(40)
                    part.count:SetJustifyH("LEFT")
                    row.itemParts[j] = part
                end

                historyDayRows[i] = row
            end

            local row = historyDayRows[i]
            row:SetWidth(historyScrollChild:GetWidth())
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", historyScrollChild, "TOPLEFT", 0, -((i - 1) * ROW_H))
            row:Show()

            local data = days[i]
            row.dateText:SetText(data.dayKey)

            for j, itemID in ipairs(ORDERED_ITEM_IDS) do
                local part = row.itemParts[j]
                local xOff = 88 + (j - 1) * 62
                part.icon:ClearAllPoints()
                part.icon:SetPoint("LEFT", row, "LEFT", xOff, 0)
                part.icon:SetTexture(ResolveItemIcon(itemID))
                part.count:ClearAllPoints()
                part.count:SetPoint("LEFT", row, "LEFT", xOff + 20, 0)
                part.count:SetText(tostring(data.items[itemID] or 0))
            end
        else
            if historyDayRows[i] then
                historyDayRows[i]:Hide()
            end
        end
    end

    historyScrollChild:SetHeight(math.max(1, numDays * ROW_H))
    historyPanel.footer:SetText(string.format("Days recorded: %d", numDays))
end

local function RefreshUI()
    if not frame or not frame:IsShown() then
        return
    end

    RefreshOverview()
    RefreshHistory()
end

local function BuildFrame()
    frame = CreateFrame("Frame", "SkinningDataMainFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(580, 360)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER")
    frame:SetClampedToScreen(true)
    frame:SetClampRectInsets(0, 0, 0, 0)
    frame:SetMovable(true)
    frame:SetUserPlaced(true)
    frame:EnableMouse(true)
    frame:Hide()

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.title:SetPoint("LEFT", frame.TitleBg, "LEFT", 8, 0)
    frame.title:SetText("Skinning Data")

    frame.dragHandle = CreateFrame("Frame", nil, frame)
    frame.dragHandle:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -6)
    frame.dragHandle:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -28, -6)
    frame.dragHandle:SetHeight(24)
    frame.dragHandle:EnableMouse(true)
    frame.dragHandle:RegisterForDrag("LeftButton")
    frame.dragHandle:SetScript("OnDragStart", function()
        frame:StartMoving()
    end)
    frame.dragHandle:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
    end)

    contentArea = CreateFrame("Frame", nil, frame)
    contentArea:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -54)
    contentArea:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 38)

    overviewPanel = CreateFrame("Frame", nil, frame)
    overviewPanel:SetAllPoints(contentArea)

    overviewPanel.dailyLabel = overviewPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    overviewPanel.dailyLabel:SetPoint("TOPLEFT", 16, -8)
    overviewPanel.dailyLabel:SetText("Daily Total: 0")

    overviewPanel.charHeader = overviewPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    overviewPanel.charHeader:SetPoint("TOPLEFT", 16, -120)
    overviewPanel.charHeader:SetText("Eligible Characters")

    charScrollFrame = CreateFrame("ScrollFrame", nil, overviewPanel, "UIPanelScrollFrameTemplate")
    charScrollFrame:SetPoint("TOPLEFT", overviewPanel, "TOPLEFT", 10, -136)
    charScrollFrame:SetPoint("BOTTOMRIGHT", overviewPanel, "BOTTOMRIGHT", -28, 42)

    charScrollChild = CreateFrame("Frame", nil, charScrollFrame)
    charScrollChild:SetWidth(charScrollFrame:GetWidth() or 300)
    charScrollChild:SetHeight(1)
    charScrollFrame:SetScrollChild(charScrollChild)

    overviewPanel.resetTotalsButton = CreateFrame("Button", nil, overviewPanel, "UIPanelButtonTemplate")
    overviewPanel.resetTotalsButton:SetSize(130, 22)
    overviewPanel.resetTotalsButton:SetPoint("BOTTOMLEFT", 16, 12)
    overviewPanel.resetTotalsButton:SetText("Reset Totals")
    overviewPanel.resetTotalsButton:SetScript("OnClick", function()
        SkinningData.ResetTotals()
        RefreshUI()
    end)

    historyPanel = CreateFrame("Frame", nil, frame)
    historyPanel:SetAllPoints(contentArea)

    historyPanel.footer = historyPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    historyPanel.footer:SetPoint("BOTTOMLEFT", 16, 16)
    historyPanel.footer:SetText("Entries: 0")

    historyScrollFrame = CreateFrame("ScrollFrame", nil, historyPanel, "UIPanelScrollFrameTemplate")
    historyScrollFrame:SetPoint("TOPLEFT", historyPanel, "TOPLEFT", 10, -8)
    historyScrollFrame:SetPoint("BOTTOMRIGHT", historyPanel, "BOTTOMRIGHT", -28, 42)

    historyScrollChild = CreateFrame("Frame", nil, historyScrollFrame)
    historyScrollChild:SetWidth(historyScrollFrame:GetWidth() or 500)
    historyScrollChild:SetHeight(1)
    historyScrollFrame:SetScrollChild(historyScrollChild)

    historyPanel.clearButton = CreateFrame("Button", nil, historyPanel, "UIPanelButtonTemplate")
    historyPanel.clearButton:SetSize(130, 22)
    historyPanel.clearButton:SetPoint("BOTTOMRIGHT", -16, 12)
    historyPanel.clearButton:SetText("Clear Daily History")
    historyPanel.clearButton:SetScript("OnClick", function()
        SkinningData.ClearDailyHistory()
        RefreshHistory()
    end)

    tabs[1] = CreateTab(1, "Overview", overviewPanel)
    tabs[1]:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -28)

    tabs[2] = CreateTab(2, "History", historyPanel)
    tabs[2]:SetPoint("LEFT", tabs[1], "RIGHT", 6, 0)

    SetTab(1)
end

local function ToggleFrame()
    if not frame then
        BuildFrame()
    end

    if frame:IsShown() then
        frame:Hide()
        return
    end

    frame:ClearAllPoints()
    frame:SetPoint("CENTER")
    frame:Show()
    RefreshUI()
end

SLASH_SKINNINGDATA1 = "/skinningdata"
SLASH_SKINNINGDATA2 = "/sd"
SlashCmdList.SKINNINGDATA = ToggleFrame

SkinningData.RegisterListener(function()
    RefreshUI()
end)
