-- GroupCC.lua
-- Core: SavedVariables, catalog, slash commands

GroupCCDB = GroupCCDB or {}

-- AoE CC catalog
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
  if db.ttsNext==nil then db.ttsNext=true end
  if db.onlyMine==nil then db.onlyMine=false end
  db.window = db.window or { w=360, h=260, scale=1, point="CENTER", rel="CENTER", x=0, y=0 }
end
initDB()

local function SpellName(id)
  if C_Spell and C_Spell.GetSpellInfo then local i=C_Spell.GetSpellInfo(id); if i and i.name then return i.name end end
  if GetSpellInfo then local n=GetSpellInfo(id); if n then return n end end
  return "Spell "..id
end

local function printHelp()
  print("|cff33ff99GroupCC|r commands:")
  print("  /gccshow         - toggle the GroupCC list window")
  print("  /gccnow          - TTS: 'Use <spell> now' (global next)")
  print("  /gcc options     - open options window")
  print("  /gcc hearall     - hear everyone (auto-TTS)")
  print("  /gcc hearonly    - hear only my spells (auto-TTS)")
  print("  /gcc status      - show current settings")
  print("  /gcc help        - show this help")
end

SLASH_GROUPCC1 = "/gcc"
SlashCmdList["GROUPCC"] = function(msg)
  msg = (msg or ""):lower():match("^%s*(.-)%s*$")
  if msg=="" or msg=="help" or msg=="?" then
    printHelp()
  elseif msg=="show" or msg=="window" or msg=="toggle" then
    if GroupCCRuntime_Toggle then GroupCCRuntime_Toggle() else print("GroupCC: runtime not loaded") end
  elseif msg=="now" then
    if GroupCCRuntime_AnnounceNow then GroupCCRuntime_AnnounceNow() else print("GroupCC: runtime not loaded") end
  elseif msg=="options" or msg=="opt" or msg=="config" then
    if GroupCCOptions_Toggle then GroupCCOptions_Toggle() else print("GroupCC: options not loaded") end
  elseif msg=="hearall" then
    GroupCCDB.onlyMine=false; print("|cff33ff99GroupCC|r: Auto-TTS will announce everyone.")
    if GroupCCRuntime_ForceRefresh then GroupCCRuntime_ForceRefresh() end
  elseif msg=="hearonly" then
    GroupCCDB.onlyMine=true; print("|cff33ff99GroupCC|r: Auto-TTS will announce only your spells.")
    if GroupCCRuntime_ForceRefresh then GroupCCRuntime_ForceRefresh() end
  elseif msg=="status" then
    local who = GroupCCDB.onlyMine and "only yours" or "everyone"
    print(("|cff33ff99GroupCC|r: TTS=%s, Auto-TTS hears %s. Rows show all players."):format(
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
