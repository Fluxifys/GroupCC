-- GroupCCOptions.lua
-- Wider, movable options window with working scrollbars that hide when not needed.
-- TTS + OnlyMine toggles, scale slider, per-spell toggles, and priority editor.

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
  if db.ttsNext==nil then db.ttsNext=true end
  if db.onlyMine==nil then db.onlyMine=false end
  db.window = db.window or {w=360,h=260,scale=1,point="CENTER",rel="CENTER",x=0,y=0}
end
EnsureDefaults()

-- Helper: hide scrollbar if not needed
local function UpdateScrollbar(sf)
  if not sf then return end
  if sf.UpdateScrollChildRect then sf:UpdateScrollChildRect() end
  local range = sf:GetVerticalScrollRange() or 0
  local sb = sf.ScrollBar or (sf.GetName and _G[sf:GetName().."ScrollBar"]) -- template differences
  if sb then
    if range <= 0.5 then sb:Hide() else sb:Show() end
  end
end

local opt = CreateFrame("Frame","GroupCCOptionsFrame",UIParent,"BasicFrameTemplateWithInset")
opt:SetSize(760, 600)  -- wider
opt:SetPoint("CENTER")
opt:Hide()
opt:EnableMouse(true)
opt:SetMovable(true)
opt:RegisterForDrag("LeftButton")
opt:SetScript("OnDragStart", opt.StartMoving)
opt:SetScript("OnDragStop",  opt.StopMovingOrSizing)

-- (optional) allow resizing if you want
if opt.SetResizeBounds then opt:SetResizeBounds(640, 420) end
opt:SetResizable(true)
local sizer=CreateFrame("Frame",nil,opt)
sizer:SetSize(18,18); sizer:SetPoint("BOTTOMRIGHT"); sizer:EnableMouse(true)
sizer:SetScript("OnMouseDown", function() opt:StartSizing("BOTTOMRIGHT") end)
sizer:SetScript("OnMouseUp",   function() opt:StopMovingOrSizing() end)
local tex=sizer:CreateTexture(nil,"OVERLAY"); tex:SetAllPoints(); tex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")

opt.title=opt:CreateFontString(nil,"OVERLAY","GameFontHighlight")
opt.title:SetPoint("TOP",0,-6)
opt.title:SetText("GroupCC Options")

-- Top toggles
local tts=CreateFrame("CheckButton",nil,opt,"UICheckButtonTemplate")
tts:SetPoint("TOPLEFT",12,-34)
tts.text:SetText("Enable Text-to-Speech")
tts:SetChecked(DB().ttsNext)
tts:SetScript("OnClick", function(self) DB().ttsNext = self:GetChecked() and true or false end)

local mine=CreateFrame("CheckButton",nil,opt,"UICheckButtonTemplate")
mine:SetPoint("TOPLEFT", tts, "BOTTOMLEFT", 0, -8)
mine.text:SetText("Hear only my spells (auto-TTS)")
mine:SetChecked(DB().onlyMine)
mine:SetScript("OnClick", function(self)
  DB().onlyMine = self:GetChecked() and true or false
  if GroupCCRuntime_ForceRefresh then GroupCCRuntime_ForceRefresh() end
end)

-- Scale
local scaleLbl=opt:CreateFontString(nil,"OVERLAY","GameFontNormal")
scaleLbl:SetPoint("TOPLEFT", mine, "BOTTOMLEFT", 4, -14)
scaleLbl:SetText("Window Scale")

local scale=CreateFrame("Slider", nil, opt, "OptionsSliderTemplate")
scale:SetPoint("TOPLEFT", scaleLbl, "BOTTOMLEFT", -6, -8)
scale:SetWidth(200)
scale:SetMinMaxValues(0.7,1.5)
scale:SetValueStep(0.05)
scale:SetObeyStepOnDrag(true)
scale.Low:SetText("0.7")
scale.High:SetText("1.5")
scale:SetValue(DB().window.scale or 1)
scale.Text:ClearAllPoints(); scale.Text:SetPoint("TOP", scale, "BOTTOM", 0, 0)
scale.Text:SetText(string.format("Scale: %.2f", scale:GetValue()))
scale:SetScript("OnValueChanged", function(self,val)
  DB().window.scale = val
  scale.Text:SetText(string.format("Scale: %.2f", val))
  if GroupCCRuntimeFrame then GroupCCRuntimeFrame:SetScale(val) end
end)

