-- =====================================================
-- QuestAnnouncer v2.2.3
-- Announces quest progress to party chat
-- =====================================================

local ADDON_NAME = "QuestAnnouncer"
local VERSION = "2.2.3"

-- =====================================================
-- ADDON NAMESPACE
-- =====================================================
QuestAnnouncer = QuestAnnouncer or {}
local QA = QuestAnnouncer

-- =====================================================
-- CONSTANTS
-- =====================================================
local DEFAULTS = {
  filters = {
    accept = true,
    progress = true,
    complete = true,
    turnin = true,
  },
  useShortPrefix = false,
  debug = false,
}

local PREFIX_LONG = "Quest Announcer:"
local PREFIX_SHORT = "QA:"

-- =====================================================
-- STATE VARIABLES
-- =====================================================
QA.filters = {}
QA.useShortPrefix = false
QA.DEBUG = false
QA.prevQuestSnapshot = {}
QA.questCacheInitialized = false

-- =====================================================
-- UTILITY FUNCTIONS
-- =====================================================
local function DebugPrint(msg)
  if QA.DEBUG then
    print("|cff66ccff[" .. ADDON_NAME .. " DEBUG]|r " .. tostring(msg))
  end
end

local function IsInParty()
  return GetNumPartyMembers() > 0
end

local function BooleanValue(val)
  return val and true or false
end

-- =====================================================
-- DATABASE FUNCTIONS
-- =====================================================
function QA:InitDB()
  -- Initialize saved variables
  if not QuestAnnouncerDB then
    QuestAnnouncerDB = {}
  end

  -- Initialize filters table
  QuestAnnouncerDB.filters = QuestAnnouncerDB.filters or {}
  
  -- Apply defaults for missing values
  for key, defaultValue in pairs(DEFAULTS.filters) do
    if QuestAnnouncerDB.filters[key] == nil then
      QuestAnnouncerDB.filters[key] = defaultValue
    end
  end

  -- Apply other defaults
  if QuestAnnouncerDB.useShortPrefix == nil then
    QuestAnnouncerDB.useShortPrefix = DEFAULTS.useShortPrefix
  end

  if QuestAnnouncerDB.debug == nil then
    QuestAnnouncerDB.debug = DEFAULTS.debug
  end

  -- Load saved settings into runtime variables
  self.filters = QuestAnnouncerDB.filters
  self.useShortPrefix = QuestAnnouncerDB.useShortPrefix
  self.DEBUG = QuestAnnouncerDB.debug

  DebugPrint("Database initialized")
end

function QA:SaveDB()
  QuestAnnouncerDB.filters = self.filters
  QuestAnnouncerDB.useShortPrefix = self.useShortPrefix
  QuestAnnouncerDB.debug = self.DEBUG
  
  DebugPrint("Settings saved to disk")
end

-- =====================================================
-- CORE FUNCTIONALITY
-- =====================================================
function QA:IsFilterEnabled(filterName)
  return self.filters[filterName] == true
end

function QA:GetPrefix()
  return self.useShortPrefix and PREFIX_SHORT or PREFIX_LONG
end

function QA:Announce(message)
  if not message or message == "" then 
    DebugPrint("Attempted to announce empty message")
    return 
  end
  
  if not IsInParty() then 
    DebugPrint("Not in party, skipping announcement")
    return 
  end

  local fullMessage = self:GetPrefix() .. " " .. message
  SendChatMessage(fullMessage, "PARTY")
  DebugPrint("Announced: " .. message)
end

-- =====================================================
-- QUEST TRACKING
-- =====================================================
function QA:InitializeQuestSnapshot()
  wipe(self.prevQuestSnapshot)

  local numEntries = GetNumQuestLogEntries()
  for i = 1, numEntries do
    local title, _, _, _, isHeader, _, isComplete = GetQuestLogTitle(i)
    if title and not isHeader then
      self.prevQuestSnapshot[title] = (isComplete == 1)
    end
  end

  self.questCacheInitialized = true
  DebugPrint("Quest snapshot initialized with " .. numEntries .. " entries")
end

function QA:ScanQuestTurnIns()
  if not self:IsFilterEnabled("turnin") then return end
  if not self.questCacheInitialized then return end

  local currentSnapshot = {}
  local numEntries = GetNumQuestLogEntries()

  -- Build current quest snapshot
  for i = 1, numEntries do
    local title, _, _, _, isHeader, _, isComplete = GetQuestLogTitle(i)
    if title and not isHeader then
      currentSnapshot[title] = (isComplete == 1)
    end
  end

  -- Check for completed quests that are now missing (turned in)
  for questTitle, wasComplete in pairs(self.prevQuestSnapshot) do
    if wasComplete and not currentSnapshot[questTitle] then
      self:Announce("★ I turned in quest: " .. questTitle .. " ★")
    end
  end

  -- Update snapshot
  self.prevQuestSnapshot = currentSnapshot
