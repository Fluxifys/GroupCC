-- GroupCC.lua
-- Core: SavedVariables, catalog, slash commands, sync (send), broadcast "next" calls
-- Also: auto-open runtime window in dungeons if enabled, and /groupcc alias

GroupCCDB = GroupCCDB or {}

-- AoE CC catalog (expand as you like)
GroupCC_ClassAOE = {
  PALADIN = {115750},                 -- Blinding Light
  WARRIOR = {46968, 5246},            -- Shockwave, Intimidating Shout
  SHAMAN  = {192058, 51490},          -- Capacitor Totem, Thunderstorm
  HUNTER  = {236776, 186387, 462031}, -- High Explosive Trap, Bursting Shot, Implosion Trap
}

local function flattenOrder()
  local out={}
  for _,cls in ipairs({"PALADIN","WARRIOR","SHAMAN","HUNTER"}) do
    local t=GroupCC_ClassAOE[cls]; if t then for _,id in ipairs(t) do table.insert(out,id) end end
  end
  return out
end

local function initDB()
  local db=GroupCCDB
  db.enabledSpells = db.enabledSpells or {}
  for _,id in ipairs(flattenOrder()) do if db.enabledSpells[id]==nil then db.enabledSpells[id]=true end end
  db.priorityOrder = db.priorityOrder or flattenOrder()
  if #db.priorityOrder==0 then db.priorityOrder=flattenOrder() end
  if db.ttsNext==nil   then db.ttsNext=true end
  if db.onlyMine==nil  then db.onlyMine=false end
  db.window = db.window or { w=360, h=260, scale=1, point="CENTER", rel="CENTER", x=0, y=0 }
  db.roleOrder = db.roleOrder or {"TANK","HEALER","DAMAGER"}
  -- NEW: auto-open runtime window on entering a 5-man dungeon
  if db.autoOpenDungeon == nil then db.autoOpenDungeon = false end
end
initDB()

-- Helper for names / help printing from anywhere
local function SpellName(id)
  if C_Spell and C_Spell.GetSpellInfo then local i=C_Spell.GetSpellInfo(id); if i and i.name then return i.name end end
  if GetSpellInfo then local n=GetSpellInfo(id); if n then return n end end
  return "Spell "..id
end

local function printHelp()
  print("|cff33ff99GroupCC|r commands:")
  print("  /gcc show          - toggle the GroupCC list window")
  print("  /gcc now           - local TTS: 'Use <spell> now' (your client only)")
  print("  /gcc next          - BROADCAST: call the next player ('Use <spell> now')")
  print("  /gcc options       - open options window")
  print("  /gcc hearall       - auto-TTS will announce everyone")
  print("  /gcc hearonly      - auto-TTS announces only your spells")
  print("  /gcc share         - share spell order + role priority to group (with confirm on receive)")
  print("  /gcc status        - show current settings")
  print("  /gcc help          - show this help")
end
_G.GroupCC_PrintHelp = printHelp  -- expose for Options button

-- ---------- Sync (send) ----------
local ADDON_PREFIX = "GroupCC1"
C_ChatInfo.RegisterAddonMessagePrefix(ADDON_PREFIX)

local function serializeRoleOrder()
  return table.concat(GroupCCDB.roleOrder, ",")  -- e.g. "TANK,HEALER,DAMAGER"
end

local function serializeSpellOrder()
  local t={} ; for i,id in ipairs(GroupCCDB.priorityOrder or {}) do t[i]=tostring(id) end
  return table.concat(t, ",")                    -- e.g. "46968,115750,192058"
end

local function sendToChannel(payload)
  local chan = IsInRaid() and "RAID" or (IsInGroup() and "PARTY" or nil)
  if not chan then print("|cff33ff99GroupCC|r: Not in a group; nothing sent.") return end
  C_ChatInfo.SendAddonMessage(ADDON_PREFIX, payload, chan)
end

local function shareAll()
  sendToChannel("V1|ROLE|"..serializeRoleOrder())
  sendToChannel("V1|SPELL|"..serializeSpellOrder())
  print("|cff33ff99GroupCC|r: Shared priority and role order to group.")
