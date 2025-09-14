-- GroupCCOptions.lua
-- Clean layout + CORRECT scrollbars (wired to real range/value), mouse wheel, next-frame recalcs.
-- Buttons anchored LEFT, renamed "Open/Toggle Window", wider min size so content always fits.

local ADDON_PREFIX = "GroupCC1"

local function DB() _G.GroupCCDB=_G.GroupCCDB or {}; return _G.GroupCCDB end
local function SpellName(id)
  if C_Spell and C_Spell.GetSpellInfo then local i=C_Spell.GetSpellInfo(id); if i and i.name then return i.name end end
  if _G.GetSpellInfo then local n=_G.GetSpellInfo(id); if n then return n end end
  return "Spell "..id
end

local function EnsureDefaults()
  local db=DB()
  db.enabledSpells = db.enabledSpells or {}
  db.priorityOrder = db.priorityOrder or {}
  db.roleOrder     = db.roleOrder     or {"TANK","HEALER","DAMAGER"}
  if db.ttsNext          == nil then db.ttsNext=true  end
  if db.onlyMine         == nil then db.onlyMine=false end
  if db.openInDungeon    == nil then db.openInDungeon=false end
  if db.useRolePriority  == nil then db.useRolePriority=true end
  db.window = db.window or { w=360, h=260, scale=1, point="CENTER", rel="CENTER", x=0, y=0 }
end
EnsureDefaults()

-- Static catalog (or provided by GroupCC.lua)
local CLASS_AOE = _G.GroupCC_ClassAOE or {
  PALADIN = {115750},
  WARRIOR = {46968,5246},
  SHAMAN  = {192058,51490},
  HUNTER  = {236776,186387,462031},
}

-- ---------- Scroll helpers ----------
local function UpdateScrollbar(sf)
  if not sf then return end
  if sf.UpdateScrollChildRect then sf:UpdateScrollChildRect() end

  local range = sf:GetVerticalScrollRange() or 0
  local name  = sf.GetName and sf:GetName()
  local sb    = sf.ScrollBar or (name and _G[name.."ScrollBar"]) or nil
  if not sb then return end

  local cur = sf:GetVerticalScroll() or 0
  sb:SetMinMaxValues(0, range)
  sb:SetValue(cur)

  local need = range > 1
  sb:SetShown(need)
  if not need and cur ~= 0 then sf:SetVerticalScroll(0) end
end

local function WireScrollBar(sf)
  if not sf then return end
  local name = sf.GetName and sf:GetName()
  local sb   = sf.ScrollBar or (name and _G[name.."ScrollBar"]) or nil
  if not sb or sb._wired then return end
  sb._wired = true
  sb:ClearAllPoints()
  sb:SetPoint("TOPRIGHT",    sf, "TOPRIGHT",    0, -16)
  sb:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT", 0,  16)
  sb:SetScript("OnValueChanged", function(self, value)
    sf:SetVerticalScroll(value or 0)
  end)
end

local function HookMouseWheel(sf)
  if not sf or sf._wheelHooked then return end
  sf:EnableMouseWheel(true)
  sf:SetScript("OnMouseWheel", function(self, delta)
    local cur   = self:GetVerticalScroll() or 0
    local step  = math.max(24, self:GetHeight() / 3)
    local range = self:GetVerticalScrollRange() or 0
    local new   = cur - delta * step
    if new < 0 then new = 0 end
    if new > range then new = range end
    self:SetVerticalScroll(new)
    local name = self.GetName and self:GetName()
    local sb   = self.ScrollBar or (name and _G[name.."ScrollBar"]) or nil
    if sb then sb:SetValue(new) end
  end)
  sf._wheelHooked = true
end

-- ---------- Frame ----------
local opt = CreateFrame("Frame","GroupCCOptionsFrame",UIParent,"BasicFrameTemplateWithInset")
opt:SetSize(1000, 680)
opt:SetPoint("CENTER")
opt:Hide()
opt:EnableMouse(true)
opt:SetMovable(true)
opt:RegisterForDrag("LeftButton")
opt:SetScript("OnDragStart", opt.StartMoving)
opt:SetScript("OnDragStop",  opt.StopMovingOrSizing)
opt.title=opt:CreateFontString(nil,"OVERLAY","GameFontHighlight")
opt.title:SetPoint("TOP",0,-6)
opt.title:SetText("GroupCC Options")
tinsert(UISpecialFrames, opt:GetName())

-- Resizing (min width/height so everything fits)
if opt.SetResizeBounds then opt:SetResizeBounds(1000, 500) end
opt:SetResizable(true)
local sizer=CreateFrame("Frame",nil,opt)
sizer:SetSize(18,18); sizer:SetPoint("BOTTOMRIGHT"); sizer:EnableMouse(true)
sizer:SetScript("OnMouseDown", function() opt:StartSizing("BOTTOMRIGHT") end)
sizer:SetScript("OnMouseUp",   function() opt:StopMovingOrSizing() end)
local tex=sizer:CreateTexture(nil,"OVERLAY"); tex:SetAllPoints(); tex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")