local reset=CreateFrame("Button", nil, opt, "UIPanelButtonTemplate")
reset:SetSize(220, 24)
reset:SetPoint("LEFT", scale, "RIGHT", 16, 0)
reset:SetText("Reset All to Defaults")
reset:SetScript("OnClick", function()
  DB().enabledSpells = {}
  for _, list in pairs(_G.GroupCC_ClassAOE or {}) do
    for _, id in ipairs(list) do DB().enabledSpells[id] = true end
  end
  if GroupCCRuntime_ForceRefresh then GroupCCRuntime_ForceRefresh() end
  opt:RebuildSpellList(); opt:RebuildPriorityList()
end)

-- Left scroll: per-spell toggles
local leftBox = CreateFrame("Frame", nil, opt, "InsetFrameTemplate3")
leftBox:SetPoint("TOPLEFT", 10, -180)
leftBox:SetPoint("BOTTOMRIGHT", -390, 10)

local leftScroll = CreateFrame("ScrollFrame", "GroupCC_LeftScroll", leftBox, "UIPanelScrollFrameTemplate")
leftScroll:SetPoint("TOPLEFT", 4, -4)
leftScroll:SetPoint("BOTTOMRIGHT", -24, 4)

local leftContent = CreateFrame("Frame", nil, leftScroll)
leftContent:SetSize(1,1)
leftScroll:SetScrollChild(leftContent)

opt.widgets = {}

function opt:RebuildSpellList()
  for _,w in ipairs(self.widgets) do w:Hide() end
  wipe(self.widgets)
  local y=-4
  for _,cls in ipairs({"PALADIN","WARRIOR","SHAMAN","HUNTER"}) do
    local list=_G.GroupCC_ClassAOE and _G.GroupCC_ClassAOE[cls]
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
  UpdateScrollbar(leftScroll)
end

-- Right scroll: priority editor
local rightBox = CreateFrame("Frame", nil, opt, "InsetFrameTemplate3")
rightBox:SetPoint("TOPLEFT", opt, "TOPRIGHT", -380, -180)
rightBox:SetPoint("BOTTOMRIGHT", -10, 10)

local rightScroll = CreateFrame("ScrollFrame", "GroupCC_RightScroll", rightBox, "UIPanelScrollFrameTemplate")
rightScroll:SetPoint("TOPLEFT", 4, -4)
rightScroll:SetPoint("BOTTOMRIGHT", -24, 4)

local rightContent = CreateFrame("Frame", nil, rightScroll)
rightContent:SetSize(1,1)
rightScroll:SetScrollChild(rightContent)

opt.priorityRows = {}

local function MovePriorityIndex(fromIdx, toIdx)
  local order=DB().priorityOrder
  if not order or toIdx<1 or toIdx>#order then return end
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
    row:SetSize(320,24)

    local txt=row:CreateFontString(nil,"OVERLAY","GameFontNormal")
    txt:SetPoint("LEFT",0,0)
    txt:SetText(string.format("%d) %s", i, SpellName(spellID)))

    local up =CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    up:SetSize(48,20); up:SetPoint("RIGHT",-96,0); up:SetText("Up")
    up:SetScript("OnClick", function() MovePriorityIndex(i, i-1) end)

    local dn =CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    dn:SetSize(48,20); dn:SetPoint("RIGHT",-48,0); dn:SetText("Down")
    dn:SetScript("OnClick", function() MovePriorityIndex(i, i+1) end)

    local top=CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    top:SetSize(48,20); top:SetPoint("RIGHT",0,0); top:SetText("Top")
    top:SetScript("OnClick", function() MovePriorityIndex(i, 1) end)

    table.insert(self.priorityRows,{row=row})
    y=y-26
  end

  rightContent:SetHeight(-y+8)
  rightContent:SetWidth(rightScroll:GetWidth()-2)
  UpdateScrollbar(rightScroll)
end

-- Build UI now
opt:RebuildSpellList()
opt:RebuildPriorityList()

-- Keep scrollbars honest on resize
opt:SetScript("OnSizeChanged", function()
  leftContent:SetWidth(leftScroll:GetWidth()-2)
  rightContent:SetWidth(rightScroll:GetWidth()-2)
  UpdateScrollbar(leftScroll)
  UpdateScrollbar(rightScroll)
end)
leftScroll:SetScript("OnScrollRangeChanged", function() UpdateScrollbar(leftScroll) end)
rightScroll:SetScript("OnScrollRangeChanged", function() UpdateScrollbar(rightScroll) end)

function GroupCCOptions_Toggle()
  opt:SetShown(not opt:IsShown())
  if opt:IsShown() then
    UpdateScrollbar(leftScroll)
    UpdateScrollbar(rightScroll)
  end
end

-- Make the Options window close when the Escape key / Game Menu is opened
table.insert(UISpecialFrames, "GroupCCOptionsFrame")