end

-- Broadcast a "call next" so only the targeted player hears TTS
local function broadcastNext()
  if _G.GroupCCRuntime_CallNext then
    _G.GroupCCRuntime_CallNext(true) -- broadcast = true
  else
    print("GroupCC: runtime not loaded")
  end
end

-- ---------- Slash commands ----------
SLASH_GROUPCC1 = "/gcc"
SLASH_GROUPCC2 = "/groupcc"   -- alias
SlashCmdList["GROUPCC"] = function(msg)
  msg = (msg or ""):lower():match("^%s*(.-)%s*$")
  -- NEW: typing /gcc or /groupcc with no args opens Options instead of printing help
  if msg=="" then
    if GroupCCOptions_Toggle then GroupCCOptions_Toggle() else print("GroupCC: options not loaded") end
    return
  end

  if msg=="help" or msg=="?" then
    printHelp()
  elseif msg=="show" or msg=="window" or msg=="toggle" then
    if GroupCCRuntime_Toggle then GroupCCRuntime_Toggle() else print("GroupCC: runtime not loaded") end
  elseif msg=="now" then
    if GroupCCRuntime_AnnounceNow then GroupCCRuntime_AnnounceNow() else print("GroupCC: runtime not loaded") end
  elseif msg=="next" then
    broadcastNext()
  elseif msg=="options" or msg=="opt" or msg=="config" then
    if GroupCCOptions_Toggle then GroupCCOptions_Toggle() else print("GroupCC: options not loaded") end
  elseif msg=="hearall" then
    GroupCCDB.onlyMine=false; print("|cff33ff99GroupCC|r: Auto-TTS will announce everyone.")
    if GroupCCRuntime_ForceRefresh then GroupCCRuntime_ForceRefresh() end
  elseif msg=="hearonly" then
    GroupCCDB.onlyMine=true; print("|cff33ff99GroupCC|r: Auto-TTS will announce only your spells.")
    if GroupCCRuntime_ForceRefresh then GroupCCRuntime_ForceRefresh() end
  elseif msg=="share" then
    shareAll()
  elseif msg=="status" then
    local who = GroupCCDB.onlyMine and "only yours" or "everyone"
    print(("|cff33ff99GroupCC|r: TTS=%s, Auto-TTS hears %s."):format(
      GroupCCDB.ttsNext and "ON" or "OFF", who))
    if GroupCCRuntime_DebugTop then GroupCCRuntime_DebugTop() end
  else
    printHelp()
  end
end

SLASH_GCCSHOW1 = "/gccshow"
SlashCmdList["GCCSHOW"] = function() if GroupCCRuntime_Toggle then GroupCCRuntime_Toggle() else print("GroupCC: runtime not loaded") end end
SLASH_GCCNOW1  = "/gccnow"
SlashCmdList["GCCNOW"]  = function() if GroupCCRuntime_AnnounceNow then GroupCCRuntime_AnnounceNow() else print("GroupCC: runtime not loaded") end end
SLASH_GCCNEXT1 = "/gccnext"
SlashCmdList["GCCNEXT"] = function() broadcastNext() end
SLASH_GCCSHARE1= "/gccshare"
SlashCmdList["GCCSHARE"] = function() shareAll() end

-- ---------- Auto-open runtime in dungeons ----------
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
watcher:RegisterEvent("ZONE_CHANGED_NEW_AREA")
watcher:RegisterEvent("GROUP_ROSTER_UPDATE")
watcher:SetScript("OnEvent", function()
  if not GroupCCDB.autoOpenDungeon then return end
  local inInstance, instType = IsInInstance()
  if inInstance and instType == "party" then
    -- Show the runtime window if it isn't already shown
    if GroupCCRuntime_Toggle and GroupCCRuntimeFrame and not GroupCCRuntimeFrame:IsShown() then
      -- Make sure scale preference is applied
      if GroupCCRuntimeFrame.SetScale and GroupCCDB.window and GroupCCDB.window.scale then
        GroupCCRuntimeFrame:SetScale(GroupCCDB.window.scale)
      end
      GroupCCRuntime_Toggle()
    end
  end
end)