-- Buttons (top-left, tidy row)
local btnOpen = CreateFrame("Button", nil, opt, "UIPanelButtonTemplate")
btnOpen:SetSize(180, 22)
btnOpen:SetPoint("TOPLEFT", opt, "TOPLEFT", 18, -58)
btnOpen:SetText("Open/Toggle Window")
btnOpen:SetScript("OnClick", function()
  if GroupCCRuntime_Toggle then GroupCCRuntime_Toggle() end
end)

local btnShare = CreateFrame("Button", nil, opt, "UIPanelButtonTemplate")
btnShare:SetSize(140, 22)
btnShare:SetPoint("LEFT", btnOpen, "RIGHT", 12, 0)
btnShare:SetText("Share to Group")
btnShare:SetScript("OnClick", function()
  local chan = IsInRaid() and "RAID" or (IsInGroup() and "PARTY" or nil)
  if not chan then print("|cff33ff99GroupCC|r: Not in a group.") return end
  local role = table.concat(DB().roleOrder or {"TANK","HEALER","DAMAGER"}, ",")
  C_ChatInfo.SendAddonMessage(ADDON_PREFIX, "V1|ROLE|"..role, chan)
  local pr = table.concat(DB().priorityOrder or {}, ",")
  if pr ~= "" then C_ChatInfo.SendAddonMessage(ADDON_PREFIX, "V1|SPELL|"..pr, chan) end
  local en = {}; for id,enb in pairs(DB().enabledSpells) do if enb then table.insert(en, id) end end
  table.sort(en); if #en>0 then C_ChatInfo.SendAddonMessage(ADDON_PREFIX, "V1|ENBL|"..table.concat(en, ","), chan) end
  print("|cff33ff99GroupCC|r: Shared settings to group.")
end)

local btnSlash = CreateFrame("Button", nil, opt, "UIPanelButtonTemplate")
btnSlash:SetSize(170, 22)
btnSlash:SetPoint("LEFT", btnShare, "RIGHT", 12, 0)
btnSlash:SetText("Show Slash Commands")
btnSlash:SetScript("OnClick", function()
  print("|cff33ff99GroupCC|r commands:")
  print("  /gcc show    - open/toggle the runtime window")
  print("  /gcc now     - TTS: 'Use <spell> now'")
  print("  /gcc options - open this options window")
end)

-- Top controls block
local top = CreateFrame("Frame", nil, opt)
top:SetPoint("TOPLEFT", 10, -92)
top:SetPoint("TOPRIGHT", opt, "TOPRIGHT", -10, -92)
top:SetHeight(220)

local tts=CreateFrame("CheckButton",nil,top,"UICheckButtonTemplate")
tts:SetPoint("TOPLEFT", 6, -4)
tts.text:SetText("Enable Text-to-Speech")
tts:SetChecked(DB().ttsNext)
tts:SetScript("OnClick", function(self) DB().ttsNext = self:GetChecked() and true or false end)

local mine=CreateFrame("CheckButton",nil,top,"UICheckButtonTemplate")
mine:SetPoint("TOPLEFT", tts, "BOTTOMLEFT", 0, -10)
mine.text:SetText("Hear only my spells (auto-TTS)")
mine:SetChecked(DB().onlyMine)
mine:SetScript("OnClick", function(self)
  DB().onlyMine = self:GetChecked() and true or false
  if GroupCCRuntime_ForceRefresh then GroupCCRuntime_ForceRefresh() end
end)

local openDungeon=CreateFrame("CheckButton",nil,top,"UICheckButtonTemplate")
openDungeon:SetPoint("TOPLEFT", mine, "BOTTOMLEFT", 0, -10)
openDungeon.text:SetText("Open window when in dungeon")
openDungeon:SetChecked(DB().openInDungeon)
openDungeon:SetScript("OnClick", function(self) DB().openInDungeon = self:GetChecked() and true or false end)

local scaleLbl = top:CreateFontString(nil,"OVERLAY","GameFontNormal")
scaleLbl:SetPoint("TOPLEFT", openDungeon, "BOTTOMLEFT", 0, -16)
scaleLbl:SetText("Window Scale")

