-- GroupCC Options (larger window + tidy layout)
-- - Bigger frame (900 x 720)
-- - Toolbar right-aligned under header
-- - ASCII ">" in labels (fixes missing glyph)
-- - Scroll panes spaced lower, scrollbars auto-hide
-- - ESC closes window

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
  db.roleOrder = db.roleOrder or {"TANK","HEALER","DAMAGER"}
  if db.autoOpenDungeon == nil then db.autoOpenDungeon = false end
end
EnsureDefaults()

local function UpdateScrollbar(sf)
  if not sf then return end
  if sf.UpdateScrollChildRect then sf:UpdateScrollChildRect() end
  local range = sf:GetVerticalScrollRange() or 0
  local sb = sf.ScrollBar or (sf.GetName and _G[sf:GetName().."ScrollBar"])
  if sb then if range <= 0.5 then sb:Hide() else sb:Show() end end
end

-- === Shell ===
local opt = CreateFrame("Frame","GroupCCOptionsFrame",UIParent,"BasicFrameTemplateWithInset")
opt:SetSize(900, 720)                             -- bigger!
opt:SetPoint("CENTER")
opt:Hide()
opt:EnableMouse(true)
opt:SetMovable(true)
opt:RegisterForDrag("LeftButton")
opt:SetScript("OnDragStart", opt.StartMoving)
opt:SetScript("OnDragStop",  opt.StopMovingOrSizing)
if opt.SetResizeBounds then opt:SetResizeBounds(860, 640) end
opt:SetResizable(true)
local sizer=CreateFrame("Frame",nil,opt)
sizer:SetSize(18,18); sizer:SetPoint("BOTTOMRIGHT"); sizer:EnableMouse(true)
sizer:SetScript("OnMouseDown", function() opt:StartSizing("BOTTOMRIGHT") end)
sizer:SetScript("OnMouseUp",   function() opt:StopMovingOrSizing() end)
local tex=sizer:CreateTexture(nil,"OVERLAY"); tex:SetAllPoints(); tex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")

opt.title=opt:CreateFontString(nil,"OVERLAY","GameFontHighlight")
opt.title:SetPoint("TOP",0,-6)
opt.title:SetText("GroupCC Options")

-- === Left column toggles ===
local topY = -34
local function addCheck(label, y, checked, onClick)
  local cb=CreateFrame("CheckButton",nil,opt,"UICheckButtonTemplate")
  cb:SetPoint("TOPLEFT",12,y)
  cb.text:SetText(label)
  cb:SetChecked(checked)
  cb:SetScript("OnClick", onClick)
  return cb
end

local tts = addCheck("Enable Text-to-Speech", topY, DB().ttsNext, function(self)
  DB().ttsNext = self:GetChecked() and true or false
end)

local mine = addCheck("Hear only my spells (auto-TTS)", topY-28, DB().onlyMine, function(self)
  DB().onlyMine = self:GetChecked() and true or false
  if GroupCCRuntime_ForceRefresh then GroupCCRuntime_ForceRefresh() end
end)

local autoOpen = addCheck("Open window when in dungeon", topY-56, DB().autoOpenDungeon, function(self)
  DB().autoOpenDungeon = self:GetChecked() and true or false
end)

-- === Scale row ===
local scaleLbl=opt:CreateFontString(nil,"OVERLAY","GameFontNormal")
scaleLbl:SetPoint("TOPLEFT", 12, topY-96)
scaleLbl:SetText("Window Scale")

local scale=CreateFrame("Slider", nil, opt, "OptionsSliderTemplate")
scale:SetPoint("TOPLEFT", scaleLbl, "BOTTOMLEFT", -6, -8)
scale:SetWidth(360)                                -- wider slider
scale:SetMinMaxValues(0.7,1.5)
scale:SetValueStep(0.05)
scale:SetObeyStepOnDrag(true)
scale.Low:SetText("0.7")
scale.High:SetText("1.5")
scale:SetValue(DB().window.scale or 1)
scale.Text:ClearAllPoints()
scale.Text:SetPoint("LEFT", scale, "RIGHT", 12, 0)
scale.Text:SetJustifyH("LEFT")
scale.Text:SetText(string.format("Scale: %.2f", scale:GetValue()))
scale:SetScript("OnValueChanged", function(self,val)
  DB().window.scale = val
  scale.Text:SetText(string.format("Scale: %.2f", val))
  if GroupCCRuntimeFrame then GroupCCRuntimeFrame:SetScale(val) end
end)

-- === Toolbar (right-aligned) ===
local toolbar = CreateFrame("Frame", nil, opt)
toolbar:SetPoint("TOPRIGHT", opt, "TOPRIGHT", -12, topY-96)
toolbar:SetSize(1,1)

