-- GroupCCRuntime.lua
-- Queue, role-priority sorting, TTS, resizable window, background auto-TTS
-- Adds: receiving sync with CONFIRM POPUP, and broadcasted /gccnext calls.

GroupCC_LastError = nil
GroupCCRuntime_InitDone = false

local ADDON_PREFIX = "GroupCC1"

local function DB() _G.GroupCCDB=_G.GroupCCDB or {}; return _G.GroupCCDB end
local function safeErr(msg) print("|cffff4444GroupCC runtime error:|r", msg) end

local function Init()
  local wipe = wipe or function(t) for k in pairs(t) do t[k]=nil end end

  -- ---------- State ----------
  local frame
  local rows = {}
  local MAX_ROWS = 24
  local LINE_H  = 18
  local TOP_PAD = 30
  local LEFT_PAD = 12

  local partyByGUID, classByGUID = {}, {}
  local spellsByGUID, lastCast   = {}, {}
  local readySince               = {}   -- readySince[guid][spellID] = time when it hit 0s
  local entries, priorityIndex   = {}, {}
  local lastAnnouncedTopKey      = nil
  local ticker, UPDATE_INTERVAL  = 0, 0.2

  -- Pending sync for confirm dialog
  local pendingRole, pendingSpell, pendingSender

  -- ---------- Helpers ----------
  local function now() return GetTime() end

  local function SpellName(id)
    if C_Spell and C_Spell.GetSpellInfo then
      local info = C_Spell.GetSpellInfo(id)
      if info and info.name then return info.name end
    end
    if _G.GetSpellInfo then
      local n = _G.GetSpellInfo(id)
      if n then return n end
    end
    return "Spell "..id
  end

  local function BaseCD(id)
    if _G.GetSpellBaseCooldown then
      local ms=_G.GetSpellBaseCooldown(id)
      if ms and ms>0 then return ms/1000 end
    end
    return 0
  end

  local function ColorName(name, cls)
    local c=RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls]
    return c and ("|cff%02x%02x%02x%s|r"):format(c.r*255,c.g*255,c.b*255,name) or name
  end

  -- Role weight from DB().roleOrder (index = priority)
  local function RoleWeight(unit)
    local order = DB().roleOrder or {"TANK","HEALER","DAMAGER"}
    local map = {}; for i,role in ipairs(order) do map[role]=i end
    local r = UnitGroupRolesAssigned(unit)
    return map[r] or 99
  end

  -- ---------- Defaults ----------
  local function DefaultOrder()
    local o={}
    for _,cls in ipairs({"PALADIN","WARRIOR","SHAMAN","HUNTER"}) do
      local l=_G.GroupCC_ClassAOE and _G.GroupCC_ClassAOE[cls]
      if l then for _,id in ipairs(l) do table.insert(o,id) end end
    end
    return o
  end

  local function EnsureDefaults()
    local db=DB()
    db.enabledSpells = db.enabledSpells or {}
    for _,id in ipairs(DefaultOrder()) do
      if db.enabledSpells[id]==nil then db.enabledSpells[id]=true end
    end
    db.priorityOrder = db.priorityOrder or DefaultOrder()
    if #db.priorityOrder==0 then db.priorityOrder=DefaultOrder() end
    if db.ttsNext==nil   then db.ttsNext=true end
    if db.onlyMine==nil  then db.onlyMine=false end
    db.window = db.window or { w=360, h=260, scale=1, point="CENTER", rel="CENTER", x=0, y=0 }
    db.roleOrder = db.roleOrder or {"TANK","HEALER","DAMAGER"}
  end
  EnsureDefaults()

  -- ---------- Priority ----------
  local function BuildPriorityIndex()
    wipe(priorityIndex)
    for i,id in ipairs(DB().priorityOrder) do
      priorityIndex[id]=i
    end
  end

  -- ---------- Party scan ----------
  local function Seed(guid, cls)
    spellsByGUID[guid]=spellsByGUID[guid] or {}
    lastCast[guid]=lastCast[guid] or {}
    readySince[guid]=readySince[guid] or {}
    local list=_G.GroupCC_ClassAOE and _G.GroupCC_ClassAOE[cls]
    if not list then return end
    for _,id in ipairs(list) do
      if DB().enabledSpells[id] then
        spellsByGUID[guid][id]=true
        if not lastCast[guid][id] then
          lastCast[guid][id]=now()-BaseCD(id)                      -- seed ready
          if not readySince[guid][id] then readySince[guid][id]=now()-9999 end
        end
      end
    end
  end

  local function RebuildParty()
    wipe(partyByGUID); wipe(classByGUID); wipe(spellsByGUID)
    local me=UnitGUID("player")
    if me then
      local _,cls=UnitClass("player")
      partyByGUID[me]="player"; classByGUID[me]=cls; Seed(me,cls)
    end
    local n=GetNumGroupMembers()
    if n and n>0 then
      if IsInRaid() then
        for i=1,n do
          local u="raid"..i
          if UnitExists(u) then
            local g=UnitGUID(u)
            if g then local _,c=UnitClass(u); partyByGUID[g]=u; classByGUID[g]=c; Seed(g,c) end
          end
        end
      else
        for i=1,GetNumSubgroupMembers() do
          local u="party"..i
          if UnitExists(u) then
            local g=UnitGUID(u)
            if g then local _,c=UnitClass(u); partyByGUID[g]=u; classByGUID[g]=c; Seed(g,c) end
          end
        end
      end
    end
  end

  -- ---------- Entries ----------
  local function BuildEntries()
    wipe(entries)
    for guid,pool in pairs(spellsByGUID) do
      local unit=partyByGUID[guid]
      if unit then
        local raw=UnitName(unit) or "?"
        local name=ColorName(raw, classByGUID[guid])
        local roleW=RoleWeight(unit)
        for id in pairs(pool) do
          if DB().enabledSpells[id] then
            local cd=BaseCD(id)
            local cast=lastCast[guid][id] or (now()-cd)
            local remain=(cast+cd)-now(); if remain<0 then remain=0 end

            readySince[guid]=readySince[guid] or {}
            if remain==0 then
              if not readySince[guid][id] then readySince[guid][id]=now() end
            else
              readySince[guid][id]=nil
            end

            table.insert(entries,{
              guid=guid, unit=unit, raw=raw, name=name,
              spellID=id, readyIn=remain, readySince=readySince[guid][id] or math.huge,
              role=roleW, pri=priorityIndex[id] or 999
            })
          end
        end
      end
    end

    table.sort(entries,function(a,b)
      local aReady, bReady = (a.readyIn==0), (b.readyIn==0)
      if aReady and bReady then
        if a.role~=b.role             then return a.role < b.role end      -- Role order
        if a.readySince~=b.readySince then return a.readySince < b.readySince end -- FIFO ready within role
        if a.pri~=b.pri               then return a.pri < b.pri end        -- Manual spell priority
        return a.raw < b.raw
      end
      if a.readyIn~=b.readyIn         then return a.readyIn < b.readyIn end
      if a.role~=b.role               then return a.role < b.role end
      if a.pri~=b.pri                 then return a.pri < b.pri end
      return a.raw < b.raw
    end)
  end

  -- ---------- UI paint ----------
  local function Paint()
    local usableW = math.max(50, frame:GetWidth() - LEFT_PAD*2)
    for i=1,MAX_ROWS do
      local r=rows[i]
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", frame, "TOPLEFT", LEFT_PAD, -TOP_PAD - (i-1)*LINE_H)
      r:SetWidth(usableW); r:SetHeight(LINE_H)
      r:SetJustifyH("LEFT"); r:SetJustifyV("TOP")
      if r.SetWordWrap then r:SetWordWrap(false) end
      if r.SetNonSpaceWrap then r:SetNonSpaceWrap(false) end
      r:Hide(); r:SetText("")
    end
    local visible = math.min(#entries, MAX_ROWS)
    for i=1,visible do
      local e=entries[i]; local r=rows[i]
      r:SetText(("%s - %s (%.1fs)"):format(e.name, SpellName(e.spellID), e.readyIn))
      r:Show()
    end
  end

  -- ---------- Auto-TTS ----------
  local function AutoTTS()
    local db = DB(); if not db.ttsNext then return end
    local top = (entries[1] and entries[1].readyIn==0) and entries[1] or nil
    if db.onlyMine and (not top or top.unit~="player") then return end
    if not top then return end
    local key = "TOP:"..top.guid..":"..top.spellID
    if key == lastAnnouncedTopKey then return end
    if C_VoiceChat and C_VoiceChat.SpeakText then
      C_VoiceChat.SpeakText(0, SpellName(top.spellID).." next", Enum.VoiceTtsDestination.LocalPlayback, 0, 100)
    else
      print("|cff33ff99GroupCC|r:", SpellName(top.spellID).." next")
    end
    lastAnnouncedTopKey = key
  end

  local function Refresh()
    BuildPriorityIndex()
    BuildEntries()
    Paint()
    AutoTTS()
  end

  -- ---------- Reset runtime order ----------
  local function ResetRuntimeOrder()
    for guid, pool in pairs(spellsByGUID) do
      readySince[guid] = readySince[guid] or {}
      for spellID in pairs(pool) do
        local cd   = BaseCD(spellID)
        local cast = lastCast[guid][spellID] or (now() - cd)
        local rem  = (cast + cd) - now()
        if rem <= 0 then
          readySince[guid][spellID] = now()
        end
      end
    end
    lastAnnouncedTopKey = nil
    Refresh()
  end

  -- ---------- Window save/restore ----------
  local function SaveWindow()
    local db=DB(); local p,_,r,x,y=frame:GetPoint(1)
    db.window.w, db.window.h = frame:GetWidth(), frame:GetHeight()
    db.window.scale = frame:GetScale()
    db.window.point, db.window.rel, db.window.x, db.window.y = p, r, x, y
  end

  local function RestoreWindow()
    local w=DB().window
    frame:SetSize(w.w or 360, w.h or 260)
    frame:SetScale(w.scale or 1)
    frame:ClearAllPoints()
    frame:SetPoint(w.point or "CENTER", UIParent, w.rel or "CENTER", w.x or 0, w.y or 0)
  end

  -- ---------- UI ----------
  frame=CreateFrame("Frame","GroupCCRuntimeFrame",UIParent,"BasicFrameTemplateWithInset")
  frame:SetResizable(true)
  if frame.SetResizeBounds then frame:SetResizeBounds(240,140) elseif frame.SetMinResize then frame:SetMinResize(240,140) end
  frame:SetSize(360,260)
  frame:SetPoint("CENTER")
  frame:Hide()
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing(); SaveWindow() end)

  -- sizer
  local sizer=CreateFrame("Frame", nil, frame)
  sizer:SetSize(18,18)
  sizer:SetPoint("BOTTOMRIGHT")
  sizer:EnableMouse(true)
  sizer:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
  sizer:SetScript("OnMouseUp",   function() frame:StopMovingOrSizing(); SaveWindow() end)
  local tex=sizer:CreateTexture(nil,"OVERLAY"); tex:SetAllPoints(); tex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")

  frame.title=frame:CreateFontString(nil,"OVERLAY","GameFontHighlight")
  frame.title:SetPoint("TOP",0,-5); frame.title:SetText("GroupCC")

  -- Reset button aligned with Close "X"
  local close = _G[frame:GetName().."CloseButton"]
  local resetBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  resetBtn:SetText("Reset")
  resetBtn:SetSize(56, 20)
  resetBtn:SetScale(0.9)
  resetBtn:ClearAllPoints()
  if close then
    resetBtn:SetPoint("RIGHT", close, "LEFT", -6, 0)
  else
    resetBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -28, -6)
  end
  resetBtn:SetScript("OnClick", function() ResetRuntimeOrder() end)
  resetBtn:SetScript("OnEnter", function(selfBtn)
    GameTooltip:SetOwner(selfBtn, "ANCHOR_LEFT")
    GameTooltip:SetText("Reset queue order", 1,1,1)
    GameTooltip:AddLine("Re-sorts ready spells by Role → Spell priority → Name.", 0.85,0.85,0.85, true)
    GameTooltip:Show()
  end)
  resetBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

  -- rows
  for i=1,MAX_ROWS do
    local fs=frame:CreateFontString(nil,"OVERLAY","GameFontNormal")
    fs:SetText(""); fs:Hide()
    rows[i]=fs
  end

  frame:SetScript("OnSizeChanged", function() SaveWindow(); Refresh() end)
  frame:SetScript("OnUpdate", function(_,dt)
    if not frame:IsShown() then return end
    ticker=ticker+dt
    if ticker>=UPDATE_INTERVAL then Refresh(); ticker=0 end
  end)

  -- ---------- Confirm popup for incoming sync ----------
  StaticPopupDialogs = StaticPopupDialogs or {}
  StaticPopupDialogs["GROUPCC_ACCEPT_SYNC"] = {
    text = "GroupCC: %s wants to update your settings.\n\nApply %s?",
    button1 = "Accept",
    button2 = "Decline",
    OnAccept = function(self, data)
      if data and data.kind=="ROLE" and data.payload then
        DB().roleOrder = data.payload
      elseif data and data.kind=="SPELL" and data.payload then
        DB().priorityOrder = data.payload
      end
      if GroupCCRuntime_ForceRefresh then GroupCCRuntime_ForceRefresh() end
      print("|cff33ff99GroupCC|r: Update applied.")
    end,
    timeout = 10,
    whileDead = 1,
    hideOnEscape = 1,
    preferredIndex = 3,
  }

  local function showConfirm(kind, sender, payload)
    local human = (kind=="ROLE") and "role priority" or "spell priority"
    local data = { kind = kind, payload = payload }
    StaticPopup_Show("GROUPCC_ACCEPT_SYNC", sender or "someone", human, data)
  end

  -- ---------- Events ----------
  local ef=CreateFrame("Frame")
  ef:RegisterEvent("PLAYER_ENTERING_WORLD")
  ef:RegisterEvent("GROUP_ROSTER_UPDATE")
  ef:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
  ef:RegisterEvent("CHAT_MSG_ADDON")
  ef:SetScript("OnEvent", function(_,ev, ...)
    if ev=="PLAYER_ENTERING_WORLD" or ev=="GROUP_ROSTER_UPDATE" then
      local oldLC,lastRS = lastCast,readySince
      RebuildParty()
      for g,sp in pairs(oldLC) do lastCast[g]=lastCast[g] or {}; for id,t in pairs(sp) do if not lastCast[g][id] then lastCast[g][id]=t end end end
      for g,sp in pairs(lastRS or {}) do readySince[g]=readySince[g] or {}; for id,t in pairs(sp) do if not readySince[g][id] then readySince[g][id]=t end end end
      lastAnnouncedTopKey=nil
      if frame:IsShown() then Refresh() end

    elseif ev=="COMBAT_LOG_EVENT_UNFILTERED" then
      local _, sub, _, src, _, _, _, _, _, _, _, id = CombatLogGetCurrentEventInfo()
      if sub=="SPELL_CAST_SUCCESS" and partyByGUID[src] then
        if spellsByGUID[src] and spellsByGUID[src][id] and DB().enabledSpells[id] then
          lastCast[src][id]=now()
          readySince[src]=readySince[src] or {}; readySince[src][id]=nil
          lastAnnouncedTopKey=nil
          if frame:IsShown() then Refresh() end
        end
      end

    elseif ev=="CHAT_MSG_ADDON" then
      local prefix, text, channel, sender = ...
      if prefix ~= ADDON_PREFIX then return end
      if not UnitInParty(sender) and not UnitInRaid(sender) then return end

      -- Expect:
      --  "V1|ROLE|TANK,HEALER,DAMAGER"
      --  "V1|SPELL|46968,115750,..."
      --  "V1|CALL|NOW|spellID|guid"
      local ver, kind, rest = string.match(text, "^([^|]+)|([^|]+)|(.+)$")
      if ver ~= "V1" or not kind then return end

      if kind == "ROLE" then
        local order = {}
        for role in string.gmatch(rest, "([^,]+)") do
          role = string.upper((role or ""):match("^%s*(.-)%s*$"))
          if role=="TANK" or role=="HEALER" or role=="DAMAGER" then table.insert(order, role) end
        end
        if #order==3 then
          showConfirm("ROLE", sender, order)
        end

      elseif kind == "SPELL" then
        local newOrder = {}
        for id in string.gmatch(rest, "%d+") do table.insert(newOrder, tonumber(id)) end
        if #newOrder > 0 then
          showConfirm("SPELL", sender, newOrder)
        end

      elseif kind == "CALL" then
        local callType, a, b = rest:match("^([^|]+)|([^|]+)|([^|]+)$")
        if callType == "NOW" then
          local spellID = tonumber(a)
          local targetGUID = b
          if spellID and targetGUID and targetGUID == UnitGUID("player") then
            local line = "Use "..SpellName(spellID).." now"
            if C_VoiceChat and C_VoiceChat.SpeakText then
              C_VoiceChat.SpeakText(0, line, Enum.VoiceTtsDestination.LocalPlayback, 0, 100)
            else
              print("|cff33ff99GroupCC|r:", line)
            end
          end
        end
      end
    end
  end)

  -- ---------- Public API ----------
  function GroupCCRuntime_Toggle()
    EnsureDefaults()
    if frame:IsShown() then
      frame:Hide()
    else
      RestoreWindow()
      BuildPriorityIndex(); BuildEntries(); Paint()
      frame:Show()
    end
  end

  -- Local-only TTS: announce the true global next on your client
  function GroupCCRuntime_AnnounceNow()
    EnsureDefaults(); BuildPriorityIndex(); BuildEntries()
    local e=entries[1]
    if not e then
      print("|cff33ff99GroupCC|r: No AoE CC in queue.")
      return
    end
    local line = "Use "..SpellName(e.spellID).." now"
    if C_VoiceChat and C_VoiceChat.SpeakText then
      C_VoiceChat.SpeakText(0, line, Enum.VoiceTtsDestination.LocalPlayback, 0, 100)
    else
      print("|cff33ff99GroupCC|r:", line)
    end
  end

  -- Broadcast to party/raid: pick the top entry and send a targeted "NOW" call
  function GroupCCRuntime_CallNext(broadcast)
    EnsureDefaults(); BuildPriorityIndex(); BuildEntries()
    local e=entries[1]
    if not e then
      print("|cff33ff99GroupCC|r: No AoE CC in queue.")
      return
    end
    if not broadcast then
      -- local behavior fallback
      GroupCCRuntime_AnnounceNow()
      return
    end
    local chan = IsInRaid() and "RAID" or (IsInGroup() and "PARTY" or nil)
    if not chan then print("|cff33ff99GroupCC|r: Not in a group.") return end
    local payload = ("V1|CALL|NOW|%d|%s"):format(e.spellID, e.guid)
    C_ChatInfo.SendAddonMessage(ADDON_PREFIX, payload, chan)
    print("|cff33ff99GroupCC|r: Called "..(e.raw or "?").." to use "..SpellName(e.spellID).." now.")
  end

  function GroupCCRuntime_DebugTop()
    BuildPriorityIndex(); BuildEntries()
    local e=entries[1]
    if e then
      print(("Top: %s - %s (%.1fs)"):format(e.name, SpellName(e.spellID), e.readyIn))
    else
      print("Top: (none)")
    end
  end

  function GroupCCRuntime_ForceRefresh()
    EnsureDefaults(); RebuildParty(); Refresh()
  end

  -- Background TTS ticker
  if C_Timer and C_Timer.NewTicker then
    C_Timer.NewTicker(0.4, function()
      pcall(function()
        BuildPriorityIndex()
        BuildEntries()
        AutoTTS()
      end)
    end)
  end
end

-- Protected init
local ok,err=pcall(Init)
if not ok then
  GroupCC_LastError=err
  safeErr(err)
else
  GroupCCRuntime_InitDone=true
  print("|cff33ff99GroupCC|r: runtime loaded.")
end