local scale = CreateFrame("Slider", nil, top, "OptionsSliderTemplate")
scale:SetPoint("TOPLEFT", scaleLbl, "BOTTOMLEFT", -2, -8)
scale:SetWidth(420)
scale:SetMinMaxValues(0.7,1.5)
scale:SetValueStep(0.05); scale:SetObeyStepOnDrag(true)
scale.Low:SetText("0.7"); scale.High:SetText("1.5")
scale:SetValue(DB().window.scale or 1)
scale.Text:ClearAllPoints(); scale.Text:SetPoint("LEFT", scale, "RIGHT", 12, 0)
scale.Text:SetText(string.format("Scale: %.2f", scale:GetValue()))
scale:SetScript("OnValueChanged", function(self,val)
  DB().window.scale = val
  scale.Text:SetText(string.format("Scale: %.2f", val))
  if GroupCCRuntimeFrame then GroupCCRuntimeFrame:SetScale(val) end
end)

local roleLbl = top:CreateFontString(nil,"OVERLAY","GameFontNormal")
roleLbl:SetPoint("TOPLEFT", scale, "BOTTOMLEFT", 0, -16)
roleLbl:SetText("Role Priority (highest > lowest)")

local roleDD = CreateFrame("Frame", "GroupCC_RoleDropDown", top, "UIDropDownMenuTemplate")
roleDD:SetPoint("TOPLEFT", roleLbl, "BOTTOMLEFT", -14, -6)
UIDropDownMenu_SetWidth(roleDD, 260)
UIDropDownMenu_SetText(roleDD, table.concat(DB().roleOrder or {"TANK","HEALER","DAMAGER"}," > "))
UIDropDownMenu_Initialize(roleDD, function(self, level)
  local info = UIDropDownMenu_CreateInfo()
  for _,perm in ipairs({
    {"TANK","HEALER","DAMAGER"},
    {"TANK","DAMAGER","HEALER"},
    {"HEALER","TANK","DAMAGER"},
    {"HEALER","DAMAGER","TANK"},
    {"DAMAGER","TANK","HEALER"},
    {"DAMAGER","HEALER","TANK"},
  }) do
    local text = table.concat(perm, " > ")
    info.text = text
    info.func = function()
      DB().roleOrder = {perm[1],perm[2],perm[3]}
      UIDropDownMenu_SetText(roleDD, text)
      if GroupCCRuntime_ForceRefresh then GroupCCRuntime_ForceRefresh() end
    end
    info.checked = (DB().roleOrder[1]==perm[1] and DB().roleOrder[2]==perm[2] and DB().roleOrder[3]==perm[3])
    UIDropDownMenu_AddButton(info, level)
  end
end)

local roleChk = CreateFrame("CheckButton", nil, top, "UICheckButtonTemplate")
roleChk:SetPoint("LEFT", roleDD, "RIGHT", 12, 0)
roleChk.text:SetText("Enable role priority")
roleChk:SetChecked(DB().useRolePriority ~= false)
roleChk:SetScript("OnClick", function(self)
  DB().useRolePriority = self:GetChecked() and true or false
  if GroupCCRuntime_ForceRefresh then GroupCCRuntime_ForceRefresh() end
end)

-- LEFT pane --------------------------------------------------------------------
local leftBox = CreateFrame("Frame", nil, opt, "InsetFrameTemplate3")
leftBox:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, -12)
leftBox:SetPoint("BOTTOMRIGHT", opt, "BOTTOMLEFT", 500, 10)

local leftScroll = CreateFrame("ScrollFrame", "GroupCC_LeftScroll", leftBox, "UIPanelScrollFrameTemplate")
leftScroll:SetPoint("TOPLEFT", 4, -4)
leftScroll:SetPoint("BOTTOMRIGHT", -24, 4)

local leftContent = CreateFrame("Frame", nil, leftScroll)
leftContent:SetSize(1,1)
leftScroll:SetScrollChild(leftContent)
WireScrollBar(leftScroll)
HookMouseWheel(leftScroll)

opt.widgets = {}

function opt:RebuildSpellList()
  for _,w in ipairs(self.widgets) do w:Hide() end
  wipe(self.widgets)
  local y=-4
  for _,cls in ipairs({"PALADIN","WARRIOR","SHAMAN","HUNTER"}) do
    local list=CLASS_AOE[cls]
    if list then
      local hdr=leftContent:CreateFontString(nil,"OVERLAY","GameFontHighlight")
      hdr:SetPoint("TOPLEFT",6,y); hdr:SetText(cls)
      table.insert(self.widgets,hdr); y=y-22
      for _,id in ipairs(list) do
        local cb=CreateFrame("CheckButton",nil,leftContent,"UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT",6,y)
        cb.text:SetText(SpellName(id).." ("..id..")")
        cb:SetChecked(DB().enabledSpells[id] ~= false)
        cb:SetScript("OnClick", function(selfBtn)
          DB().enabledSpells[id] = selfBtn:GetChecked() and true or false
          if GroupCCRuntime_ForceRefresh then GroupCCRuntime_ForceRefresh() end
        end)
        table.insert(self.widgets, cb)
        y=y-24
      end
      y=y-6
    end
  end
  leftContent:SetHeight(-y+8)
  leftContent:SetWidth(leftScroll:GetWidth()-2)

  if leftScroll.SetVerticalScroll then leftScroll:SetVerticalScroll(0) end
  C_Timer.After(0, function() UpdateScrollbar(leftScroll) end)