local helpBtn = CreateFrame("Button", nil, toolbar, "UIPanelButtonTemplate")
helpBtn:SetSize(170, 24)
helpBtn:SetPoint("RIGHT", toolbar, "RIGHT", 0, 0)
helpBtn:SetText("Show Slash Commands")
helpBtn:SetScript("OnClick", function() if _G.GroupCC_PrintHelp then _G.GroupCC_PrintHelp() end end)

local shareBtn = CreateFrame("Button", nil, toolbar, "UIPanelButtonTemplate")
shareBtn:SetSize(140, 24)
shareBtn:SetPoint("RIGHT", helpBtn, "LEFT", -8, 0)
shareBtn:SetText("Share to Group")
shareBtn:SetScript("OnClick", function()
  if SlashCmdList and SlashCmdList["GCCSHARE"] then SlashCmdList["GCCSHARE"]() end
end)

local openBtn = CreateFrame("Button", nil, toolbar, "UIPanelButtonTemplate")
openBtn:SetSize(200, 24)
openBtn:SetPoint("RIGHT", shareBtn, "LEFT", -8, 0)
openBtn:SetText("Open/Toggle Runtime Window")
openBtn:SetScript("OnClick", function() if GroupCCRuntime_Toggle then GroupCCRuntime_Toggle() end end)

-- === Role priority row (ASCII '>' to avoid missing glyph) ===
local roleHdr = opt:CreateFontString(nil,"OVERLAY","GameFontNormal")
roleHdr:SetPoint("TOPLEFT", 12, topY-136)
roleHdr:SetText("Role Priority (highest > lowest)")

local roleDrop = CreateFrame("Frame", "GroupCC_RoleDrop", opt, "UIDropDownMenuTemplate")
roleDrop:SetPoint("TOPLEFT", roleHdr, "BOTTOMLEFT", -16, -6)

local rolePerms = {
  {"TANK","HEALER","DAMAGER"},
  {"TANK","DAMAGER","HEALER"},
  {"HEALER","TANK","DAMAGER"},
  {"HEALER","DAMAGER","TANK"},
  {"DAMAGER","TANK","HEALER"},
  {"DAMAGER","HEALER","TANK"},
}
local function roleLabel(t) return (t[1].." > "..t[2].." > "..t[3]) end

function opt:RefreshRoleDropdown()
  local cur = DB().roleOrder or {"TANK","HEALER","DAMAGER"}
  UIDropDownMenu_SetWidth(roleDrop, 280)
  UIDropDownMenu_SetText(roleDrop, roleLabel(cur))
end

UIDropDownMenu_Initialize(roleDrop, function(self, level, menuList)
  for _,perm in ipairs(rolePerms) do
    local info = UIDropDownMenu_CreateInfo()
    info.text = roleLabel(perm)
    info.func = function()
      DB().roleOrder = {perm[1],perm[2],perm[3]}
      if GroupCCRuntime_ForceRefresh then GroupCCRuntime_ForceRefresh() end
      opt:RefreshRoleDropdown()
    end
    info.checked = (DB().roleOrder[1]==perm[1] and DB().roleOrder[2]==perm[2] and DB().roleOrder[3]==perm[3])
    UIDropDownMenu_AddButton(info)
  end
end)

-- === Panes (pushed down further) ===
local PANE_TOP_OFFSET = -255

-- Left: per-spell toggles
local leftBox = CreateFrame("Frame", nil, opt, "InsetFrameTemplate3")
leftBox:SetPoint("TOPLEFT", 10, PANE_TOP_OFFSET)
leftBox:SetPoint("BOTTOMRIGHT", -460, 12)          -- slightly narrower to give right pane more room

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

-- Right: manual spell priority
local rightBox = CreateFrame("Frame", nil, opt, "InsetFrameTemplate3")
rightBox:SetPoint("TOPLEFT", opt, "TOPRIGHT", -440, PANE_TOP_OFFSET)
rightBox:SetPoint("BOTTOMRIGHT", -10, 12)

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
    row:SetSize(380,24)

    local txt=row:CreateFontString(nil,"OVERLAY","GameFontNormal")
    txt:SetPoint("LEFT",0,0)
    txt:SetText(string.format("%d) %s", i, SpellName(spellID)))

    local up =CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    up:SetSize(50,20); up:SetPoint("RIGHT",-106,0); up:SetText("Up")
    up:SetScript("OnClick", function() MovePriorityIndex(i, i-1) end)

    local dn =CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    dn:SetSize(62,20); dn:SetPoint("RIGHT",-56,0); dn:SetText("Down")
    dn:SetScript("OnClick", function() MovePriorityIndex(i, i+1) end)

    local top=CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    top:SetSize(50,20); top:SetPoint("RIGHT",0,0); top:SetText("Top")
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
opt:RefreshRoleDropdown()

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

-- ESC closes
table.insert(UISpecialFrames, "GroupCCOptionsFrame")