end

function QA:OnQuestProgress(message)
  if not self:IsFilterEnabled("progress") then return end
  if not message or type(message) ~= "string" then return end

  -- Parse progress message: "Objective Name: 5/10"
  local objectiveName, current, maximum = string.match(message, "(.*):%s*(%d+)%s*/%s*(%d+)")
  if not objectiveName then return end

  current = tonumber(current)
  maximum = tonumber(maximum)
  if not current or not maximum then return end

  if current < maximum then
    self:Announce("★ " .. objectiveName .. " (" .. current .. "/" .. maximum .. ") ★")
  elseif self:IsFilterEnabled("complete") then
    self:Announce("★ Finished " .. objectiveName .. " (" .. current .. "/" .. maximum .. ") ★")
  end
end

function QA:HandleQuestAccepted(questLogIndex)
  if not self:IsFilterEnabled("accept") then return end

  local title, _, _, _, isHeader = GetQuestLogTitle(questLogIndex)
  if not title or isHeader then return end

  self:Announce("★ Accepted quest: " .. title .. " ★")
  
  -- Add to snapshot as incomplete
  self.prevQuestSnapshot[title] = false
end

-- =====================================================
-- SLASH COMMANDS
-- =====================================================
local function ShowHelp()
  print("|cff66ccff" .. ADDON_NAME .. " v" .. VERSION .. "|r")
  print("Commands:")
  print("  /qa filter accept | progress | complete | turnin - Toggle announcement filters")
  print("  /qa prefix short | long - Change prefix style")
  print("  /qa debug - Toggle debug output")
  print("  /qa test - Send test announcement")
  print("  /qa status - Show current settings")
end