end

-- RIGHT pane -------------------------------------------------------------------
local rightBox = CreateFrame("Frame", nil, opt, "InsetFrameTemplate3")
rightBox:SetPoint("TOPLEFT", leftBox, "TOPRIGHT", 10, 0)
rightBox:SetPoint("BOTTOMRIGHT", opt, "BOTTOMRIGHT", -10, 10)

local rightScroll = CreateFrame("ScrollFrame", "GroupCC_RightScroll", rightBox, "UIPanelScrollFrameTemplate")
rightScroll:SetPoint("TOPLEFT", 4, -4)
rightScroll:SetPoint("BOTTOMRIGHT", -24, 4)

local rightContent = CreateFrame("Frame", nil, rightScroll)
rightContent:SetSize(1,1)
rightScroll:SetScrollChild(rightContent)
WireScrollBar(rightScroll)
HookMouseWheel(rightScroll)

opt.priorityRows = {}

local function MovePriorityIndex(fromIdx, toIdx)
  local order=DB().priorityOrder
  if not order then return end
  if toIdx < 1 then toIdx = 1 end
  if toIdx > #order then toIdx = #order end
  if fromIdx==toIdx then return end
  local v=table.remove(order, fromIdx)
  table.insert(order, toIdx, v)
  if GroupCCRuntime_ForceRefresh then GroupCCRuntime_ForceRefresh() end
  opt:RebuildPriorityList()
end

function opt:RebuildPriorityList()
  for _,r in ipairs(self.priorityRows) do if r.row then r.row:Hide() end end
  wipe(self.priorityRows)
  local y=-4
  for i,spellID in ipairs(DB().priorityOrder) do
    local row=CreateFrame("Frame", nil, rightContent)
    row:SetPoint("TOPLEFT",6,y)
    row:SetSize(420,24)

    local txt=row:CreateFontString(nil,"OVERLAY","GameFontNormal")
    txt:SetPoint("LEFT",0,0)
    txt:SetText(string.format("%d) %s", i, SpellName(spellID)))

    local up =CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    up:SetSize(48,20); up:SetPoint("RIGHT",-96,0); up:SetText("Up")
    up:SetScript("OnClick", function() MovePriorityIndex(i, i-1) end)

    local dn =CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    dn:SetSize(48,20); dn:SetPoint("RIGHT",-48,0); dn:SetText("Down")
    dn:SetScript("OnClick", function() MovePriorityIndex(i, i+1) end)

    local topBtn=CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    topBtn:SetSize(48,20); topBtn:SetPoint("RIGHT",0,0); topBtn:SetText("Top")
    topBtn:SetScript("OnClick", function() MovePriorityIndex(i, 1) end)

    table.insert(self.priorityRows,{row=row})
    y=y-26
  end

  rightContent:SetHeight(-y+8)
  rightContent:SetWidth(rightScroll:GetWidth()-2)

  if rightScroll.SetVerticalScroll then rightScroll:SetVerticalScroll(0) end
  C_Timer.After(0, function() UpdateScrollbar(rightScroll) end)
end

-- Build UI now
opt:RebuildSpellList()
opt:RebuildPriorityList()

-- Keep scrollbars honest on resize/show (next-frame so sizes are final)
opt:SetScript("OnSizeChanged", function()
  leftContent:SetWidth(leftScroll:GetWidth()-2)
  rightContent:SetWidth(rightScroll:GetWidth()-2)
  C_Timer.After(0, function()
    UpdateScrollbar(leftScroll)
    UpdateScrollbar(rightScroll)
  end)
end)
opt:SetScript("OnShow", function()
  leftContent:SetWidth(leftScroll:GetWidth()-2)
  rightContent:SetWidth(rightScroll:GetWidth()-2)
  C_Timer.After(0, function()
    UpdateScrollbar(leftScroll)
    UpdateScrollbar(rightScroll)
  end)
end)

leftScroll:SetScript("OnScrollRangeChanged", function() UpdateScrollbar(leftScroll) end)
rightScroll:SetScript("OnScrollRangeChanged", function() UpdateScrollbar(rightScroll) end)

function GroupCCOptions_Toggle()
  opt:SetShown(not opt:IsShown())
  if opt:IsShown() then
    leftContent:SetWidth(leftScroll:GetWidth()-2)
    rightContent:SetWidth(rightScroll:GetWidth()-2)
    C_Timer.After(0, function()
      UpdateScrollbar(leftScroll)
      UpdateScrollbar(rightScroll)
    end)
  end
end