local function ShowStatus()
  print("|cff66ccff" .. ADDON_NAME .. " Status:|r")
  print("  Accept: " .. (QA.filters.accept and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
  print("  Progress: " .. (QA.filters.progress and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
  print("  Complete: " .. (QA.filters.complete and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
  print("  Turn-in: " .. (QA.filters.turnin and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
  print("  Prefix: " .. (QA.useShortPrefix and "Short (QA:)" or "Long (Quest Announcer:)"))
  print("  Debug: " .. (QA.DEBUG and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
end

SLASH_QUESTANNOUNCER1 = "/qa"
SlashCmdList["QUESTANNOUNCER"] = function(msg)
  msg = string.lower(strtrim(msg or ""))
  
  if msg == "" or msg == "help" then
    ShowHelp()
    return
  end

  if msg == "status" then
    ShowStatus()
    return
  end

  if msg == "test" then
    QA:Announce("★ Test announcement ★")
    return
  end

  if msg == "debug" then
    QA.DEBUG = not QA.DEBUG
    print(ADDON_NAME .. ": Debug mode " .. (QA.DEBUG and "|cff00ff00ENABLED|r" or "|cffff0000DISABLED|r"))
    QA:SaveDB()
    return
  end

  if msg == "prefix short" then
    QA.useShortPrefix = true
    print(ADDON_NAME .. ": Using short prefix (QA:)")
    QA:SaveDB()
    return
  end

  if msg == "prefix long" then
    QA.useShortPrefix = false
    print(ADDON_NAME .. ": Using long prefix (Quest Announcer:)")
    QA:SaveDB()
    return
  end

  -- Handle filter commands
  local filterType = string.match(msg, "filter%s+(%w+)")
  if filterType and QA.filters[filterType] ~= nil then
    QA.filters[filterType] = not QA.filters[filterType]
    print(ADDON_NAME .. ": " .. filterType .. " announcements " .. 
          (QA.filters[filterType] and "|cff00ff00ENABLED|r" or "|cffff0000DISABLED|r"))
    QA:SaveDB()
    return
  end

  -- Unknown command
  print(ADDON_NAME .. ": Unknown command. Type /qa help for commands.")
end

-- =====================================================
-- EVENT HANDLING
-- =====================================================
local eventFrame = CreateFrame("Frame")

local eventHandlers = {
  PLAYER_LOGIN = function()
    QA:InitDB()
    QA:InitializeQuestSnapshot()
    print("|cff66ccff" .. ADDON_NAME .. " v" .. VERSION .. "|r loaded. Type |cffffcc00/qa help|r for commands.")
  end,

  QUEST_LOG_UPDATE = function()
    QA:ScanQuestTurnIns()
  end,

  UI_INFO_MESSAGE = function(message)
    QA:OnQuestProgress(message)
  end,

  QUEST_ACCEPTED = function(questLogIndex)
    QA:HandleQuestAccepted(questLogIndex)
  end,
}

eventFrame:SetScript("OnEvent", function(self, event, ...)
  local handler = eventHandlers[event]
  if handler then
    handler(...)
  end
end)

-- Register all events
for event in pairs(eventHandlers) do
  eventFrame:RegisterEvent(event)
end

-- =====================================================
-- GUI OPTIONS PANEL
-- =====================================================
local optionsPanel = CreateFrame("Frame", "QuestAnnouncerOptionsPanel")
optionsPanel.name = ADDON_NAME
InterfaceOptions_AddCategory(optionsPanel)

-- Title
local title = optionsPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16)
title:SetText(ADDON_NAME .. " v" .. VERSION)

-- Subtitle
local subtitle = optionsPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
subtitle:SetText("Configure which quest events to announce to party chat.")

-- Checkbox factory function
local function CreateCheckbox(text, parent, offsetX, offsetY, getter, setter)
  local checkbox = CreateFrame("CheckButton", nil, optionsPanel, "UICheckButtonTemplate")
  checkbox:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", offsetX, offsetY)

  checkbox.text = checkbox:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  checkbox.text:SetPoint("LEFT", checkbox, "RIGHT", 4, 0)
  checkbox.text:SetText(text)

  checkbox:SetScript("OnClick", function(self)
    local isChecked = BooleanValue(self:GetChecked())
    setter(isChecked)
    QA:SaveDB()
  end)

  checkbox.getter = getter

  return checkbox
end

-- Create checkboxes
local checkboxAccept = CreateCheckbox(
  "Announce quest accepted",
  subtitle, 0, -20,
  function() return QA.filters.accept end,
  function(val) QA.filters.accept = val end
)

local checkboxProgress = CreateCheckbox(
  "Announce quest progress",
  checkboxAccept, 0, -8,
  function() return QA.filters.progress end,
  function(val) QA.filters.progress = val end
)

local checkboxComplete = CreateCheckbox(
  "Announce objective completion",
  checkboxProgress, 0, -8,
  function() return QA.filters.complete end,
  function(val) QA.filters.complete = val end
)

local checkboxTurnin = CreateCheckbox(
  "Announce quest turn-in",
  checkboxComplete, 0, -8,
  function() return QA.filters.turnin end,
  function(val) QA.filters.turnin = val end
)

-- Separator
local separator = optionsPanel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
separator:SetPoint("TOPLEFT", checkboxTurnin, "BOTTOMLEFT", 0, -16)
separator:SetText("Other Options:")

local checkboxDebug = CreateCheckbox(
  "Enable debug output",
  separator, 0, -12,
  function() return QA.DEBUG end,
  function(val) QA.DEBUG = val end
)

-- Prefix dropdown
local prefixLabel = optionsPanel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
prefixLabel:SetPoint("TOPLEFT", checkboxDebug, "BOTTOMLEFT", 0, -16)
prefixLabel:SetText("Announcement Prefix:")

local prefixDropdown = CreateFrame("Frame", "QuestAnnouncerPrefixDropdown", optionsPanel, "UIDropDownMenuTemplate")
prefixDropdown:SetPoint("TOPLEFT", prefixLabel, "BOTTOMLEFT", -15, -8)

-- Dropdown initialization
local function PrefixDropdown_Initialize()
  local info = UIDropDownMenu_CreateInfo()
  
  -- Long prefix option
  info.text = "Long (Quest Announcer:)"
  info.value = false
  info.func = function()
    QA.useShortPrefix = false
    QA:SaveDB()
    UIDropDownMenu_SetSelectedValue(prefixDropdown, false)
  end
  info.checked = (QA.useShortPrefix == false)
  UIDropDownMenu_AddButton(info)
  
  -- Short prefix option
  info.text = "Short (QA:)"
  info.value = true
  info.func = function()
    QA.useShortPrefix = true
    QA:SaveDB()
    UIDropDownMenu_SetSelectedValue(prefixDropdown, true)
  end
  info.checked = (QA.useShortPrefix == true)
  UIDropDownMenu_AddButton(info)
end

UIDropDownMenu_Initialize(prefixDropdown, PrefixDropdown_Initialize)
UIDropDownMenu_SetWidth(prefixDropdown, 180)

-- Refresh panel when shown
local allCheckboxes = {checkboxAccept, checkboxProgress, checkboxComplete, checkboxTurnin, checkboxDebug}

optionsPanel:SetScript("OnShow", function()
  for _, checkbox in ipairs(allCheckboxes) do
    checkbox:SetChecked(checkbox.getter())
  end
  
  -- Update dropdown
  UIDropDownMenu_SetSelectedValue(prefixDropdown, QA.useShortPrefix)
  UIDropDownMenu_SetText(prefixDropdown, QA.useShortPrefix and "Short (QA:)" or "Long (Quest Announcer:)")
end)