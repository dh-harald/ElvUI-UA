-- LibConfig-1.0
--
-- A vanilla (WoW 1.12.1 / Lua 5.0) options-window library. It takes an
-- AceConfig-format options table (the same shape AceConfigDialog-3.0 consumes)
-- and renders it into its own window: a list of registered addons/categories on
-- the left, the selected category's options on the right (nested groups shown
-- as inline section headers).
--
-- This replaces `InterfaceOptionsFrame_OpenToCategory`, whose Blizzard
-- Interface Options frame is broken on the Unreal Azeroth 1.12.1 server (and
-- needlessly heavyweight on a plain 1.12.1 client).
--
-- The look borrows ElvUI's *colour palette only*; the widget/frame mechanics
-- follow UnrealUI's proven-on-this-client patterns (flat fill backdrops,
-- explicit 1px borders drawn as textures, a drag-thumb Button for `range`
-- instead of the broken native Slider, no EditBox).
--
-- Distributed as a LibStub embedded minor, like Ace3.

local MAJOR, MINOR = "LibConfig-1.0", 1
local lib, oldminor = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then
    return -- already loaded (older/newer minor)
end

-- ===========================================================================
-- Theme (ElvUI palette)
-- ===========================================================================
local THEME = {
    -- backdrop / border
    backdrop     = { 0.10, 0.10, 0.10, 1.00 },
    backdropFade = { 0.06, 0.06, 0.06, 0.80 },
    border       = { 0.31, 0.31, 0.31, 1.00 },
    hover        = { 0.60, 0.60, 0.60, 1.00 },
    -- accent (#FFD100)
    accent       = { 1.00, 0.82, 0.00, 1.00 },
    accentFill   = { 1.00, 0.82, 0.00, 0.22 },
    sliderThumb  = { 1.00, 0.82, 0.00, 1.00 },
    -- text
    text         = { 1.00, 1.00, 1.00, 1.00 },
    textDim      = { 0.60, 0.60, 0.60, 1.00 },
    -- flat white texture tinted via SetVertexColor for everything
    plain        = "Interface\\BUTTONS\\WHITE8X8",
}

-- Layout (UnrealUI's sizes)
local PANEL_WIDTH, PANEL_HEIGHT = 700, 580
local SIDEBAR_WIDTH = 168
local HEADER_HEIGHT, FOOTER_HEIGHT = 46, 46
local MARGIN = 12
local CONTENT_LEFT = SIDEBAR_WIDTH + MARGIN * 2        -- 192
-- Gutter permanently reserved down the right-hand side of the content
-- area for the scrollbar (MINOR 11). Reserved even when the scrollbar is
-- hidden, so the content width never changes underneath a rendered page --
-- and, more importantly, so the scrollbar can never sit ON TOP of a
-- widget and steal its clicks, which is exactly the bug MINOR 7 had to
-- fix when the old loose scroll buttons overlapped the last option in a
-- long list.
local SCROLLBAR_GUTTER = 20
-- A few pixels of safety margin on the right: on Unreal Azeroth the panel
-- renders slightly narrower, so a widget sized to the full content width gets
-- its right edge clipped by a few pixels (dropdown menus, slider value text).
local CONTENT_WIDTH = PANEL_WIDTH - CONTENT_LEFT - MARGIN - 6 - SCROLLBAR_GUTTER -- 470
local LABEL_WIDTH = 200
local CONTROL_GAP = 12
local CONTROL_WIDTH = CONTENT_WIDTH - LABEL_WIDTH - CONTROL_GAP -- 284

local ROW_HEIGHT = 24
local ROW_GAP = 8
local HEADER_H = 30
local SLIDER_H = 56
local DESC_H = 20
local BUTTON_LABEL_OFFSET_Y = -2

-- Forward-declared here (before the widget constructors) so CreateDropdown can
-- parent its popup menu to the panel. Assigned later in Build().
local panel

-- Forward-declared for the same reason (MINOR 11): CreateDropdown has to
-- know how far the options page is currently scrolled to place its popup
-- menu correctly -- see AnchorMenuToButton there for the full why. The
-- real `contentOffset` upvalue is declared much further down, next to the
-- rest of the content-scroll state, so a getter is forward-declared here
-- and assigned alongside it rather than hoisting that whole block up.
local GetContentScrollOffset

-- Tracks whichever EditBox (plain `type = "input"` field, or the range
-- slider's own editable value readout) currently has keyboard focus, if
-- any -- set on OnEditFocusGained, cleared on OnEditFocusLost, by both
-- CreateEditBox and CreateSlider below. Exists so Build()'s own panel
-- Close handling can force a pending edit to commit before hiding (see
-- that OnHide handler for why: closing the panel via Close would
-- otherwise lose whatever was typed unless Enter was also pressed first).
local focusedEditBox

-- ===========================================================================
-- Small helpers
-- ===========================================================================
local function GetGlobal(name)
    if type(getglobal) == "function" then
        return getglobal(name)
    end
    if _G then
        return _G[name]
    end
    return nil
end

local function SetRegionColor(region, color)
    if not region then return end
    color = color or THEME.text
    if region.SetVertexColor then
        pcall(region.SetVertexColor, region, color[1], color[2], color[3], color[4] or 1)
    end
end

local function SetTextColor(label, color)
    if not label then return end
    color = color or THEME.text
    pcall(label.SetTextColor, label, color[1], color[2], color[3], color[4] or 1)
end

-- ===========================================================================
-- Skin primitives (adapted from UnrealUI core/style.lua)
-- ===========================================================================
local EDGES = {
    { "TOPLEFT",     "TOPRIGHT",    "horizontal" },
    { "BOTTOMLEFT",  "BOTTOMRIGHT", "horizontal" },
    { "TOPLEFT",     "BOTTOMLEFT",  "vertical"   },
    { "TOPRIGHT",    "BOTTOMRIGHT", "vertical"   },
}

local function CreateBorder(frame, thickness)
    if not frame or not frame.CreateTexture then return nil end
    thickness = tonumber(thickness) or 1
    if thickness < 1 then thickness = 1 end

    if not frame.lcEdges then
        local edges = {}
        local i
        for i = 1, table.getn(EDGES) do
            local anchor = EDGES[i]
            local edge = frame:CreateTexture(nil, "OVERLAY")
            edge:SetTexture(THEME.plain)
            SetRegionColor(edge, THEME.border)
            edge:SetPoint(anchor[1], frame, anchor[1], 0, 0)
            edge:SetPoint(anchor[2], frame, anchor[2], 0, 0)
            edges[i] = edge
        end
        frame.lcEdges = edges
    end

    local i
    for i = 1, table.getn(EDGES) do
        if EDGES[i][3] == "horizontal" then
            frame.lcEdges[i]:SetHeight(thickness)
        else
            frame.lcEdges[i]:SetWidth(thickness)
        end
    end
    return frame.lcEdges
end

local function SetBorderColor(frame, color)
    if not frame or not frame.lcEdges then return end
    color = color or THEME.border
    local i
    for i = 1, table.getn(frame.lcEdges) do
        SetRegionColor(frame.lcEdges[i], color)
    end
end

-- Fill-only backdrop + explicit border. edgeFile is deliberately omitted: it
-- does not rasterize on this client (UnrealUI knowledge.json / rendering).
local function CreateBackdrop(frame, options)
    if not frame then return frame end
    options = options or {}
    local background = options.background or THEME.backdrop
    -- options.border is a colour override (a table) or `false` to skip the
    -- border entirely -- never a boolean `true`. Guard against a stray boolean
    -- so it can never flow into SetBorderColor as a colour.
    local border = (type(options.border) == "table" and options.border) or THEME.border

    if frame.SetBackdrop then
        local ok = pcall(frame.SetBackdrop, frame, {
            bgFile = THEME.plain,
            tile = false,
            tileSize = 0,
            insets = { left = 0, right = 0, top = 0, bottom = 0 },
        })
        if ok then
            pcall(frame.SetBackdropColor, frame, background[1], background[2], background[3], background[4] or 1)
            pcall(frame.SetBackdropBorderColor, frame, 0, 0, 0, 0)
        else
            if not frame.lcFill and frame.CreateTexture then
                local fill = frame:CreateTexture(nil, "BACKGROUND")
                fill:SetTexture(THEME.plain)
                fill:SetAllPoints(frame)
                frame.lcFill = fill
            end
            SetRegionColor(frame.lcFill, background)
        end
    end

    if options.border ~= false then
        CreateBorder(frame, options.thickness)
        SetBorderColor(frame, border)
    end
    return frame
end

local function SetBackgroundColor(frame, color)
    if not frame then return end
    color = color or THEME.backdrop
    if frame.lcFill then
        SetRegionColor(frame.lcFill, color)
        return
    end
    if frame.SetBackdropColor then
        pcall(frame.SetBackdropColor, frame, color[1], color[2], color[3], color[4] or 1)
    end
end

local function CreatePanel(parent, options)
    options = options or {}
    local frame = CreateFrame("Frame", options.name, parent or UIParent)
    frame:SetWidth(options.width or 100)
    frame:SetHeight(options.height or 20)
    return CreateBackdrop(frame, options)
end

local function CreateLabel(parent, options)
    if not parent or not parent.CreateFontString then return nil end
    options = options or {}

    local ok, label = false, nil
    if options.inherits then
        ok, label = pcall(parent.CreateFontString, parent, options.name, options.layer or "OVERLAY", options.inherits)
    end
    if not ok or not label then
        ok, label = pcall(parent.CreateFontString, parent, options.name, options.layer or "OVERLAY")
    end
    if not ok or not label then return nil end

    if options.font and options.size then
        pcall(label.SetFont, label, options.font, options.size)
    end
    SetTextColor(label, options.color or THEME.text)

    if options.justify then
        pcall(label.SetJustifyH, label, options.justify)
    end
    if options.width then
        pcall(label.SetWidth, label, options.width)
    end
    if options.height then
        pcall(label.SetHeight, label, options.height)
    end
    if options.nonSpaceWrap ~= nil and label.SetNonSpaceWrap then
        pcall(label.SetNonSpaceWrap, label, options.nonSpaceWrap and true or false)
    end
    return label
end

local function CreateButton(parent, options)
    options = options or {}
    local width = options.width or 100
    local height = options.height or 22

    local button = CreateFrame("Button", options.name, parent or UIParent)
    button:SetWidth(width)
    button:SetHeight(height)
    pcall(button.EnableMouse, button, true)
    CreateBackdrop(button, options)

    local label = CreateLabel(button, {
        color = options.textColor or THEME.text,
        inherits = "GameFontNormal",
        width = math.max(1, width - 8),
        height = math.max(1, height - 4),
        nonSpaceWrap = true,
    })
    if label then
        pcall(label.ClearAllPoints, label)
        pcall(label.SetPoint, label, "CENTER", button, "CENTER", 0, BUTTON_LABEL_OFFSET_Y)
        label:SetText(options.text or "")
    end
    button.label = label

    button:SetScript("OnEnter", function()
        SetBorderColor(button, options.hoverBorder or THEME.hover)
    end)
    button:SetScript("OnLeave", function()
        SetBorderColor(button, (type(options.border) == "table" and options.border) or THEME.border)
    end)

    if type(options.onClick) == "function" then
        button:SetScript("OnClick", options.onClick)
    end
    return button
end

-- ===========================================================================
-- Artwork glyphs (+/- collapse markers, navigation arrows)
--
-- The library SHIPS ITS OWN artwork, in Media/ next to this file:
-- PlusMinusButton.blp and SquareButtonTextures.blp. They are the same two
-- sprite sheets ElvUI uses for exactly these jobs, brought in so the
-- config window looks like the rest of an ElvUI-styled UI -- but this
-- library depends on NOTHING, so the files live here rather than being
-- referenced out of some consumer addon's folder.
--
-- FINDING THE FILES IS THE ONLY HARD PART. This library is EMBEDDED, so
-- its on-disk location differs per consumer
-- (Interface\AddOns\ElvUI_Config\Libraries\LibConfig-1.0\ for one,
-- Interface\AddOns\Bagzen\lib\LibConfig-1.0\ for another), and WoW texture
-- paths are absolute from Interface\ with no relative form. DeriveOwnPath
-- below recovers it from `debugstack()`, whose traceback lines carry this
-- file's own full path -- documented on Unreal Azeroth
-- (UnrealAzeroth_LuaAPI/en/globals/Helpers.md, where it also normalizes
-- forward slashes to backslashes) and present on real 1.12.1 too.
--
-- If that ever fails, the glyphs fall back to the plain ASCII characters
-- this library has always drawn ("+", "-", "^", "v") -- a cosmetic
-- downgrade, never an error. A consumer can also override the paths
-- explicitly with :SetMedia{} (e.g. to supply its own art).
--
-- The TexCoords are ElvUI's own, copied from its Skins module rather than
-- eyeballed: PLUS/MINUS are the two halves of `PlusMinusButton`, and the
-- four arrows are cells of the shared `SquareButtonTextures` sheet. DOWN
-- and RIGHT deliberately have their coordinate pairs REVERSED (top>bottom,
-- left>right) -- that is ElvUI's own way of flipping UP/LEFT rather than
-- storing separate cells, and it works with the plain 4-argument
-- SetTexCoord form.
-- ===========================================================================
lib.media = lib.media or {}

-- Characters that cannot appear inside a texture path, used to find where
-- the path starts when walking backwards from this file's own name in a
-- traceback line.
local PATH_DELIMITERS = " \t\n\r\"'()[]:,@<>"

-- This library's own folder name. Fixed by definition (a LibStub embed
-- keeps the library's canonical folder name), which is what makes it
-- possible to rebuild a path the traceback truncated -- see DeriveOwnPath.
local LIB_FOLDER = "LibConfig-1.0"

-- Recovers this file's own folder ("...\LibConfig-1.0\") from a traceback.
-- Returns nil rather than guessing if anything about the string is
-- unexpected -- the caller degrades to text glyphs.
--
-- Deliberately does NOT look for a literal "Interface\" prefix (a first
-- attempt did, and came back empty in-game): the traceback's exact
-- framing is client-specific -- Unreal Azeroth documents that it strips
-- the first two lines and rewrites `[string "` prefixes -- so anything
-- assumed about the text AROUND the file name is a guess. Walking
-- backwards from the file name to the first character that cannot be part
-- of a path makes no such assumption.
--
-- The raw traceback is kept on `lib.mediaDebug` so a failure is
-- diagnosable in one line in-game:
--     /run print(LibStub("LibConfig-1.0").mediaDebug)
local function DeriveOwnPath()
    if type(debugstack) ~= "function" then
        lib.mediaDebug = "debugstack is not a function on this client"
        return nil
    end

    -- Called DIRECTLY, not through pcall. A pcall inserts a C call
    -- boundary at the very top of the stack that debugstack is about to
    -- walk, which is exactly the region Unreal Azeroth then trims (it
    -- strips the first two lines of the raw traceback) -- so the frames
    -- carrying this file's own path can end up cut off, or never reported
    -- past the pcall boundary at all. The `type()` check above is the real
    -- protection here; the pcall was only ever guarding against a
    -- traceback function erroring, which it does not do.
    local stack = debugstack()
    if type(stack) ~= "string" or stack == "" then
        lib.mediaDebug = "debugstack returned nothing usable"
        return nil
    end
    lib.mediaDebug = stack

    -- Real 1.12.1 and Unreal Azeroth both report backslashes, but
    -- normalize anyway rather than depend on it.
    stack = string.gsub(stack, "/", "\\")

    -- Walks backwards from `stopAt` to the first character that cannot be
    -- part of a path, and returns what lies between.
    local function PathTokenBefore(stopAt)
        local head = string.sub(stack, 1, stopAt - 1)
        local i = string.len(head)
        while i > 0 do
            local c = string.sub(head, i, i)
            if string.find(PATH_DELIMITERS, c, 1, true) then break end
            i = i - 1
        end
        return string.sub(head, i + 1)
    end

    -- CASE 1: the whole path is present. Everything before the file name
    -- is the folder.
    local fileStart = string.find(stack, "LibConfig%-1%.0%.lua")
    if fileStart then
        local path = PathTokenBefore(fileStart)
        if path ~= "" then return path end
        return nil
    end

    -- CASE 2: the path is TRUNCATED, which is what actually happens here.
    -- Confirmed from a live traceback:
    --
    --   Interface\AddOns\ElvUI_Config\Libraries\Lib...":375: in function 'DeriveOwnPath'
    --
    -- Lua caps the chunk name it stores per function (LUA_IDSIZE), so a
    -- deeply embedded library's path is cut short with a literal "..." --
    -- here after only 43 characters, which lands PART WAY THROUGH this
    -- library's own folder name. The file name never appears at all, so no
    -- amount of searching for it can work; the tail has to be
    -- RECONSTRUCTED instead.
    --
    -- That is possible because the only unknown is the host's own folder
    -- layout, and the truncation always cuts a path we already know the
    -- END of: this library's folder is named LIB_FOLDER by definition.
    local dots = string.find(stack, "%.%.%.")
    if not dots then return nil end

    local truncated = PathTokenBefore(dots)
    if truncated == "" then return nil end

    -- Split off whatever partial segment the cut left behind.
    local lastSlash, init = nil, 1
    while true do
        local at = string.find(truncated, "\\", init, true)
        if not at then break end
        lastSlash = at
        init = at + 1
    end
    if not lastSlash then return nil end

    local folder = string.sub(truncated, 1, lastSlash)      -- keeps the trailing "\"
    local partial = string.sub(truncated, lastSlash + 1)

    -- If our own folder is already complete in the surviving text, the
    -- partial is the start of the FILE name -- the folder is what we want.
    if string.find(folder, LIB_FOLDER .. "\\", 1, true) then
        return folder
    end

    -- Otherwise the cut landed inside our folder's name: complete it, but
    -- ONLY if what survived really is a prefix of it. Anything else means
    -- the truncation happened further up the path, where there is nothing
    -- left to reconstruct from -- return nil and let the glyphs fall back
    -- to text rather than invent a path that would silently load nothing.
    if partial == string.sub(LIB_FOLDER, 1, string.len(partial)) then
        return folder .. LIB_FOLDER .. "\\"
    end

    return nil
end

-- Resolved LAZILY, on the first glyph actually drawn, not at file load.
--
-- Two reasons. The traceback at main-chunk load time is the SHALLOWEST it
-- will ever be, and Unreal Azeroth strips its first two lines -- which can
-- take the only path-bearing line with them. And a failure at load would
-- be permanent, whereas this retries until it succeeds.
local mediaResolved = false
local function EnsureMediaPath()
    if mediaResolved then return end
    if lib.media.plusMinus and lib.media.arrows then
        mediaResolved = true
        return
    end
    local ownPath = DeriveOwnPath()
    lib.mediaPath = ownPath
    if not ownPath then return end
    lib.media.plusMinus = lib.media.plusMinus or (ownPath .. "Media\\PlusMinusButton")
    lib.media.arrows = lib.media.arrows or (ownPath .. "Media\\SquareButtonTextures")
    mediaResolved = true
end

-- One EAGER attempt at load, purely so the diagnostic fields are populated
-- even if the config window is never opened: `lib.mediaDebug` could
-- otherwise come back nil, indistinguishable from "the derivation was
-- never reached". A failure here
-- costs nothing: mediaResolved stays false, so the lazy path above still
-- retries on the first glyph drawn, from a deeper (more informative)
-- stack.
EnsureMediaPath()

local GLYPH_TEXCOORDS = {
    PLUS  = { 0.045, 0.475, 0.085, 0.925 },
    MINUS = { 0.545, 0.975, 0.085, 0.925 },
    UP    = { 0.453125, 0.640625, 0.015625, 0.203125 },
    DOWN  = { 0.453125, 0.640625, 0.203125, 0.015625 },
    LEFT  = { 0.234375, 0.421875, 0.015625, 0.203125 },
    RIGHT = { 0.421875, 0.234375, 0.015625, 0.203125 },
}

-- Which registered sheet each glyph is cut from.
local GLYPH_SHEET = {
    PLUS = "plusMinus", MINUS = "plusMinus",
    UP = "arrows", DOWN = "arrows", LEFT = "arrows", RIGHT = "arrows",
}

-- What to draw when the consumer registered no artwork.
local GLYPH_TEXT = {
    PLUS = "+", MINUS = "-", UP = "^", DOWN = "v", LEFT = "<", RIGHT = ">",
}

--- media  table with any of: plusMinus, arrows (texture paths).
--- Call before opening the panel. Merges, so it can be called repeatedly.
function lib:SetMedia(media)
    if type(media) ~= "table" then return end
    lib.media = lib.media or {}
    if media.plusMinus then lib.media.plusMinus = media.plusMinus end
    if media.arrows then lib.media.arrows = media.arrows end
end

local function GlyphPath(glyphName)
    local sheet = GLYPH_SHEET[glyphName or ""]
    if not sheet then return nil end
    EnsureMediaPath()
    return lib.media and lib.media[sheet]
end

-- Replaces a button's text label with the artwork glyph, or restores the
-- text fallback if no artwork is registered for it. Safe to call on every
-- render -- the texture is created once and only re-pointed afterwards.
--
-- The icon is always drawn SQUARE and CENTERED, sized off the button's
-- SHORTER side: several of these buttons are deliberately non-square (the
-- sidebar's collapse toggle is 16x20, the scroll buttons are full-width
-- strips), and stretching a square sprite to fill those reads as a smear.
local GLYPH_INSET = 3
local function SetButtonGlyph(button, glyphName)
    if not button then return end

    local path = GlyphPath(glyphName)
    local coords = GLYPH_TEXCOORDS[glyphName or ""]

    if not path or not coords then
        if button.glyph then pcall(button.glyph.Hide, button.glyph) end
        if button.label then
            pcall(button.label.Show, button.label)
            pcall(button.label.SetText, button.label, GLYPH_TEXT[glyphName or ""] or "")
        end
        return
    end

    if button.label then
        pcall(button.label.SetText, button.label, "")
        pcall(button.label.Hide, button.label)
    end

    if not button.glyph then
        local ok, tex = pcall(button.CreateTexture, button, nil, "ARTWORK")
        if not ok or not tex then return end
        pcall(tex.SetPoint, tex, "CENTER", button, "CENTER", 0, 0)
        button.glyph = tex
    end

    local w = button:GetWidth() or 16
    local h = button:GetHeight() or 16
    local size = (w < h) and w or h
    size = size - 2 * GLYPH_INSET
    if size < 6 then size = 6 end
    pcall(button.glyph.SetWidth, button.glyph, size)
    pcall(button.glyph.SetHeight, button.glyph, size)

    pcall(button.glyph.SetTexture, button.glyph, path)
    pcall(button.glyph.SetTexCoord, button.glyph, coords[1], coords[2], coords[3], coords[4])
    pcall(button.glyph.Show, button.glyph)
end

local function CreateRule(parent, options)
    options = options or {}
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetTexture(THEME.plain)
    line:SetHeight(options.thickness or 1)
    SetRegionColor(line, options.color or THEME.accent)
    return line
end

-- ===========================================================================
-- Visibility helpers
--
-- This client does not propagate parent visibility to children
-- (rendering.parent_alpha_not_propagated), so every region is toggled by hand.
-- ===========================================================================
local function SetShown(region, show)
    if not region then return end
    if type(region.uuiSetShown) == "function" then
        region.uuiSetShown(show)
        return
    end
    if region.uuiParts then
        local i
        for i = 1, table.getn(region.uuiParts) do
            SetShown(region.uuiParts[i], show)
        end
        return
    end
    if show then region:Show() else region:Hide() end
    if region.label then
        if show then region.label:Show() else region.label:Hide() end
    end
end

local function SetListShown(list, show)
    if type(list) ~= "table" then return end
    local i
    for i = 1, table.getn(list) do
        SetShown(list[i], show)
    end
end

-- Wraps a region's existing OnEnter/OnLeave so the description tooltip stacks on
-- top of whatever hover behaviour the control already has.
local function AttachTooltip(region, text)
    if not region or not region.SetScript then return end
    if type(text) ~= "string" or text == "" then return end

    local oldEnter = region:GetScript("OnEnter")
    local oldLeave = region:GetScript("OnLeave")
    region:SetScript("OnEnter", function()
        if oldEnter then oldEnter() end
        local tt = GameTooltip
        if tt then
            pcall(tt.SetOwner, tt, region, "ANCHOR_RIGHT")
            pcall(tt.SetText, tt, text)
            pcall(tt.Show, tt)
        end
    end)
    region:SetScript("OnLeave", function()
        if oldLeave then oldLeave() end
        local tt = GameTooltip
        if tt then pcall(tt.Hide, tt) end
    end)
end

-- ===========================================================================
-- Widgets (each returns a control table with SetValue / SetPoint / uuiParts)
-- ===========================================================================
local function CreateCheckbox(parent, options)
    options = options or {}
    local size = options.size or 16
    local control = { uuiParts = {} }
    local parts = control.uuiParts

    local function Apply()
        if control.value then
            SetBackgroundColor(control.box, THEME.accent)
        else
            SetBackgroundColor(control.box, THEME.backdrop)
        end
    end

    local box = CreateButton(parent, {
        name = options.name,
        text = "",
        width = size,
        height = size,
        onClick = function()
            if control.disabled then return end
            control.value = not control.value
            Apply()
            if type(options.onChange) == "function" then
                options.onChange(control.value)
            end
        end,
    })
    control.box = box
    table.insert(parts, box)

    control.disabled = options.disabled and true or false

    control.SetValue = function(value)
        control.value = value and true or false
        Apply()
    end

    control.SetPoint = function(self, point, relative, relativePoint, x, y)
        box:ClearAllPoints()
        box:SetPoint(point, relative, relativePoint, x, y)
    end

    control.SetValue(options.value)
    return control
end

-- ===========================================================================
-- Text input
--
-- ADDED (MINOR 7): `type = "input"` was not handled by RenderLeaf at all --
-- any AceConfig option table using it (e.g. this project's own ElvUI addon
-- has several: a free-text keyword list, custom texture paths) silently
-- rendered NOTHING, no error, just an empty gap.
-- ===========================================================================
local function CreateEditBox(parent, options)
    options = options or {}
    local width = options.width or 200
    local height = options.height or ROW_HEIGHT
    local control = { uuiParts = {} }
    local parts = control.uuiParts

    local box = CreateFrame("Frame", options.name and (options.name .. "Box") or nil, parent)
    box:SetWidth(width)
    box:SetHeight(height)
    CreateBackdrop(box, {})
    control.box = box
    table.insert(parts, box)

    local edit = CreateFrame("EditBox", options.name and (options.name .. "EditBox") or nil, box)
    edit:SetPoint("TOPLEFT", box, "TOPLEFT", 6, -1)
    edit:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -6, 1)
    pcall(edit.SetAutoFocus, edit, false)
    pcall(edit.SetJustifyH, edit, "LEFT")
    pcall(edit.SetFontObject, edit, GameFontHighlightSmall)
    SetTextColor(edit, THEME.text)
    if options.maxLetters then pcall(edit.SetMaxLetters, edit, options.maxLetters) end
    -- Without this, typing adds no characters at all (only
    -- paste works), and the last remaining character can't be
    -- deleted. This project's own real ElvUI/UA embedding has an
    -- ALREADY-documented finding that native EditBox is broken on UA
    -- (part of why Slider/ColorPickerFrame got hand-rolled replacements
    -- there too) -- but a freshly CreateFrame()'d EditBox not
    -- auto-registering for keyboard/mouse input the way a Blizzard-
    -- template-built one does is also a distinct, already-established
    -- gap on UA elsewhere (see this addon's own key-nudge frame, which
    -- needed an explicit EnableKeyboard(true) real vanilla doesn't
    -- require). Cheap, safe to try first before assuming this needs a
    -- full custom (non-native-EditBox) text-input widget the way
    -- Slider/ColorPicker did.
    pcall(edit.EnableKeyboard, edit, true)
    pcall(edit.EnableMouse, edit, true)
    control.edit = edit
    table.insert(parts, edit)

    -- Strips a literal newline the moment it appears in the box (typed,
    -- or pasted): a multi-line value (a
    -- serialized profile table, real newlines between entries) would
    -- otherwise render COMPLETELY UNCLIPPED in this small box, sprawling across and
    -- behind the entire options window. This box has no bounding
    -- ScrollFrame, and this vintage client has no SetClipsChildren to
    -- fall back on -- a real fix would need a genuinely different,
    -- ScrollFrame-backed multi-line widget. Cheaper and immediate:
    -- guarantee this box is ALWAYS effectively single-line regardless of
    -- what's fed into it, so there's never a newline left to sprawl on.
    -- `suppressTextChanged` guards against SetText below re-triggering
    -- this same handler.
    local suppressTextChanged = false
    edit:SetScript("OnTextChanged", function()
        if suppressTextChanged then return end
        local text = edit:GetText() or ""
        if string.find(text, "\n") then
            local flattened = string.gsub(text, "\n%s*", " ")
            suppressTextChanged = true
            edit:SetText(flattened)
            pcall(edit.SetCursorPosition, edit, string.len(flattened))
            suppressTextChanged = false
        end
    end)

    -- Enter commits and clears focus (which also fires OnEditFocusLost --
    -- harmless, it just re-sends the same already-committed text). Escape
    -- reverts to the last known-good value without committing. Clicking
    -- away (focus lost) also commits, matching the slider readout's own
    -- forgiving "don't require Enter" behavior above.
    local function Commit()
        local text = edit:GetText() or ""
        control.value = text
        if type(options.onChange) == "function" then
            options.onChange(text)
        end
    end

    edit:SetScript("OnEnterPressed", function()
        Commit()
        pcall(edit.ClearFocus, edit)
    end)
    edit:SetScript("OnEditFocusGained", function() focusedEditBox = edit end)
    edit:SetScript("OnEditFocusLost", function()
        if focusedEditBox == edit then focusedEditBox = nil end
        Commit()
    end)
    edit:SetScript("OnEscapePressed", function()
        edit:SetText(control.value or "")
        pcall(edit.ClearFocus, edit)
    end)

    control.SetValue = function(value)
        control.value = value or ""
        edit:SetText(control.value)
    end

    control.SetPoint = function(self, point, relative, relativePoint, x, y)
        box:ClearAllPoints()
        box:SetPoint(point, relative, relativePoint, x, y)
    end

    control.SetValue(options.value)
    return control
end

local activeDropdown

local function CreateDropdown(parent, options)
    options = options or {}
    local items = options.items or {}
    local width = options.width or 220
    local height = options.height or 24
    local rowHeight = options.rowHeight or 22
    local control = { uuiParts = {}, rows = {} }

    local button = CreateButton(parent, {
        name = options.name,
        text = "",
        width = width,
        height = height,
    })
    control.button = button
    table.insert(control.uuiParts, button)

    if button.label then
        button.label:ClearAllPoints()
        button.label:SetPoint("LEFT", button, "LEFT", 8, BUTTON_LABEL_OFFSET_Y)
        pcall(button.label.SetWidth, button.label, width - 30)
        pcall(button.label.SetJustifyH, button.label, "LEFT")
    end

    local arrow = CreateLabel(button, {
        color = THEME.accent,
        inherits = "GameFontNormalSmall",
        width = 14,
        height = height - 4,
        justify = "CENTER",
    })
    if arrow then
        arrow:SetPoint("RIGHT", button, "RIGHT", -5, BUTTON_LABEL_OFFSET_Y)
        arrow:SetText("v")
    end
    control.arrow = arrow
    table.insert(control.uuiParts, arrow)

    -- Artwork arrow instead of the "v" character when the consumer
    -- registered a sheet (see SetMedia). Not routed through
    -- SetButtonGlyph: that one owns a button's whole label, and this
    -- button's label is the SELECTED VALUE -- only the little indicator
    -- at the right edge is being replaced here.
    local arrowPath = GlyphPath("DOWN")
    if arrow and arrowPath then
        arrow:SetText("")
        pcall(arrow.Hide, arrow)
        local okArrow, arrowTex = pcall(button.CreateTexture, button, nil, "ARTWORK")
        if okArrow and arrowTex then
            local coords = GLYPH_TEXCOORDS.DOWN
            pcall(arrowTex.SetTexture, arrowTex, arrowPath)
            pcall(arrowTex.SetTexCoord, arrowTex, coords[1], coords[2], coords[3], coords[4])
            pcall(arrowTex.SetWidth, arrowTex, 10)
            pcall(arrowTex.SetHeight, arrowTex, 10)
            pcall(arrowTex.SetPoint, arrowTex, "RIGHT", button, "RIGHT", -6, 0)
            control.arrowTexture = arrowTex
        end
    end

    local totalHeight = table.getn(items) * rowHeight + 2
    local menuViewHeight = totalHeight
    if menuViewHeight > 300 then menuViewHeight = 300 end

    -- Up/down navigation buttons for clients where the mouse wheel does not
    -- scroll (Unreal Azeroth); they only exist when the list overflows. The
    -- rows are laid out between the two buttons, so the visible row area is
    -- viewHeight, not menuViewHeight.
    local BUTTON_H = 16
    local hasScroll = (totalHeight > menuViewHeight)
    local rowsTop = 0
    local viewHeight = menuViewHeight
    if hasScroll then
        rowsTop = BUTTON_H
        viewHeight = menuViewHeight - 2 * BUTTON_H
    end
    local rowsBottom = rowsTop + viewHeight

    local menuOffset = 0
    local maxOffset = totalHeight - viewHeight
    if maxOffset < 0 then maxOffset = 0 end

    -- The dropdown menu is a ScrollFrame only so the mouse wheel fires on Unreal
    -- Azeroth (a plain Frame/Button's OnMouseWheel never fires there). The rows
    -- are NOT its scroll child (a tall scroll child does not render on Unreal
    -- Azeroth); they are children of the menu and positioned by hand. The menu
    -- is a child of the panel so it renders above the other widgets.
    local menu = CreateFrame("ScrollFrame", options.name and (options.name .. "Menu") or nil, panel)
    menu:SetWidth(width)
    menu:SetHeight(menuViewHeight)
    CreateBackdrop(menu, { background = THEME.backdrop })
    menu:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -1)
    pcall(menu.SetFrameLevel, menu, 100)
    control.menu = menu

    -- Live media previews -- `options.previewType` ("font" or "statusbar")
    -- plus a `previewPath` on each item (the already-resolved LSM path)
    -- renders each row using the ACTUAL media it represents, matching real
    -- ElvUI's/AceGUI's own LSM30_Font/LSM30_Statusbar dialog controls
    -- (source/ElvUI-vanilla, AceGUI-3.0-SharedMediaWidgets) -- and,
    -- crucially, doubles as a live diagnostic: if
    -- every row renders identically regardless of which media it names,
    -- that itself proves the underlying SetFont/SetTexture call silently
    -- isn't applying on this client.
    local i
    for i = 1, table.getn(items) do
        local item = items[i]
        local row = CreateButton(menu, {
            name = options.name and (options.name .. "Item" .. i) or nil,
            text = item.text or tostring(item.value or ""),
            width = width - 2,
            height = rowHeight,
        })
        row.item = item

        if options.previewType == "statusbar" and item.previewPath then
            -- A small texture swatch behind the row's own label -- BACKGROUND
            -- layer so it never covers the (already-OVERLAY) label text drawn
            -- on top of it, matching the reference screenshot's own look
            -- (each entry's name overlaid directly on its own bar texture).
            local preview = row:CreateTexture(nil, "BACKGROUND")
            preview:SetPoint("TOPLEFT", row, "TOPLEFT", 3, -2)
            preview:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -3, 2)
            pcall(preview.SetTexture, preview, item.previewPath)
            row.previewTexture = preview
        end

        if row.label then
            row.label:ClearAllPoints()
            row.label:SetPoint("LEFT", row, "LEFT", 7, BUTTON_LABEL_OFFSET_Y)
            pcall(row.label.SetWidth, row.label, width - 16)
            pcall(row.label.SetJustifyH, row.label, "LEFT")
            if options.previewType == "font" and item.previewPath then
                -- Renders the row's OWN name using the font it names --
                -- size/outline fixed rather than read from options, matching
                -- AceGUI's own LSM30_Font widget (a font-picker row preview
                -- is always shown at one consistent readable size,
                -- independent of whatever size the SETTING itself will
                -- apply elsewhere).
                pcall(row.label.SetFont, row.label, item.previewPath, 14, "")
            end
        end

        row:SetScript("OnClick", function()
            control.SetValue(row.item.value, true)
            control.SetOpen(false)
        end)
        table.insert(control.rows, row)
    end

    local function UpdateRows()
        local i
        for i = 1, table.getn(control.rows) do
            local row = control.rows[i]
            -- rowTop is measured DOWN from the menu top (positive = down); the
            -- SetPoint below negates it back to WoW's negative-Y convention.
            local rowTop = rowsTop + 1 + (i - 1) * rowHeight - menuOffset
            local rowBottom = rowTop + rowHeight
            if rowTop >= rowsBottom or rowBottom <= rowsTop then
                row:Hide()
            else
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", menu, "TOPLEFT", 1, -rowTop)
                row:Show()
            end
        end
    end

    local function ScrollToSelected()
        local selIndex = nil
        local i
        for i = 1, table.getn(items) do
            if items[i].value == control.value then selIndex = i end
        end
        if not selIndex then
            menuOffset = 0
        else
            local selTop = (selIndex - 1) * rowHeight
            local selBottom = selTop + rowHeight
            if selTop < menuOffset then
                menuOffset = selTop
            elseif selBottom > menuOffset + viewHeight then
                menuOffset = selBottom - viewHeight
            end
            if menuOffset < 0 then menuOffset = 0 end
            if menuOffset > maxOffset then menuOffset = maxOffset end
        end
    end

    local function OnWheel(a1, a2)
        local delta = arg1
        if type(a1) == "number" then delta = a1 end
        if type(a2) == "number" then delta = a2 end
        if type(delta) ~= "number" then delta = 0 end
        menuOffset = menuOffset - delta * rowHeight * 3
        if menuOffset < 0 then menuOffset = 0 end
        if menuOffset > maxOffset then menuOffset = maxOffset end
        UpdateRows()
    end

    pcall(menu.EnableMouseWheel, menu, true)
    menu:SetScript("OnMouseWheel", OnWheel)

    local upBtn, downBtn
    if hasScroll then
        upBtn = CreateButton(menu, {
            text = "^",
            width = width - 2,
            height = BUTTON_H,
            onClick = function()
                menuOffset = menuOffset - rowHeight
                if menuOffset < 0 then menuOffset = 0 end
                UpdateRows()
            end,
        })
        upBtn:SetPoint("TOPLEFT", menu, "TOPLEFT", 1, 0)
        pcall(upBtn.SetFrameLevel, upBtn, 102)
        SetButtonGlyph(upBtn, "UP")
        upBtn:Hide()

        downBtn = CreateButton(menu, {
            text = "v",
            width = width - 2,
            height = BUTTON_H,
            onClick = function()
                menuOffset = menuOffset + rowHeight
                if menuOffset > maxOffset then menuOffset = maxOffset end
                UpdateRows()
            end,
        })
        downBtn:SetPoint("BOTTOMLEFT", menu, "BOTTOMLEFT", 1, 1)
        pcall(downBtn.SetFrameLevel, downBtn, 102)
        SetButtonGlyph(downBtn, "DOWN")
        downBtn:Hide()
    end

    -- BUG FIXED (MINOR 11): a dropdown far enough down a long options page
    -- that you have to SCROLL to reach it opened its menu with a visible
    -- GAP below the button instead of flush against it.
    --
    -- The menu's anchor was correct all along ("TOPLEFT" -> button's
    -- "BOTTOMLEFT", 0, -1) and never changes. The problem is that the
    -- BUTTON lives inside `content`, the scroll child of `contentScroll`,
    -- while the MENU is deliberately parented to `panel` instead (it has
    -- to be -- a ScrollFrame clips its scroll child, so a menu parented
    -- into the content would be cut off exactly for the bottom-of-page
    -- dropdowns that need it most). Anchoring across that boundary
    -- evidently does not pick up the ScrollFrame's own scroll
    -- translation on Unreal Azeroth, so the menu lands where the button
    -- WOULD be at scroll offset 0 -- i.e. off by exactly the current
    -- scroll amount, which is why it only shows up once you scroll.
    --
    -- Fixed by re-applying the anchor at OPEN time with the current scroll
    -- amount added back in (positive Y moves a frame up, which is the
    -- direction the menu needs to come back by). At scroll offset 0 --
    -- every dropdown on a page short enough not to scroll, and every
    -- consumer that never scrolls at all -- this is byte-for-byte the old
    -- behaviour, so it cannot regress the cases that already worked.
    --
    -- IF THIS COMES BACK DOUBLED rather than fixed, the diagnosis above is
    -- wrong (the anchor did resolve correctly and something else adds the
    -- gap) -- flip the sign back and look elsewhere, don't tune the
    -- number.
    local function AnchorMenuToButton()
        local scrolled = 0
        if GetContentScrollOffset then
            scrolled = GetContentScrollOffset() or 0
        end
        pcall(menu.ClearAllPoints, menu)
        pcall(menu.SetPoint, menu, "TOPLEFT", button, "BOTTOMLEFT", 0, -1 + scrolled)
    end

    local function SetPopupShown(shown)
        control.open = shown and true or false
        if shown then
            control.menu:Show()
            if upBtn then upBtn:Show() end
            if downBtn then downBtn:Show() end
            AnchorMenuToButton()
            ScrollToSelected()
            UpdateRows()
        else
            control.menu:Hide()
            if upBtn then upBtn:Hide() end
            if downBtn then downBtn:Hide() end
            local i
            for i = 1, table.getn(control.rows) do
                control.rows[i]:Hide()
            end
        end
    end

    local function ApplySelection()
        local selected = nil
        local i
        for i = 1, table.getn(items) do
            if items[i].value == control.value then selected = items[i] end
        end
        if button.label then
            button.label:SetText(selected and selected.text or "")
        end
        for i = 1, table.getn(control.rows) do
            local row = control.rows[i]
            if row.item.value == control.value then
                SetBackgroundColor(row, THEME.accentFill)
                SetBorderColor(row, THEME.accent)
            else
                SetBackgroundColor(row, THEME.backdrop)
                SetBorderColor(row, THEME.border)
            end
        end
    end

    control.SetOpen = function(open)
        open = open and true or false
        if open and activeDropdown and activeDropdown ~= control then
            activeDropdown.SetOpen(false)
        end
        if open then activeDropdown = control end
        SetPopupShown(open)
        if open then ApplySelection() end
    end

    control.SetValue = function(value, notify)
        local valid = false
        local i
        for i = 1, table.getn(items) do
            if items[i].value == value and not items[i].disabled then
                valid = true
                break
            end
        end
        if not valid then return false end

        control.value = value
        ApplySelection()
        -- NOT gated on the value having changed. `notify` is only ever true
        -- for a real row click, and re-picking the value already displayed
        -- is a deliberate act for an action-shaped select ("Copy From",
        -- "Delete a Profile"): the caller's own get() may not track the
        -- widget's value at all, so "same value" carries no information
        -- about whether the config has heard about it.
        if notify and type(options.onChange) == "function" then
            options.onChange(value)
        end
        return true
    end

    control.GetValue = function()
        return control.value
    end

    control.SetPoint = function(self, point, relative, relativePoint, x, y)
        button:ClearAllPoints()
        button:SetPoint(point, relative, relativePoint, x, y)
    end

    control.uuiSetShown = function(shown)
        if button then if shown then button:Show() else button:Hide() end end
        -- Only ONE of the two arrow representations is ever live (the text
        -- one is permanently hidden the moment an artwork sheet is
        -- registered), so re-showing must not resurrect the other.
        if control.arrowTexture then
            if shown then control.arrowTexture:Show() else control.arrowTexture:Hide() end
        elseif arrow then
            if shown then arrow:Show() else arrow:Hide() end
        end
        if not shown then control.SetOpen(false) end
    end

    button:SetScript("OnClick", function()
        control.SetOpen(not control.open)
    end)

    -- Construction never notifies, and never picks a value of its own: when
    -- `options.value` matches no item (nil -- nothing picked yet) the button
    -- label stays empty. Auto-picking here would call onChange, i.e. the
    -- consumer's own set(), merely because the page was rendered -- and for
    -- an action-shaped select that PERFORMS the action unasked, on whichever
    -- item happens to sort first.
    --
    -- What makes an empty start safe is that SetValue above no longer gates
    -- the notification on the value having changed: a real row click always
    -- reaches onChange, including a click that re-picks whatever the label
    -- already shows.
    control.SetValue(options.value, false)
    control.SetOpen(false)
    return control
end

-- ===========================================================================
-- Drag mechanics shared by every one-axis thumb in this library (the
-- `range` slider's thumb and the scrollbar's thumb).
--
-- Three findings feed into this, all paid for live on Unreal Azeroth.
-- Please read them before "simplifying" any of it.
--
--  1. A thumb must never be MOVED by StartMoving. The client's own free
--     move follows the cursor on BOTH axes, so the thumb drifts sideways
--     off its track and can be dragged past its own ends. The native
--     Slider does not move its thumb either -- it reads the cursor,
--     projects it onto its own axis and positions the thumb itself.
--     Constraint is a consequence of never writing the other axis, not a
--     widget feature we lack. So: read GetCursorPosition every tick,
--     clamp to the track, SetPoint. ("SetPoint during a drag breaks it"
--     only ever applied to fighting StartMoving, which no longer
--     happens here at all.)
--
--  2. A drag must not be STARTED from OnDragStart. RegisterForDrag only
--     fires it once the cursor has travelled more than 15 UI pixels
--     (documented: Frame.md#registerfordrag), and whether it fires here
--     at all has been in dispute across several sessions -- one round
--     "fixed" it by adding a throwaway SetMovable/StartMoving/
--     StopMovingOrSizing arm sequence, which is also the one thing that
--     can silently re-anchor the thumb. OnMouseDown is unconditional
--     (the press IS on the thumb, by definition), so that is what starts
--     a drag now. Nothing here registers for drag any more.
--
--  3. Knowing when a drag ENDED is the genuinely hard part. Dead ends,
--     recorded so nobody re-walks them:
--       a. Trust OnDragStop / the thumb's own OnMouseUp alone. Only
--          fires while the cursor is still over the thumb -- and a thumb
--          clamped to its track is exactly the thing the cursor wanders
--          off.
--       b. Poll IsMouseButtonDown("LeftButton") (UnrealUI's approach).
--          That function DOES NOT EXIST on Unreal Azeroth, and appears
--          nowhere in real 1.12.1's FrameXML either.
--       c. Show a full-screen mouse-enabled catcher for the duration of
--          the drag. Its OnMouseUp does fire -- but only for a press
--          that STARTED on it. Shown mid-hold it never saw the press, so
--          the drag only ended on the NEXT click.
--     (c) failed for a fixable reason: wrong FRAME, not wrong idea. So
--     the thumb ITSELF becomes the full-screen catcher for the duration
--     of the drag: SetHitRectInsets with large NEGATIVE values expands a
--     frame's hit rectangle without touching its size, its anchors or
--     how it draws (documented on UA: Frame.md#sethitrectinsets). The
--     cursor can then never leave the thumb, so the thumb's own
--     OnMouseUp fires wherever the button is released -- and the press
--     did start on it.
--     GetButtonState() == "PUSHED" (what vanilla's own FrameXML polls,
--     e.g. MessageFrameScrollButton_OnUpdate) is kept as a second
--     opinion, but is only ARMED once a PUSHED reading has actually been
--     seen during this drag. If this client reports something else for a
--     held button, the poll then never fires and we simply fall back to
--     OnMouseUp -- instead of killing the drag on its very first tick,
--     which is what "the thumb cannot be grabbed at all" looked like.
--     Two live findings that this arming preserves, so nobody re-derives
--     them: only a definite "PUSHED" may count as
--     held -- an earlier version treated anything that was not a definite
--     "NORMAL" as still held, and the drag then never ended at all,
--     because this client reports "UNKNOWN" the moment the mouse is
--     released (its own docs list DISABLED/PUSHED/NORMAL/UNKNOWN and note
--     that a plain hover-with-no-press already returns UNKNOWN, so its
--     state machine is not the vanilla one). Flipping that to "PUSHED"
--     is correct but not sufficient on its own -- hence the arming.
--     A dead-man timer is the last line of defence: an expanded hit rect
--     that never got restored would swallow every click in the UI, which
--     is far worse than a drag that ends late.
local DRAG_CAPTURE_INSET = -4000
local DRAG_MAX_SECONDS = 60

-- ...and ALL of the above is a UA workaround that must NOT run anywhere
-- else. On a real Blizzard client RegisterForDrag with OnDragStart/
-- OnDragStop works exactly as intended, and the expanded hit rectangle
-- actively BREAKS the widget there. Live-confirmed on real 1.12.1, in
-- LibDBIcon-1.0, whose minimap buttons carried this same
-- mechanism: after one drag the button behaved as though the cursor were
-- over it everywhere on screen -- its own tooltip stopped re-appearing on
-- hover, the OTHER button's OnLeave popped THIS one's tooltip up, and
-- further drags grabbed the two buttons alternately. All of that AFTER
-- the restore path had demonstrably run. Whether resetting the insets
-- fails to undo the expansion there, or the cached mouse focus is simply
-- never re-evaluated because the cursor never "left" the screen-sized
-- frame, was not measured -- and does not need to be, because the
-- workaround has no reason to run on that client at all.
--
-- Detecting UA: ported from the user's own `Bagzen.IsUA`. Deliberately
-- NOT `_VERSION == "Lua 5.1"`, which this library uses elsewhere for the
-- SetGradientAlpha quirk: that probe is only valid while the code ships
-- to exactly two clients (real 1.12.1 = Lua 5.0.3, UA = 5.1). 3.3.5 is
-- Lua 5.1 as well and would wrongly take the UA path. `GetUECvar` is the
-- Unreal engine's own cvar accessor and exists nowhere else; the 5875
-- interface number is the second half of the same upstream check.
local function DetectUA()
    if GetUECvar then return true end
    if type(GetBuildInfo) == "function" then
        local _, _, _, tocversion = GetBuildInfo()
        if tocversion == 5875 then return true end
    end
    return false
end

local USE_DRAG_CAPTURE = DetectUA()

-- Cursor position in the same coordinate space as GetLeft()/GetTop() --
-- screen pixels divided by the frame's own effective scale, the same
-- recipe the colour picker's CursorFraction uses further down.
local function CursorPoint(frame)
    if type(GetCursorPosition) ~= "function" then return nil end
    local ok, cx, cy = pcall(GetCursorPosition)
    if not ok or not tonumber(cx) or not tonumber(cy) then return nil end
    local scaleOk, scale = pcall(frame.GetEffectiveScale, frame)
    if not scaleOk or not tonumber(scale) or scale <= 0 then return nil end
    return cx / scale, cy / scale
end

-- true / false / nil, where nil means "this client would not tell us".
local function ButtonStillHeld(button)
    if not button or not button.GetButtonState then return nil end
    local ok, state = pcall(button.GetButtonState, button)
    if not ok or type(state) ~= "string" then return nil end
    return state == "PUSHED"
end

--- Wires OnMouseDown/OnMouseUp on `thumb` and an OnUpdate on `ticker`
--- into one drag. `handlers.onStart` runs once at press (capture the
--- grab offset there), `handlers.onUpdate` every tick while held (do the
--- cursor math and the SetPoint there), `handlers.onStop` once at
--- release (snap/commit there).
local function AttachThumbDrag(thumb, ticker, handlers)
    local dragging, armed, startedAt, restoreLevel = false, false, nil, nil

    local function Stop()
        if not dragging then return end
        dragging = false
        armed = false
        if USE_DRAG_CAPTURE then
            pcall(thumb.SetHitRectInsets, thumb, 0, 0, 0, 0)
        end
        if restoreLevel then
            pcall(thumb.SetFrameLevel, thumb, restoreLevel)
            restoreLevel = nil
        end
        if handlers.onStop then handlers.onStop() end
    end

    local function Start()
        if dragging then return end
        dragging = true
        armed = false
        startedAt = (type(GetTime) == "function" and GetTime()) or nil
        if USE_DRAG_CAPTURE then
            pcall(thumb.SetHitRectInsets, thumb,
                DRAG_CAPTURE_INSET, DRAG_CAPTURE_INSET, DRAG_CAPTURE_INSET, DRAG_CAPTURE_INSET)
            -- An expanded hit rectangle only wins the cursor if nothing
            -- sits ABOVE the thumb where the button happens to be
            -- released. Option widgets are created per page render, i.e.
            -- later than this thumb, and at equal frame levels the later
            -- frame wins -- so lift the thumb clear of its own siblings
            -- for the duration, and put it back afterwards. Frame LEVEL,
            -- not strata: everything that can realistically be under the
            -- cursor here is inside the same panel, hence the same
            -- strata, and a strata change has a much wider blast radius
            -- (it would also reorder us against other addons).
            local ok, level = pcall(thumb.GetFrameLevel, thumb)
            if ok and tonumber(level) then
                restoreLevel = level
                pcall(thumb.SetFrameLevel, thumb, level + 50)
            end
        end
        if handlers.onStart then handlers.onStart() end
    end

    if USE_DRAG_CAPTURE then
        thumb:SetScript("OnMouseDown", Start)
    else
        -- Real-client path: the client delivers both ends of the drag by
        -- itself, so use its own machinery and none of the compensation
        -- above. The cost is the client's ~15px travel threshold before
        -- OnDragStart -- a thumb has nothing else to do with a click, so
        -- that only makes the very first pixels of a drag lag slightly;
        -- it is not worth a second, hand-rolled threshold here.
        pcall(thumb.RegisterForDrag, thumb, "LeftButton")
        thumb:SetScript("OnDragStart", Start)
        thumb:SetScript("OnDragStop", Stop)
    end
    -- Second chance in both worlds: on UA the expanded hit rectangle is
    -- what makes this reachable, on a real client the release simply
    -- often does land on the thumb. Stop() is idempotent.
    thumb:SetScript("OnMouseUp", Stop)
    -- Hidden mid-drag (page switch, panel close) must not leave a drag --
    -- or, on UA, a screen-wide hit rectangle -- behind.
    thumb:SetScript("OnHide", Stop)

    ticker:SetScript("OnUpdate", function()
        if not dragging then return end

        if handlers.onUpdate then handlers.onUpdate() end

        -- Only meaningful while the hit rectangle keeps the cursor on the
        -- thumb. Without it the button un-pushes the moment the cursor
        -- moves off, and this would end every drag on its first tick.
        if USE_DRAG_CAPTURE then
            local held = ButtonStillHeld(thumb)
            if held == true then
                armed = true
            elseif held == false and armed then
                Stop()
                return
            end
        end

        if startedAt and type(GetTime) == "function" then
            local now = GetTime()
            if tonumber(now) and now - startedAt > DRAG_MAX_SECONDS then
                Stop()
            end
        end
    end)

    return Stop
end

local function CreateSlider(parent, options)
    options = options or {}
    local width = options.width or 200
    local min = tonumber(options.min) or 0
    local max = tonumber(options.max) or 100
    local step = tonumber(options.step) or 1
    if step <= 0 then step = 1 end
    local control = { min = min, max = max, step = step, uuiParts = {} }
    local parts = control.uuiParts

    local track = CreateFrame("Frame", options.name and (options.name .. "Track") or nil, parent)
    track:SetWidth(width)
    track:SetHeight(8)
    CreateBackdrop(track, {})
    control.track = track
    table.insert(parts, track)

    local function Clamp(raw)
        raw = tonumber(raw)
        if not raw then return min end
        raw = math.floor((raw - min) / step + 0.5) * step + min
        if raw < min then raw = min end
        if raw > max then raw = max end
        return raw
    end

    local THUMB_WIDTH, THUMB_HEIGHT = 12, 14
    local thumb = CreateFrame("Button", options.name and (options.name .. "Thumb") or nil, track)
    thumb:SetWidth(THUMB_WIDTH)
    thumb:SetHeight(THUMB_HEIGHT)
    pcall(thumb.EnableMouse, thumb, true)
    -- Drag registration is AttachThumbDrag's business, not this one's: on
    -- UA the drag starts from OnMouseDown and the thumb is deliberately
    -- NOT registered (registering would only add the client's own 15-pixel
    -- dead zone before anything happens), on a real client it registers
    -- and uses OnDragStart/OnDragStop. Don't register it here.
    CreateBackdrop(thumb, { background = THEME.sliderThumb, border = THEME.border })
    control.thumb = thumb
    table.insert(parts, thumb)

    thumb:SetScript("OnEnter", function() SetBorderColor(thumb, THEME.accent) end)
    thumb:SetScript("OnLeave", function() SetBorderColor(thumb, THEME.border) end)

    local function PlaceThumb(value)
        local usable = width - THUMB_WIDTH
        local offset = 0
        if max > min and usable > 0 then
            offset = (Clamp(value) - min) / (max - min) * usable
        end
        thumb:ClearAllPoints()
        thumb:SetPoint("LEFT", track, "LEFT", offset, 0)
    end

    local minLabel = CreateLabel(parent, {
        color = THEME.textDim,
        inherits = "GameFontNormalSmall",
        width = width / 2,
        height = 12,
    })
    if minLabel then
        minLabel:SetPoint("TOPLEFT", track, "BOTTOMLEFT", 0, -3)
        minLabel:SetText(tostring(min))
    end
    table.insert(parts, minLabel)

    local maxLabel = CreateLabel(parent, {
        color = THEME.textDim,
        inherits = "GameFontNormalSmall",
        width = width / 2,
        height = 12,
        justify = "RIGHT",
    })
    if maxLabel then
        maxLabel:SetPoint("TOPRIGHT", track, "BOTTOMRIGHT", 0, -3)
        maxLabel:SetText(tostring(max))
    end
    table.insert(parts, maxLabel)

    local boxWidth = options.boxWidth or 74
    local BOX_HEIGHT = 16
    local BOX_GAP = 4
    -- Exposed so RenderLeaf can offset the whole slider assembly down by
    -- this much instead of hardcoding a duplicate magic number -- this
    -- box floats ABOVE `track` (see the SetPoint below), so whatever
    -- anchors `track`'s own TOPLEFT needs to leave this much room above
    -- it, or the box pokes into whatever renders above the slider.
    control.topOffset = BOX_HEIGHT + BOX_GAP
    local box = CreateFrame("Frame", options.name and (options.name .. "Value") or nil, parent)
    box:SetWidth(boxWidth)
    box:SetHeight(BOX_HEIGHT)
    CreateBackdrop(box, {})
    box:SetPoint("BOTTOM", track, "TOP", 0, BOX_GAP)
    control.box = box
    table.insert(parts, box)

    -- Editable readout -- type an exact value instead of only dragging the
    -- thumb, matching real AceGUI's own Slider widget (which has always
    -- had this; this library's own version used to be a plain,
    -- non-interactive label). Script wiring (Enter/Escape/focus-lost)
    -- is added further down, once `Publish`/`Clamp` exist.
    local readout = CreateFrame("EditBox", options.name and (options.name .. "EditBox") or nil, box)
    readout:SetPoint("TOPLEFT", box, "TOPLEFT", 3, -1)
    readout:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -3, 1)
    pcall(readout.SetAutoFocus, readout, false)
    pcall(readout.SetJustifyH, readout, "CENTER")
    pcall(readout.SetFontObject, readout, GameFontHighlightSmall)
    SetTextColor(readout, THEME.text)
    control.readout = readout
    table.insert(parts, readout)

    local function UpdateReadout(raw)
        local clamped = Clamp(raw)
        control.current = clamped
        if readout then readout:SetText(tostring(clamped)) end
        return clamped
    end

    local function Publish(raw, silent)
        local clamped = UpdateReadout(raw)
        PlaceThumb(clamped)
        if not silent and type(options.onChange) == "function" then
            options.onChange(clamped)
        end
        return clamped
    end

    -- Guards against firing onChange twice for one Enter press: OnEnterPressed
    -- clears focus, which also fires OnEditFocusLost -- by the second call the
    -- box already shows the clamped value, so it's a no-op resync, not a
    -- second Publish.
    local function CommitTypedValue()
        local raw = tonumber(readout:GetText())
        if not raw then
            UpdateReadout(control.current or min)
            return
        end
        local clamped = Clamp(raw)
        if clamped == control.current then
            UpdateReadout(clamped)
            return
        end
        Publish(clamped)
    end

    readout:SetScript("OnEnterPressed", function()
        CommitTypedValue()
        pcall(readout.ClearFocus, readout)
    end)
    readout:SetScript("OnEditFocusGained", function() focusedEditBox = readout end)
    readout:SetScript("OnEditFocusLost", function()
        if focusedEditBox == readout then focusedEditBox = nil end
        CommitTypedValue()
    end)
    readout:SetScript("OnEscapePressed", function()
        UpdateReadout(control.current or min)
        pcall(readout.ClearFocus, readout)
    end)

    -- Live tracking while dragging. The thumb is positioned BY US, from the
    -- cursor, clamped to the track -- see AttachThumbDrag's own comment
    -- above for why it is no longer handed to StartMoving. The practical
    -- difference: only the X coordinate is ever written, so the thumb can
    -- no longer be dragged up and down off its own track, which range
    -- sliders were previously still able to do.
    -- onChange fires for each newly-reached STEPPED value (Ace3-style live
    -- execution) while the thumb itself follows the cursor smoothly; the
    -- release snaps it onto the stepped position.
    local lastLiveValue
    local grabOffset = 0

    local function UsableWidth()
        local widthOk, trackWidth = pcall(track.GetWidth, track)
        trackWidth = (widthOk and tonumber(trackWidth)) or width
        return trackWidth - THUMB_WIDTH
    end

    local liveTicker = CreateFrame("Frame", nil, parent)

    AttachThumbDrag(thumb, liveTicker, {
        onStart = function()
            lastLiveValue = control.current
            local cx = CursorPoint(track)
            local leftOk, thumbLeft = pcall(thumb.GetLeft, thumb)
            if cx and leftOk and tonumber(thumbLeft) then
                -- Keeps the exact point that was clicked under the cursor,
                -- instead of snapping the thumb's left edge to it.
                grabOffset = thumbLeft - cx
            else
                grabOffset = 0
            end
        end,

        onUpdate = function()
            local cx = CursorPoint(track)
            local trackOk, trackLeft = pcall(track.GetLeft, track)
            if not (cx and trackOk and tonumber(trackLeft)) then return end
            local usable = UsableWidth()
            if usable <= 0 then return end

            local offset = cx + grabOffset - trackLeft
            if offset < 0 then offset = 0 end
            if offset > usable then offset = usable end

            -- X only. Never write the vertical anchor: that is the whole
            -- axis constraint.
            thumb:ClearAllPoints()
            thumb:SetPoint("LEFT", track, "LEFT", offset, 0)

            if max > min then
                local clamped = Clamp(min + offset / usable * (max - min))
                if clamped ~= lastLiveValue then
                    lastLiveValue = clamped
                    UpdateReadout(clamped)
                    if type(options.onChange) == "function" then
                        options.onChange(clamped)
                    end
                end
            end
        end,

        onStop = function()
            -- The thumb tracked the cursor smoothly; put it back on the
            -- exact stepped position of whatever value was committed.
            PlaceThumb(control.current or min)
        end,
    })

    control.SetValue = function(raw)
        Publish(raw, true)
    end

    control.SetPoint = function(self, point, relative, relativePoint, x, y)
        track:ClearAllPoints()
        track:SetPoint(point, relative, relativePoint, x, y)
    end

    control.SetValue(options.value or min)
    return control
end

-- ===========================================================================
-- Scrollbar (MINOR 11)
--
-- A real ElvUI-looking vertical scrollbar -- a thin dark track between two
-- small square arrow buttons, with a draggable thumb sized to how much of
-- the content is visible -- replacing the pair of loose "^"/"v" buttons
-- that used to sit in the footer.
--
-- Built from this library's own primitives rather than the native Slider
-- the real FrameXML scrollbar templates use: the native Slider widget is
-- broken on Unreal Azeroth (which is why `range` options are a drag-thumb
-- Button here too). The DRAG mechanics are the shared ones -- see
-- AttachThumbDrag, well above, for the whole story.
--
-- The scrollbar drives an OFFSET IN PIXELS (0 .. maxOffset) and reports it
-- through options.onScroll -- it does not own the scrolling itself, so the
-- same widget works both for a real ScrollFrame and for a hand-positioned
-- list (see the dropdown menu, whose rows are placed by hand).
local SCROLLBAR_WIDTH = 16
local SCROLLBAR_BUTTON = 16
local SCROLLBAR_MIN_THUMB = 20

local function CreateScrollBar(parent, options)
    options = options or {}
    local control = { maxOffset = 0, value = 0, visibleRatio = 1 }
    local step = options.step or ROW_HEIGHT

    local bar = CreateFrame("Frame", options.name, parent)
    bar:SetWidth(SCROLLBAR_WIDTH)
    control.frame = bar

    local upBtn = CreateButton(bar, {
        name = options.name and (options.name .. "Up") or nil,
        width = SCROLLBAR_WIDTH,
        height = SCROLLBAR_BUTTON,
    })
    upBtn:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    SetButtonGlyph(upBtn, "UP")
    control.upBtn = upBtn

    local downBtn = CreateButton(bar, {
        name = options.name and (options.name .. "Down") or nil,
        width = SCROLLBAR_WIDTH,
        height = SCROLLBAR_BUTTON,
    })
    downBtn:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
    SetButtonGlyph(downBtn, "DOWN")
    control.downBtn = downBtn

    -- Track: the dark recessed channel, drawn behind the thumb.
    local track = CreateFrame("Frame", nil, bar)
    track:SetPoint("TOPLEFT", upBtn, "BOTTOMLEFT", 0, -2)
    track:SetPoint("BOTTOMRIGHT", downBtn, "TOPRIGHT", 0, 2)
    CreateBackdrop(track, { background = THEME.backdropFade or THEME.backdrop })
    control.track = track

    -- Thumb: a plain Button dragged by hand -- same shared mechanics as
    -- CreateSlider's own thumb (see AttachThumbDrag). NOT a native Slider:
    -- that was tried here as a client-owns-the-drag shortcut and reverted
    -- -- it was never actually confirmed live (the comment that used to
    -- justify it only cited the user testing an UNRELATED stock FrameXML
    -- scrollbar), and every other drag-thumb in this library avoids the
    -- native Slider for the same documented reason (broken on Unreal
    -- Azeroth) -- singling this one out on an unverified exception wasn't
    -- worth it.
    local thumb = CreateFrame("Button", options.name and (options.name .. "Thumb") or nil, track)
    thumb:SetWidth(SCROLLBAR_WIDTH - 4)
    thumb:SetHeight(SCROLLBAR_MIN_THUMB)
    pcall(thumb.EnableMouse, thumb, true)
    -- Drag registration is AttachThumbDrag's business -- see the slider's
    -- own thumb.
    CreateBackdrop(thumb, { background = THEME.sliderThumb, border = THEME.border })
    control.thumb = thumb

    thumb:SetScript("OnEnter", function() SetBorderColor(thumb, THEME.accent) end)
    thumb:SetScript("OnLeave", function() SetBorderColor(thumb, THEME.border) end)

    -- Cursor Y in the same coordinate space as GetTop().
    local function CursorY()
        local _, cy = CursorPoint(bar)
        return cy
    end

    -- While the thumb is being dragged it OWNS its own position -- see
    -- PlaceThumb. Nothing else may move it until the button is released.
    local isDragging = false

    -- Places the thumb for a given scroll value. Called directly via
    -- SetPoint, never via StartMoving -- so calling this mid-drag would be
    -- harmless as far as the client is concerned (the "SetPoint during a
    -- drag breaks it" finding only ever applied to fighting StartMoving,
    -- which this thumb never calls at all). It is refused anyway, because
    -- of a feedback loop that is easy to walk into and confusing to
    -- diagnose: a consumer's `onScroll` may re-enter this widget through
    -- SetValue -- the sidebar's does, since RenderSidebar QUANTISES the
    -- offset to whole rows and pushes it straight back -- so every drag
    -- tick would yank the thumb onto the nearest row boundary while the
    -- cursor held it somewhere else. That reads as "the bar's positioning
    -- is broken", not as a feedback loop.
    local function PlaceThumb(value)
        if isDragging then return end
        local trackHeightOk, trackHeight = pcall(track.GetHeight, track)
        trackHeight = (trackHeightOk and tonumber(trackHeight)) or 0
        local thumbHeightOk, thumbHeight = pcall(thumb.GetHeight, thumb)
        thumbHeight = (thumbHeightOk and tonumber(thumbHeight)) or SCROLLBAR_MIN_THUMB
        local usable = trackHeight - thumbHeight
        local offset = 0
        if control.maxOffset > 0 and usable > 0 then
            offset = (value / control.maxOffset) * usable
            if offset < 0 then offset = 0 end
            if offset > usable then offset = usable end
        end
        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", track, "TOP", 0, -offset)
    end

    control.SetValue = function(value, notify)
        value = tonumber(value) or 0
        if value < 0 then value = 0 end
        if value > control.maxOffset then value = control.maxOffset end
        control.value = value
        PlaceThumb(value)
        if notify and type(options.onScroll) == "function" then
            options.onScroll(value)
        end
    end

    control.GetValue = function()
        return control.value
    end

    --- maxOffset     how far the content can scroll, in pixels
    --- visibleRatio  visible height / total content height (0..1); sizes
    ---               the thumb the way every real scrollbar does, so its
    ---               length tells you how much you are seeing.
    control.SetRange = function(maxOffset, visibleRatio)
        control.maxOffset = tonumber(maxOffset) or 0
        if control.maxOffset < 0 then control.maxOffset = 0 end

        visibleRatio = tonumber(visibleRatio) or 1
        if visibleRatio < 0 then visibleRatio = 0 end
        if visibleRatio > 1 then visibleRatio = 1 end
        control.visibleRatio = visibleRatio

        local okT, trackHeight = pcall(track.GetHeight, track)
        trackHeight = (okT and tonumber(trackHeight)) or 0
        local thumbHeight = trackHeight * visibleRatio
        if thumbHeight < SCROLLBAR_MIN_THUMB then thumbHeight = SCROLLBAR_MIN_THUMB end
        if thumbHeight > trackHeight and trackHeight > 0 then thumbHeight = trackHeight end
        pcall(thumb.SetHeight, thumb, thumbHeight)

        if control.value > control.maxOffset then
            control.value = control.maxOffset
        end
        PlaceThumb(control.value)
    end

    -- Dragging: the client does NOT own the movement. Cursor position is
    -- read every tick, clamped to the track's own axis, and the thumb is
    -- SetPoint'd straight to it -- a grab offset captured at press time
    -- keeps the point that was clicked under the cursor instead of
    -- snapping the thumb's TOP edge there. Only the Y coordinate is ever
    -- written, so the thumb cannot drift sideways off its track.
    -- See AttachThumbDrag for how the press and the release are detected.
    local grabOffset = 0
    local lastLiveValue

    -- Parented to `parent`, NOT to `bar`: `control.SetShown` hides `bar`
    -- whenever the page fits, and a hidden ticker is a ticker whose
    -- OnUpdate never runs again -- which would look exactly like "the
    -- thumb cannot be dragged".
    local ticker = CreateFrame("Frame", nil, parent)

    AttachThumbDrag(thumb, ticker, {
        onStart = function()
            isDragging = true
            lastLiveValue = control.value
            local cy = CursorY()
            local topOk, thumbTop = pcall(thumb.GetTop, thumb)
            if cy and topOk and tonumber(thumbTop) then
                grabOffset = thumbTop - cy
            else
                grabOffset = 0
            end
        end,

        onUpdate = function()
            local cy = CursorY()
            local trackTopOk, trackTop = pcall(track.GetTop, track)
            local trackHeightOk, trackHeight = pcall(track.GetHeight, track)
            if not (cy and trackTopOk and trackHeightOk and
                    tonumber(trackTop) and tonumber(trackHeight)) then
                return
            end

            local thumbHeightOk, thumbHeight = pcall(thumb.GetHeight, thumb)
            thumbHeight = (thumbHeightOk and tonumber(thumbHeight)) or SCROLLBAR_MIN_THUMB
            local usable = trackHeight - thumbHeight
            if usable <= 0 then return end

            local offset = trackTop - (cy + grabOffset)
            if offset < 0 then offset = 0 end
            if offset > usable then offset = usable end

            -- Y only -- the axis constraint.
            thumb:ClearAllPoints()
            thumb:SetPoint("TOP", track, "TOP", 0, -offset)

            local value = (offset / usable) * control.maxOffset
            control.value = value
            if value ~= lastLiveValue then
                lastLiveValue = value
                if type(options.onScroll) == "function" then
                    options.onScroll(value)
                end
            end
        end,

        onStop = function()
            isDragging = false
            -- The consumer may have quantised the offset behind our back
            -- (the sidebar scrolls in whole rows); settle the thumb on
            -- whatever it actually ended up with.
            PlaceThumb(control.value)
        end,
    })

    -- The arrow buttons nudge by one step -- same shape as
    -- UIPanelScrollBarTemplate's own up/down buttons calling
    -- parent:SetValue().
    upBtn:SetScript("OnClick", function()
        control.SetValue(control.value - step, true)
    end)
    downBtn:SetScript("OnClick", function()
        control.SetValue(control.value + step, true)
    end)

    control.SetShown = function(shown)
        if shown then bar:Show() else bar:Hide() end
        -- Children do not reliably follow a parent's Show/Hide on Unreal
        -- Azeroth, so every piece is toggled explicitly.
        local pieces = { upBtn, downBtn, track, thumb }
        local i
        for i = 1, table.getn(pieces) do
            if shown then pieces[i]:Show() else pieces[i]:Hide() end
        end
    end

    return control
end

-- ===========================================================================
-- Color picker
--
-- The stock ColorPickerFrame's ColorSelect wheel/gradient surfaces do not
-- render or hit-test on Unreal Azeroth (independently confirmed by
-- UnrealUI, source/UnrealUI/core/widgets.lua:795-821 -- its own dialog's
-- chrome, title and Okay/Cancel draw normally, only the ColorSelect
-- widget itself is broken). This ports that same proven-on-UA
-- construction rather than reaching for the native widget: a hand-drawn
-- saturation/value square + hue strip (flat textures tinted with
-- SetGradientAlpha, dragged the same way CreateSlider's own thumb above
-- already is) plus R/G/B/A sliders that stay in sync and keep the dialog
-- fully usable even on a client where gradients don't render at all. One
-- shared dialog serves every swatch -- only one can be open at a time,
-- and content is rebuilt page by page, so a per-control dialog would leak
-- a frame for every swatch ever shown (same reasoning as `activeDropdown`
-- above).
-- ===========================================================================

-- UnrealUI found Unreal Azeroth anchors the FIRST colour stop at the TOP
-- for a "VERTICAL" SetGradientAlpha, where real vanilla 1.12.1 anchors it
-- at the BOTTOM (source/UnrealUI/core/widgets.lua:1096-1101, confirmed
-- in-game on UA specifically). This library ships to both clients, so the
-- value-gradient's stop order is swapped based on which Lua the client is
-- actually running -- the same kind of client-detection this project's
-- ElvUI addon already does elsewhere (Compat.isLua50) for an analogous
-- UA-vs-1.12.1 quirk. Unverified directly in THIS library on real 1.12.1,
-- but matches UnrealUI's own finding, which was UA-specific.
local UA_GRADIENT_ORIGIN_TOP = (_VERSION == "Lua 5.1")

local function WrapHue(h)
    while h < 0 do h = h + 360 end
    while h >= 360 do h = h - 360 end
    return h
end

local function Clamp01(v)
    v = tonumber(v) or 0
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
end

local function HSVtoRGB(h, s, v)
    h, s, v = WrapHue(h), Clamp01(s), Clamp01(v)
    if s <= 0 then return v, v, v end

    local sector = h / 60
    local i = math.floor(sector)
    local f = sector - i
    local p = v * (1 - s)
    local q = v * (1 - s * f)
    local t = v * (1 - s * (1 - f))

    if i == 0 then return v, t, p end
    if i == 1 then return q, v, p end
    if i == 2 then return p, v, t end
    if i == 3 then return p, q, v end
    if i == 4 then return t, p, v end
    return v, p, q
end

local function RGBtoHSV(r, g, b)
    r, g, b = Clamp01(r), Clamp01(g), Clamp01(b)
    local max = math.max(r, math.max(g, b))
    local min = math.min(r, math.min(g, b))
    local d = max - min

    local h = 0
    if d > 0 then
        if max == r then
            h = (g - b) / d
            if h < 0 then h = h + 6 end
        elseif max == g then
            h = (b - r) / d + 2
        else
            h = (r - g) / d + 4
        end
        h = h * 60
    end

    local s = 0
    if max > 0 then s = d / max end
    return WrapHue(h), s, max
end

-- Reads a point inside `area` from the cursor, in 0..1 on each axis
-- (click-to-jump). Returns nil unless every call succeeds and the result
-- actually lies inside the area -- a client that reports nothing useful
-- simply loses click-to-jump; the drag handles remain the primary way to
-- pick a colour regardless.
local function CursorFraction(area)
    if type(GetCursorPosition) ~= "function" then return nil end

    local ok, cx, cy = pcall(GetCursorPosition)
    if not ok or not tonumber(cx) or not tonumber(cy) then return nil end

    local scaleOk, scale = pcall(area.GetEffectiveScale, area)
    if not scaleOk or not tonumber(scale) or scale <= 0 then return nil end

    local leftOk, left = pcall(area.GetLeft, area)
    local topOk, top = pcall(area.GetTop, area)
    local wOk, w = pcall(area.GetWidth, area)
    local hOk, h = pcall(area.GetHeight, area)
    if not (leftOk and topOk and wOk and hOk) then return nil end
    if not (tonumber(left) and tonumber(top) and tonumber(w) and tonumber(h)) then
        return nil
    end
    if w <= 0 or h <= 0 then return nil end

    local px = cx / scale - left
    local py = top - cy / scale
    if px < 0 or px > w or py < 0 or py > h then return nil end

    return px / w, py / h
end

-- The same drag recipe CreateSlider's thumb above already uses: a Button
-- (only a Button reliably receives OnDragStart here), SetMovable applied
-- immediately before each drag, a throwaway StartMoving/
-- StopMovingOrSizing pair to collapse multi-point anchors, then the real
-- StartMoving -- and the marker is NOT repositioned mid-drag (breaks the
-- drag outright on this client, per CreateSlider's own comment above),
-- only tracked via a separate OnUpdate ticker and snapped into place on
-- release.
local function AttachDragMarker(area, marker, onMove)
    local function Measure(object, method)
        local ok, value = pcall(method, object)
        if not ok then return nil end
        return tonumber(value)
    end

    local function ReadFraction()
        local mLeft = Measure(marker, marker.GetLeft)
        local mTop = Measure(marker, marker.GetTop)
        local mW = Measure(marker, marker.GetWidth)
        local mH = Measure(marker, marker.GetHeight)
        local aLeft = Measure(area, area.GetLeft)
        local aTop = Measure(area, area.GetTop)
        local aW = Measure(area, area.GetWidth)
        local aH = Measure(area, area.GetHeight)

        if not (mLeft and mTop and mW and mH and aLeft and aTop and aW and aH) then
            return nil
        end
        if aW <= 0 or aH <= 0 then return nil end

        local fx = ((mLeft + mW / 2) - aLeft) / aW
        local fy = (aTop - (mTop - mH / 2)) / aH
        return Clamp01(fx), Clamp01(fy)
    end

    local dragging = false
    local ticker = CreateFrame("Frame", nil, marker)
    ticker:SetScript("OnUpdate", function()
        if not dragging then return end
        local fx, fy = ReadFraction()
        if fx then onMove(fx, fy, true) end
    end)

    marker:SetScript("OnDragStart", function()
        if not pcall(marker.SetMovable, marker, true) then return end
        if pcall(marker.StartMoving, marker) then
            pcall(marker.StopMovingOrSizing, marker)
        end
        pcall(marker.StartMoving, marker)
        dragging = true
    end)

    marker:SetScript("OnDragStop", function()
        dragging = false
        pcall(marker.StopMovingOrSizing, marker)
        local fx, fy = ReadFraction()
        if fx then onMove(fx, fy, false) end
    end)
end

-- One shared dialog, built lazily and reused by every swatch (see the
-- section comment above for why). CloseColorDialog is forward-declared so
-- EnsureColorDialog's Okay/Cancel buttons can close over it before it's
-- assigned below.
local colorDialog
local CloseColorDialog

local function EnsureColorDialog()
    if colorDialog then return colorDialog end

    local DIALOG_WIDTH = 300
    local SQUARE_W, SQUARE_H = 196, 140
    local STRIP_H = 18
    local SLIDER_SPACING = 44
    local SLIDER_TOP = 214

    -- Parented to UIParent (not the options panel) and above it in strata,
    -- matching UnrealUI's own choice -- this dialog can be summoned from a
    -- "color" leaf on any registered category's page.
    local d = CreatePanel(UIParent, {
        name = "LibConfigColorPicker",
        width = DIALOG_WIDTH,
        height = 420,
    })
    pcall(d.SetFrameStrata, d, "DIALOG")
    pcall(d.EnableMouse, d, true)
    d:Hide()
    colorDialog = d

    d.title = CreateLabel(d, {
        color = THEME.accent,
        inherits = "GameFontNormal",
        justify = "CENTER",
        width = DIALOG_WIDTH - 20,
        height = 16,
    })
    if d.title then
        d.title:SetPoint("TOP", d, "TOP", 0, -10)
        d.title:SetText("Select Color")
    end

    local preview = CreateFrame("Frame", "LibConfigColorPickerPreview", d)
    preview:SetWidth(SQUARE_W)
    preview:SetHeight(20)
    preview:SetPoint("TOP", d, "TOP", 0, -32)
    CreateBackdrop(preview, {})
    local previewFill = preview:CreateTexture(nil, "ARTWORK")
    previewFill:SetTexture(THEME.plain)
    previewFill:SetPoint("TOPLEFT", preview, "TOPLEFT", 2, -2)
    previewFill:SetPoint("BOTTOMRIGHT", preview, "BOTTOMRIGHT", -2, 2)
    d.previewFill = previewFill

    -- Saturation/value square: three stacked layers (flat hue, white
    -- fading out to the right for saturation, black fading out toward the
    -- bottom for value) make the standard picker face.
    local square = CreateFrame("Frame", "LibConfigColorPickerSquare", d)
    square:SetWidth(SQUARE_W)
    square:SetHeight(SQUARE_H)
    square:SetPoint("TOP", d, "TOP", 0, -60)
    CreateBackdrop(square, {})
    pcall(square.EnableMouse, square, true)
    d.square = square

    local hueFill = square:CreateTexture(nil, "BACKGROUND")
    hueFill:SetTexture(THEME.plain)
    hueFill:SetPoint("TOPLEFT", square, "TOPLEFT", 2, -2)
    hueFill:SetPoint("BOTTOMRIGHT", square, "BOTTOMRIGHT", -2, 2)

    local satFill = square:CreateTexture(nil, "ARTWORK")
    satFill:SetTexture(THEME.plain)
    satFill:SetAllPoints(hueFill)

    local valFill = square:CreateTexture(nil, "OVERLAY")
    valFill:SetTexture(THEME.plain)
    valFill:SetAllPoints(hueFill)

    SetRegionColor(satFill, { 1, 1, 1, 1 })
    SetRegionColor(valFill, { 0, 0, 0, 1 })

    -- Gradient support is probed once: if SetGradientAlpha is missing or
    -- the first call errors, the whole square/strip is hidden outright
    -- (see CreateColorPicker below) rather than left showing three flat,
    -- non-gradient blocks -- the R/G/B/A sliders carry the dialog alone.
    local gradients = true
    local function Gradient(texture, orientation, r1, g1, b1, a1, r2, g2, b2, a2)
        if not gradients then return false end
        if type(texture.SetGradientAlpha) ~= "function" then
            gradients = false
            return false
        end
        local ok = pcall(texture.SetGradientAlpha, texture, orientation, r1, g1, b1, a1, r2, g2, b2, a2)
        if not ok then gradients = false end
        return ok
    end

    Gradient(satFill, "HORIZONTAL", 1, 1, 1, 1, 1, 1, 1, 0)
    if UA_GRADIENT_ORIGIN_TOP then
        Gradient(valFill, "VERTICAL", 0, 0, 0, 0, 0, 0, 0, 1)
    else
        Gradient(valFill, "VERTICAL", 0, 0, 0, 1, 0, 0, 0, 0)
    end

    d.squareLayers = { hueFill, satFill, valFill }

    local marker = CreateFrame("Button", "LibConfigColorPickerMarker", square)
    marker:SetWidth(10)
    marker:SetHeight(10)
    pcall(marker.EnableMouse, marker, true)
    pcall(marker.RegisterForDrag, marker, "LeftButton")
    CreateBackdrop(marker, { background = { 0, 0, 0, 0 }, border = THEME.text })
    d.marker = marker

    local strip = CreateFrame("Frame", "LibConfigColorPickerHue", d)
    strip:SetWidth(SQUARE_W)
    strip:SetHeight(STRIP_H)
    strip:SetPoint("TOP", square, "BOTTOM", 0, -10)
    CreateBackdrop(strip, {})
    pcall(strip.EnableMouse, strip, true)
    d.strip = strip

    -- Six equal segments, each a gradient between two neighbouring pure
    -- hues -- not subject to the vertical-origin quirk above (only
    -- VERTICAL was reported reversed), so this stays unconditional.
    local HUE_STOPS = {
        { 1, 0, 0 }, { 1, 1, 0 }, { 0, 1, 0 },
        { 0, 1, 1 }, { 0, 0, 1 }, { 1, 0, 1 }, { 1, 0, 0 },
    }
    local segmentWidth = (SQUARE_W - 4) / 6
    d.hueSegments = {}
    local s
    for s = 1, 6 do
        local segment = strip:CreateTexture(nil, "ARTWORK")
        segment:SetTexture(THEME.plain)
        segment:SetWidth(segmentWidth)
        segment:SetPoint("TOPLEFT", strip, "TOPLEFT", 2 + (s - 1) * segmentWidth, -2)
        segment:SetPoint("BOTTOMLEFT", strip, "BOTTOMLEFT", 2 + (s - 1) * segmentWidth, 2)
        local from, to = HUE_STOPS[s], HUE_STOPS[s + 1]
        SetRegionColor(segment, { from[1], from[2], from[3], 1 })
        Gradient(segment, "HORIZONTAL", from[1], from[2], from[3], 1, to[1], to[2], to[3], 1)
        table.insert(d.hueSegments, segment)
    end

    local hueThumb = CreateFrame("Button", "LibConfigColorPickerHueThumb", strip)
    hueThumb:SetWidth(8)
    hueThumb:SetHeight(STRIP_H + 6)
    pcall(hueThumb.EnableMouse, hueThumb, true)
    pcall(hueThumb.RegisterForDrag, hueThumb, "LeftButton")
    CreateBackdrop(hueThumb, { background = { 0, 0, 0, 0 }, border = THEME.text })
    d.hueThumb = hueThumb

    -- HSV is the dialog's working representation -- RGB alone cannot
    -- express "same hue, no saturation", so dragging into a grey corner
    -- and back out would otherwise lose the hue that was chosen.
    d.hsv = { h = 0, s = 0, v = 1 }
    local syncing = false

    local function PlaceMarkers()
        local w = SQUARE_W - 4
        local h = SQUARE_H - 4
        marker:ClearAllPoints()
        marker:SetPoint("CENTER", square, "TOPLEFT", 2 + d.hsv.s * w, -2 - (1 - d.hsv.v) * h)

        hueThumb:ClearAllPoints()
        hueThumb:SetPoint("CENTER", strip, "TOPLEFT", 2 + (d.hsv.h / 360) * (SQUARE_W - 4), -STRIP_H / 2)
    end

    local function PaintSquareHue()
        local r, g, b = HSVtoRGB(d.hsv.h, 1, 1)
        SetRegionColor(hueFill, { r, g, b, 1 })
    end

    local function UpdatePreview()
        local v = d.current or {}
        SetRegionColor(previewFill, { v.r or 1, v.g or 1, v.b or 1, v.a or 1 })
    end
    d.UpdatePreview = UpdatePreview

    local function Publish(skipSliders)
        if not d.current then return end
        UpdatePreview()
        if d.onPreview then d.onPreview(d.current) end

        if not skipSliders and d.sliders then
            syncing = true
            d.sliders.r.SetValue(math.floor(d.current.r * 255 + 0.5))
            d.sliders.g.SetValue(math.floor(d.current.g * 255 + 0.5))
            d.sliders.b.SetValue(math.floor(d.current.b * 255 + 0.5))
            syncing = false
        end
    end

    -- Called by the square/strip: HSV is authoritative, RGB derived.
    local function ApplyHSV(skipMarkers)
        if not d.current then return end
        local r, g, b = HSVtoRGB(d.hsv.h, d.hsv.s, d.hsv.v)
        d.current.r, d.current.g, d.current.b = r, g, b
        PaintSquareHue()
        if not skipMarkers then PlaceMarkers() end
        Publish(false)
    end

    -- Called by the sliders: RGB is authoritative, HSV re-derived so the
    -- markers follow. A value/saturation of zero carries no hue, so the
    -- previous hue is kept rather than snapped back to red.
    local function AdoptRGB()
        local h, sat, val = RGBtoHSV(d.current.r, d.current.g, d.current.b)
        if sat > 0 then d.hsv.h = h end
        d.hsv.s, d.hsv.v = sat, val
        PaintSquareHue()
        PlaceMarkers()
    end
    d.AdoptRGB = AdoptRGB

    AttachDragMarker(square, marker, function(fx, fy, dragging)
        d.hsv.s = Clamp01(fx)
        d.hsv.v = Clamp01(1 - fy)
        -- Mid-drag the marker must not be re-anchored (see AttachDragMarker's
        -- own comment above), hence skipMarkers = dragging.
        ApplyHSV(dragging)
    end)

    AttachDragMarker(strip, hueThumb, function(fx, fy, dragging)
        d.hsv.h = Clamp01(fx) * 360
        ApplyHSV(dragging)
    end)

    square:SetScript("OnMouseDown", function()
        local fx, fy = CursorFraction(square)
        if not fx then return end
        d.hsv.s, d.hsv.v = Clamp01(fx), Clamp01(1 - fy)
        ApplyHSV(false)
    end)

    strip:SetScript("OnMouseDown", function()
        local fx = CursorFraction(strip)
        if not fx then return end
        d.hsv.h = Clamp01(fx) * 360
        ApplyHSV(false)
    end)

    -- Channels are 0-255 in the UI, 0-1 in storage: the slider's own
    -- readout box is the only numeric feedback there is, and 0-255 stays
    -- readable where 0-1 would need decimals the integer step can't
    -- express.
    local CHANNELS = { { "r", "Red" }, { "g", "Green" }, { "b", "Blue" }, { "a", "Opacity" } }
    d.sliders = {}
    local i
    for i = 1, table.getn(CHANNELS) do
        local key = CHANNELS[i][1]
        local slider = CreateSlider(d, {
            name = "LibConfigColorPicker" .. string.upper(key),
            width = SQUARE_W,
            min = 0,
            max = 255,
            step = 1,
            value = 255,
            onChange = function(value)
                if syncing or not d.current then return end
                d.current[key] = value / 255
                if key ~= "a" then AdoptRGB() end
                Publish(true)
            end,
        })
        slider:SetPoint("TOP", d, "TOP", 0, -(SLIDER_TOP + (i - 1) * SLIDER_SPACING))
        local caption = CreateLabel(d, {
            color = THEME.textDim,
            inherits = "GameFontNormalSmall",
            justify = "LEFT",
            width = 60,
            height = 12,
        })
        if caption and slider.track then
            caption:SetPoint("BOTTOMLEFT", slider.track, "TOPLEFT", 0, 14)
            caption:SetText(CHANNELS[i][2])
        end
        slider.caption = caption
        -- So SetShown(slider, ...) (used above to hide the opacity
        -- slider when hasAlpha is false) also toggles this label -- it
        -- isn't part of CreateSlider's own uuiParts since it's added
        -- here, after CreateSlider already returned.
        table.insert(slider.uuiParts, caption)
        d.sliders[key] = slider
    end

    d.gradients = gradients

    local accept = CreateButton(d, {
        name = "LibConfigColorPickerOkay",
        text = "OK",
        width = 90,
        height = 22,
        onClick = function() CloseColorDialog(true) end,
    })
    accept:SetPoint("BOTTOMRIGHT", d, "BOTTOM", -4, 14)
    d.accept = accept

    local cancel = CreateButton(d, {
        name = "LibConfigColorPickerCancel",
        text = "Cancel",
        width = 90,
        height = 22,
        onClick = function() CloseColorDialog(false) end,
    })
    cancel:SetPoint("BOTTOMLEFT", d, "BOTTOM", 4, 14)
    d.cancel = cancel

    -- Chrome shown/hidden together whenever the dialog opens/closes,
    -- regardless of gradient support -- same idea as `panelChrome` in
    -- Build() below.
    d.chrome = { d.title, preview, previewFill, accept, cancel }

    -- Hiding `d` itself does NOT hide its children on this client (see the
    -- "Visibility helpers" section above) -- every child must be hidden by
    -- hand whenever the dialog closes, regardless of how it closed
    -- (CloseColorDialog, or anything else that ends up calling d:Hide()),
    -- same pattern as the main options panel's own OnHide script in
    -- Build() below.
    d:SetScript("OnHide", function()
        SetListShown(d.chrome, false)
        d.square:Hide()
        d.strip:Hide()
        d.marker:Hide()
        d.hueThumb:Hide()
        SetListShown(d.squareLayers, false)
        SetListShown(d.hueSegments, false)
        SetShown(d.sliders.r, false)
        SetShown(d.sliders.g, false)
        SetShown(d.sliders.b, false)
        SetShown(d.sliders.a, false)
    end)

    return d
end

-- Closes the shared dialog. accept=false restores the colour the owning
-- control had when it was opened, so Cancel undoes every live preview;
-- accept=true keeps whatever is currently previewed.
CloseColorDialog = function(accept)
    if not colorDialog or not colorDialog:IsShown() then return end

    local finish = colorDialog.onFinish
    local start = colorDialog.start
    local current = colorDialog.current

    colorDialog.onFinish, colorDialog.onPreview = nil, nil
    colorDialog.start, colorDialog.current = nil, nil
    colorDialog:Hide()

    if type(finish) == "function" then
        if accept then finish(current) else finish(start) end
    end
end

-- Small swatch button + label, in the same shape as CreateCheckbox: the
-- caller passes a value ({r,g,b,a}) and an onChange, and owns the state.
-- Clicking the swatch opens the shared dialog above.
local function CreateColorPicker(parent, options)
    options = options or {}
    local size = options.size or 16
    local control = { uuiParts = {} }
    local parts = control.uuiParts

    local swatch = CreateFrame("Button", options.name, parent)
    swatch:SetWidth(size)
    swatch:SetHeight(size)
    pcall(swatch.EnableMouse, swatch, true)
    CreateBackdrop(swatch, {})
    control.swatch = swatch
    table.insert(parts, swatch)

    local preview = swatch:CreateTexture(nil, "ARTWORK")
    preview:SetTexture(THEME.plain)
    preview:SetPoint("TOPLEFT", swatch, "TOPLEFT", 2, -2)
    preview:SetPoint("BOTTOMRIGHT", swatch, "BOTTOMRIGHT", -2, 2)
    control.preview = preview

    control.value = { r = 1, g = 1, b = 1, a = 1 }
    control.hasAlpha = options.hasAlpha and true or false
    control.disabled = options.disabled and true or false

    local function ApplyPreview()
        SetRegionColor(preview, { control.value.r, control.value.g, control.value.b, control.value.a })
    end

    local function Publish(color, notify)
        control.value = {
            r = tonumber(color.r) or 1,
            g = tonumber(color.g) or 1,
            b = tonumber(color.b) or 1,
            a = tonumber(color.a) or 1,
        }
        ApplyPreview()
        if notify and type(options.onChange) == "function" then
            options.onChange(control.value)
        end
    end

    control.SetValue = function(value)
        if type(value) == "table" then
            control.value = {
                r = tonumber(value.r) or 1,
                g = tonumber(value.g) or 1,
                b = tonumber(value.b) or 1,
                a = tonumber(value.a) or 1,
            }
        end
        ApplyPreview()
    end

    control.SetPoint = function(self, point, relative, relativePoint, x, y)
        swatch:ClearAllPoints()
        swatch:SetPoint(point, relative, relativePoint, x, y)
    end

    swatch:SetScript("OnClick", function()
        if control.disabled then return end
        -- Whatever the dialog was previously editing is finished first
        -- (as a cancel), so its callbacks can never outlive the control
        -- that installed them.
        CloseColorDialog(false)

        local d = EnsureColorDialog()
        local start = control.value

        d.start = { r = start.r, g = start.g, b = start.b, a = start.a }
        d.current = { r = start.r, g = start.g, b = start.b, a = start.a }
        d.onPreview = function(color) Publish(color, true) end
        d.onFinish = function(color) Publish(color, true) end

        if d.title then d.title:SetText(options.text or "Select Color") end

        -- HSV is seeded from the incoming colour so the marker starts
        -- where the current colour actually is.
        d.AdoptRGB()

        local channels = { "r", "g", "b" }
        local i
        for i = 1, table.getn(channels) do
            local key = channels[i]
            d.sliders[key].SetValue(math.floor((start[key] or 0) * 255 + 0.5))
        end
        SetShown(d.sliders.r, true)
        SetShown(d.sliders.g, true)
        SetShown(d.sliders.b, true)

        -- The opacity slider only appears when the caller asked for it.
        if control.hasAlpha then
            d.sliders.a.SetValue(math.floor((start.a or 1) * 255 + 0.5))
            SetShown(d.sliders.a, true)
        else
            SetShown(d.sliders.a, false)
        end

        -- Every region is shown by hand -- this client does not propagate
        -- parent visibility to children (see the "Visibility helpers"
        -- section above).
        if d.gradients then
            d.square:Show()
            d.strip:Show()
            d.marker:Show()
            d.hueThumb:Show()
            SetListShown(d.squareLayers, true)
            SetListShown(d.hueSegments, true)
        else
            d.square:Hide()
            d.strip:Hide()
            d.marker:Hide()
            d.hueThumb:Hide()
            SetListShown(d.squareLayers, false)
            SetListShown(d.hueSegments, false)
        end

        SetListShown(d.chrome, true)
        d.UpdatePreview()
        d:ClearAllPoints()
        d:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        d:Show()
    end)

    control.SetValue(options.value)
    return control
end

-- ===========================================================================
-- AceConfig bridge
-- ===========================================================================
-- lib.* (not plain locals) so this state survives the file body re-running
-- on a minor-version bump: LibStub returns the SAME lib table across an
-- upgrade (existing hard refs stay valid) but re-executes this whole file
-- on top of it. An unconditional `= {}` here would wipe out every other
-- embedding addon's already-registered categories the moment any one
-- addon ships a newer minor -- `or` keeps whatever's already there.
lib.registry = lib.registry or {}     -- [appName][name] = configtable
lib.categories = lib.categories or {} -- ordered: { appName, name, table }
lib.expandState = lib.expandState or {} -- [pageId] = true/false, tree expand/collapse
lib.tabState = lib.tabState or {}     -- [groupId] = selected child key, childGroups="tab" groups

-- Reconstructs the AceConfig `info` table (see AceConfigDialog-3.0's
-- GetOptionsMemberValue): positional info[1..n] = path of arg keys, plus the
-- named fields. get/set/values/name/desc/order/hidden/disabled may be function
-- refs `fn(info, ...)` or method-name strings resolved on the nearest handler.
local function BuildInfo(root, appName, path, handler, arg, option)
    local info = {}
    local i
    for i = 1, table.getn(path) do
        info[i] = path[i]
    end
    info.n = table.getn(path)
    info[0] = appName
    info.appName = appName
    info.arg = arg
    info.handler = handler
    info.option = option
    info.type = option and option.type
    info.options = root
    info.uiType = "dialog"
    info.uiName = MAJOR
    return info
end

-- Members where a string value is the literal display text, not a method name
-- to resolve on the handler (matches AceConfigDialog's stringIsLiteral).
local stringIsLiteral = {
    name = true,
    desc = true,
    icon = true,
    usage = true,
    width = true,
    image = true,
    fontSize = true,
}

-- Members that are never a function or method name.
local allIsLiteral = {
    type = true,
    descStyle = true,
    imageWidth = true,
    imageHeight = true,
}

-- Members a leaf INHERITS from its enclosing groups when it doesn't define one
-- itself. Matches AceConfigDialog-3.0's own `isInherited` set exactly.
--
-- This is what lets an options table put ONE get/set on a group and have every
-- control under it work, with the entry's own KEY naming the DB field:
--
--   general = {
--       type = "group",
--       get = function(info) return E.db.general[ info[getn(info)] ] end,
--       set = function(info, value) E.db.general[ info[getn(info)] ] = value end,
--       args = { fontSize = { type = "range", ... } },   -- no get/set needed
--   }
--
-- `info[getn(info)]` is the leaf's key because the member is invoked with the
-- LEAF's info table even when it was found on an ancestor -- see ResolveMember.
-- That coupling is the point: a mistyped entry name becomes a visibly wrong
-- control instead of a silently dead closure.
--
-- `handler` is NOT listed here: it already inherits separately, carried down as
-- `opt.handler or handler` while the tree is walked.
local isInherited = {
    get = true,
    set = true,
    func = true,
    confirm = true,
    validate = true,
    disabled = true,
    hidden = true,
}

-- Returns the effective value of `memberName` for a leaf: its own if it has one,
-- otherwise the DEEPEST enclosing group that defines it (nearest ancestor wins,
-- same precedence as AceConfigDialog's GetOptionsMemberValue).
--
-- The leaf's own value is checked FIRST, so a leaf can always override its
-- group, and a path that cannot be walked (a key not present under `args`)
-- degrades to exactly the old behaviour instead of guessing.
local function InheritedMember(memberName, root, path, option)
    if option and option[memberName] ~= nil then
        return option[memberName]
    end
    if not isInherited[memberName] or type(root) ~= "table" then
        return nil
    end

    local member = nil
    if root[memberName] ~= nil then member = root[memberName] end

    -- Stops BEFORE the last path element: that one is the leaf, already handled.
    local group = root
    local i
    for i = 1, table.getn(path) - 1 do
        local args = group.args
        group = args and args[path[i]]
        if type(group) ~= "table" then break end
        if group[memberName] ~= nil then member = group[memberName] end
    end
    return member
end

-- Resolves an option member. A function is always called with the info table;
-- a string is a method name on the handler for most members, but a literal for
-- the stringIsLiteral members (name/desc/...). Extra args are forwarded (set is
-- called with the value). Anything else is returned as-is.
--
-- Inheritable members (see isInherited) fall back to the enclosing groups, and
-- are then called with the LEAF's info table regardless of where they were
-- found -- that is what makes the `info[getn(info)]` idiom resolve to the leaf's
-- own key.
local function ResolveMember(memberName, root, appName, path, handler, arg, option, a1, a2)
    local member = InheritedMember(memberName, root, path, option)
    if member == nil then return nil end

    local isFunc = (type(member) == "function")
    local isMethod = (not stringIsLiteral[memberName]) and (type(member) == "string")
    if not ((not allIsLiteral[memberName]) and (isFunc or isMethod)) then
        return member
    end

    local info = BuildInfo(root, appName, path, handler, arg, option)
    if isFunc then
        return member(info, a1, a2)
    end
    if handler and handler[member] then
        return handler[member](handler, info, a1, a2)
    end
    return nil
end

local function NewPath(path, key)
    local newPath = {}
    local i
    for i = 1, table.getn(path) do newPath[i] = path[i] end
    table.insert(newPath, key)
    return newPath
end

-- Matches real AceConfigDialog-3.0's own field-priority order exactly
-- (AceConfigDialog-3.0.lua: `pickfirstset(v.dialogInline, v.guiInline,
-- v.inline, false)`). Earlier code here only checked `opt.inline` -- real
-- ElvUI's own option tables (e.g. source/ElvUI-vanilla/ElvUI_Config/
-- Maps.lua's `generalGroup`) use `guiInline`, which that older check never
-- saw, so those groups rendered as if not inline at all.
local function EffectiveInline(opt)
    if opt.dialogInline ~= nil then return opt.dialogInline end
    if opt.guiInline ~= nil then return opt.guiInline end
    if opt.inline ~= nil then return opt.inline end
    return false
end

-- "select" (a dropdown selector instead of a tab strip) isn't implemented
-- as its own widget -- falls back to "tree" (normal sidebar rows), which
-- is a safe, working default, just not a literal visual match.
local function EffectiveChildGroups(opt)
    if opt.childGroups == "tab" then return "tab" end
    return "tree"
end

-- Default 100 when an entry has no `order`, matching AceConfigDialog-3.0's own
-- `v.order or 100`. This is not cosmetic: real ElvUI's tables rely on an
-- unordered entry sinking BELOW the explicitly-ordered ones, and a 0 default
-- (what this used to return) floated them to the top instead.
local function EvalOrder(root, appName, opt, arg, path, handler)
    local order = ResolveMember("order", root, appName, path, handler, arg, opt)
    return tonumber(order) or 100
end

-- Display name, uppercased, used ONLY as a sort tie-break.
local function SortName(root, appName, args, key, path, handler)
    local name = ResolveMember("name", root, appName, NewPath(path, key), handler, key, args[key])
    if type(name) ~= "string" then return "" end
    return string.upper(name)
end

-- Orders an args table's keys the way AceConfigDialog-3.0's own compareOptions
-- does. Three rules, none of which a plain `orderA < orderB` gets right:
--
--   1. EQUAL orders tie-break on DISPLAY NAME, not on table order. This one
--      matters most, because real ElvUI gives nearly every top-level section
--      `order = 1` and lets the name decide -- so without it, "inherit real
--      ElvUI's ordering" produces no ordering at all.
--   2. NEGATIVE orders sort AFTER every positive one (they count from the end).
--      That is how `profiles = -10` lands at the bottom of the list rather than
--      the top.
--   3. An entry with no `order` defaults to 100 (see EvalOrder).
--
-- The final `tostring(a) < tostring(b)` key comparison goes beyond AceConfig on
-- purpose: `pairs()` yields hash order and `table.sort` is not stable, so
-- entries that tie on BOTH order and name would otherwise be arranged
-- differently from one session to the next. This project's own config had a
-- block of unordered chat toggles doing exactly that.
local function SortOptionKeys(keys, args, root, appName, path, handler)
    table.sort(keys, function(a, b)
        local oa = EvalOrder(root, appName, args[a], a, path, handler)
        local ob = EvalOrder(root, appName, args[b], b, path, handler)
        if oa == ob then
            local na = SortName(root, appName, args, a, path, handler)
            local nb = SortName(root, appName, args, b, path, handler)
            if na ~= nb then return na < nb end
            return tostring(a) < tostring(b)
        end
        if oa < 0 then
            if ob > 0 then return false end
        elseif ob < 0 then
            return true
        end
        return oa < ob
    end)
end

local function IsVisibleGroup(opt, root, appName, path, handler, arg)
    local hidden = ResolveMember("hidden", root, appName, path, handler, arg, opt)
    return not hidden
end

-- Stable string identity for a tree page, since the page tables themselves are
-- rebuilt fresh on every BuildVisibleRows() call (see the note on activePageId
-- below for why nothing may compare pages by table reference).
local function BuildPageId(appName, catName, path)
    local parts = { appName, catName }
    local i
    for i = 1, table.getn(path) do
        table.insert(parts, tostring(path[i]))
    end
    return table.concat(parts, "\1")
end

-- ===========================================================================
-- Window
-- ===========================================================================
local sidebar, content, contentScroll
-- The right-gutter scrollbar (MINOR 11). Replaced the old
-- `contentUpBtn`/`contentDownBtn` footer pair -- the bar carries its own
-- arrow buttons at either end now.
local contentScrollBar
-- The sidebar gets its own, since its rows are hand-placed in a plain
-- Frame that nothing scrolls or clips on its own.
local sidebarScrollBar
local sidebarOffset = 0
-- Forward-declared: ScrollContentBy (defined before it) routes through it,
-- and the scrollbar's own onScroll callback -- created inside Build -- calls
-- it too.
local SetContentScroll
local contentOffset = 0
local contentMaxOffset = 0

-- Assignment of the getter forward-declared at the top of the file, so
-- CreateDropdown (defined long before this point) can read the live
-- scroll amount without this whole block having to move up.
GetContentScrollOffset = function()
    return contentOffset or 0
end
local panelChrome = {}
local sidebarRows = {}
local contentWidgets = {}
-- A string id, NOT a page table reference: BuildVisibleRows() rebuilds fresh
-- page tables on every call (tree structure is recomputed from the live
-- options tables each render), so comparing "is this the active page" by `==`
-- on a table would almost never match past the first render -- the same bug
-- shape as the GameMenu anchor-drift fix, avoided here by never doing it.
local activePageId
local yCursor
-- The exact page table last passed to RenderContent -- kept so a tab
-- button's OnClick can re-render the SAME page in place (new tab
-- selection, same sidebar navigation) without needing to rebuild or
-- re-look-up a page from BuildVisibleRows() (whose page tables are fresh
-- every call, see the activePageId note above -- same reason this can't
-- just be "the page with id == activePageId").
local currentPage

local SelectPage -- forward declaration; assigned after RenderSidebar

local function AddWidget(w)
    table.insert(contentWidgets, w)
end

local function ClearContent()
    SetListShown(contentWidgets, false)
    contentWidgets = {}
end

-- Renders one leaf option; advances yCursor and registers its regions.
local function RenderLeaf(opt, arg, path, handler, root, appName)
    local hidden = ResolveMember("hidden", root, appName, path, handler, arg, opt)
    if hidden then return end

    local name = ResolveMember("name", root, appName, path, handler, arg, opt)
    if name == nil then name = arg end
    name = tostring(name)
    local desc = ResolveMember("desc", root, appName, path, handler, arg, opt)
    local disabled = ResolveMember("disabled", root, appName, path, handler, arg, opt)
    local t = opt.type

    local function AddNameLabel()
        local label = CreateLabel(content, {
            color = disabled and THEME.textDim or THEME.text,
            inherits = "GameFontNormalSmall",
            justify = "LEFT",
            width = LABEL_WIDTH,
            height = ROW_HEIGHT,
        })
        if label then
            label:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -yCursor)
            label:SetText(name)
        end
        AddWidget(label)
        return label
    end

    if t == "header" then
        local title = CreateLabel(content, {
            color = THEME.accent,
            inherits = "GameFontNormal",
            justify = "LEFT",
            width = CONTENT_WIDTH,
            height = 18,
        })
        if title then
            title:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -yCursor)
            title:SetText(name)
        end
        AddWidget(title)
        local rule = CreateRule(content, { color = THEME.hover })
        rule:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(yCursor + 20))
        rule:SetWidth(CONTENT_WIDTH)
        AddWidget(rule)
        yCursor = yCursor + HEADER_H

    elseif t == "description" then
        local label = CreateLabel(content, {
            color = THEME.textDim,
            inherits = "GameFontNormalSmall",
            justify = "LEFT",
            width = CONTENT_WIDTH,
            height = DESC_H,
            nonSpaceWrap = true,
        })
        if label then
            label:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -yCursor)
            label:SetText(name)
        end
        AddWidget(label)
        yCursor = yCursor + DESC_H + ROW_GAP

    elseif t == "toggle" then
        local current = ResolveMember("get", root, appName, path, handler, arg, opt)
        AddNameLabel()
        local cb = CreateCheckbox(content, {
            value = current,
            disabled = disabled,
            onChange = function(v)
                ResolveMember("set", root, appName, path, handler, arg, opt, v)
            end,
        })
        cb:SetPoint("TOPLEFT", content, "TOPLEFT", LABEL_WIDTH + CONTROL_GAP, -yCursor + (ROW_HEIGHT - 16) / 2)
        if desc then AttachTooltip(cb.box, desc) end
        AddWidget(cb)
        yCursor = yCursor + ROW_HEIGHT + ROW_GAP

    elseif t == "input" then
        local current = ResolveMember("get", root, appName, path, handler, arg, opt)
        local full = (opt.width == "full")

        if full then
            local label = CreateLabel(content, {
                color = THEME.text,
                inherits = "GameFontNormalSmall",
                justify = "LEFT",
                width = CONTENT_WIDTH,
                height = 16,
            })
            if label then
                label:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -yCursor)
                label:SetText(name)
            end
            AddWidget(label)
            yCursor = yCursor + 16

            local eb = CreateEditBox(content, {
                value = current,
                width = CONTENT_WIDTH,
                onChange = function(v)
                    ResolveMember("set", root, appName, path, handler, arg, opt, v)
                end,
            })
            eb:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -yCursor)
            if desc then AttachTooltip(eb.box, desc) end
            AddWidget(eb)
            yCursor = yCursor + ROW_HEIGHT + ROW_GAP
        else
            AddNameLabel()
            local eb = CreateEditBox(content, {
                value = current,
                width = CONTROL_WIDTH,
                onChange = function(v)
                    ResolveMember("set", root, appName, path, handler, arg, opt, v)
                end,
            })
            eb:SetPoint("TOPLEFT", content, "TOPLEFT", LABEL_WIDTH + CONTROL_GAP, -yCursor)
            if desc then AttachTooltip(eb.box, desc) end
            AddWidget(eb)
            yCursor = yCursor + ROW_HEIGHT + ROW_GAP
        end

    elseif t == "select" then
        local values = ResolveMember("values", root, appName, path, handler, arg, opt)
        local items = {}
        if type(values) == "table" then
            local k, v
            for k, v in pairs(values) do
                table.insert(items, { value = k, text = tostring(v) })
            end
            table.sort(items, function(a, b) return a.text < b.text end)
        end
        local current = ResolveMember("get", root, appName, path, handler, arg, opt)
        local full = (opt.width == "full")

        -- `dialogControl = "LSM30_Font"` / `"LSM30_Statusbar"` -- matches
        -- real ElvUI's/AceGUI's own actual field convention (a "select"
        -- type option table names a custom dialog control), so a real
        -- ElvUI option table ported verbatim would already carry the right
        -- hint. Resolves each item's LSM path ONCE here (not per-frame in
        -- CreateDropdown) and hands it to the dropdown as `previewPath`,
        -- which renders a live preview per row -- see CreateDropdown's own
        -- comment for the full "also doubles as a diagnostic" reasoning.
        local previewType = nil
        if opt.dialogControl == "LSM30_Font" then
            previewType = "font"
        elseif opt.dialogControl == "LSM30_Statusbar" then
            previewType = "statusbar"
        end
        if previewType then
            local mediaType = (previewType == "font") and "font" or "statusbar"
            local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
            if LSM then
                local j
                for j = 1, table.getn(items) do
                    items[j].previewPath = LSM:Fetch(mediaType, items[j].value)
                end
            end
        end

        if full then
            local label = CreateLabel(content, {
                color = THEME.text,
                inherits = "GameFontNormalSmall",
                justify = "LEFT",
                width = CONTENT_WIDTH,
                height = 16,
            })
            if label then
                label:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -yCursor)
                label:SetText(name)
            end
            AddWidget(label)
            yCursor = yCursor + 16

            local dd = CreateDropdown(content, {
                items = items,
                value = current,
                width = CONTENT_WIDTH,
                previewType = previewType,
                onChange = function(v)
                    ResolveMember("set", root, appName, path, handler, arg, opt, v)
                end,
            })
            dd:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -yCursor)
            if desc then AttachTooltip(dd.button, desc) end
            AddWidget(dd)
            yCursor = yCursor + 24 + ROW_GAP
        else
            AddNameLabel()
            local dd = CreateDropdown(content, {
                items = items,
                value = current,
                width = CONTROL_WIDTH,
                previewType = previewType,
                onChange = function(v)
                    ResolveMember("set", root, appName, path, handler, arg, opt, v)
                end,
            })
            dd:SetPoint("TOPLEFT", content, "TOPLEFT", LABEL_WIDTH + CONTROL_GAP, -yCursor)
            if desc then AttachTooltip(dd.button, desc) end
            AddWidget(dd)
            yCursor = yCursor + ROW_HEIGHT + ROW_GAP
        end

    elseif t == "range" then
        local current = ResolveMember("get", root, appName, path, handler, arg, opt)
        AddNameLabel()
        local sl = CreateSlider(content, {
            min = opt.min,
            max = opt.max,
            step = opt.step,
            value = current,
            width = CONTROL_WIDTH,
            onChange = function(v)
                ResolveMember("set", root, appName, path, handler, arg, opt, v)
            end,
        })
        -- BUG FIXED (MINOR 7): CreateSlider's own editable-value box floats
        -- ABOVE its track (see CreateSlider) -- anchoring the track's own
        -- TOPLEFT directly at `-yCursor` (the row's own nominal top) let
        -- that box poke `sl.topOffset` px further up, into whatever
        -- rendered in the PREVIOUS row. Offsetting the anchor
        -- down by `sl.topOffset` keeps the whole assembly inside this
        -- row's own allocated space instead.
        sl:SetPoint("TOPLEFT", content, "TOPLEFT", LABEL_WIDTH + CONTROL_GAP, -(yCursor + (sl.topOffset or 0)))
        if desc then AttachTooltip(sl.track, desc) end
        AddWidget(sl)
        yCursor = yCursor + SLIDER_H + ROW_GAP

    elseif t == "color" then
        -- Invoked manually rather than through ResolveMember, because real
        -- AceConfig's "color" type has a wider calling convention than every
        -- other widget: get(info) returns r,g,b,a as MULTIPLE VALUES (not a
        -- table) and set(info, r,g,b,a) takes four extra args, while
        -- ResolveMember only forwards two.
        --
        -- The MEMBER still comes from InheritedMember, so a group-level
        -- get/set covers colour swatches too. Resolving `opt.get` directly
        -- here (as this did originally) would have left colour the one widget
        -- type that silently ignores its group's get/set -- a trap for any
        -- options table built on group-level inheritance.
        local getter = InheritedMember("get", root, path, opt)
        local setter = InheritedMember("set", root, path, opt)

        local info = BuildInfo(root, appName, path, handler, arg, opt)
        local r, g, b, a = 1, 1, 1, 1
        if type(getter) == "function" then
            r, g, b, a = getter(info)
        elseif type(getter) == "string" and handler and handler[getter] then
            r, g, b, a = handler[getter](handler, info)
        end
        if a == nil then a = 1 end

        AddNameLabel()
        local cp = CreateColorPicker(content, {
            value = { r = r, g = g, b = b, a = a },
            hasAlpha = opt.hasAlpha,
            disabled = disabled,
            text = name,
            onChange = function(color)
                local setInfo = BuildInfo(root, appName, path, handler, arg, opt)
                if type(setter) == "function" then
                    setter(setInfo, color.r, color.g, color.b, color.a)
                elseif type(setter) == "string" and handler and handler[setter] then
                    handler[setter](handler, setInfo, color.r, color.g, color.b, color.a)
                end
            end,
        })
        cp:SetPoint("TOPLEFT", content, "TOPLEFT", LABEL_WIDTH + CONTROL_GAP, -yCursor + (ROW_HEIGHT - 16) / 2)
        if desc then AttachTooltip(cp.swatch, desc) end
        AddWidget(cp)
        yCursor = yCursor + ROW_HEIGHT + ROW_GAP

    elseif t == "execute" then
        local btn = CreateButton(content, {
            text = name,
            width = CONTENT_WIDTH,
            height = 24,
            onClick = function()
                -- Presence checked through InheritedMember, not `opt.func`:
                -- `func` is inheritable, so a button relying on its group's
                -- func would otherwise fall through to the `set` branch and
                -- write `true` into a DB field named after the button.
                if InheritedMember("func", root, path, opt) ~= nil then
                    ResolveMember("func", root, appName, path, handler, arg, opt)
                else
                    ResolveMember("set", root, appName, path, handler, arg, opt, true)
                end
            end,
        })
        btn:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -yCursor)
        if desc then AttachTooltip(btn, desc) end
        AddWidget(btn)
        yCursor = yCursor + 24 + ROW_GAP
    end
end

local TAB_HEIGHT = ROW_HEIGHT
local TAB_GAP = 4
local TAB_MAX_WIDTH = 140

-- Horizontal breathing room around a tab's own label, and the smallest a
-- tab is ever drawn regardless of how short its name is.
local TAB_PADDING = 18
local TAB_MIN_WIDTH = 40

-- Measures a string in the same font the tab buttons use (CreateButton's
-- label inherits GameFontNormal), via a single throwaway FontString kept
-- around for the life of the session.
--
-- GetStringWidth is documented on Unreal Azeroth
-- (UnrealAzeroth_LuaAPI/en/widgets/FontString.md) and returns the
-- UNWRAPPED natural width, which is exactly what tab packing needs.
-- Falls back to a crude per-character estimate if it ever returns
-- nothing usable -- a slightly-off tab width is a cosmetic problem, a nil
-- here would be a layout crash.
local measureFontString
local function MeasureTextWidth(text)
    text = text or ""
    if not measureFontString then
        local host = panel or UIParent
        local ok, fs = pcall(host.CreateFontString, host, nil, "ARTWORK", "GameFontNormal")
        if ok and fs then
            -- Anchored, alpha'd to zero AND hidden. It exists only to be
            -- measured and must never draw -- and an UNANCHORED region has
            -- no defined place to not-draw in, which on this client is not
            -- a risk worth taking. Measurement itself is unaffected:
            -- GetStringWidth reports the natural, unwrapped text width
            -- regardless of visibility or placement.
            pcall(fs.SetPoint, fs, "TOPLEFT", host, "TOPLEFT", 0, 0)
            pcall(fs.SetAlpha, fs, 0)
            pcall(fs.Hide, fs)
            measureFontString = fs
        end
    end
    if measureFontString then
        pcall(measureFontString.SetText, measureFontString, text)
        local ok, width = pcall(measureFontString.GetStringWidth, measureFontString)
        if ok and type(width) == "number" and width > 0 then return width end
    end
    return string.len(text) * 7
end

-- Forward declarations: RenderGroup and RenderTabStrip are mutually
-- recursive (a childGroups="tab" group's selected tab is itself rendered
-- via RenderGroup, which may itself be another childGroups="tab" group --
-- this is exactly how real ElvUI's Maps.lua nests: Maps -> [World Map,
-- Minimap] tabs, then Minimap's OWN args are themselves a second
-- childGroups="tab" layer -> [General, Location Text, Reset Zoom, Icons]).
-- RenderContent is ALSO forward-declared here even though it has no direct
-- recursive relationship with the other two -- a tab button's OnClick
-- closure (built inside RenderTabStrip, see below) calls it, and that
-- closure is compiled before `local function RenderContent` would
-- otherwise be in scope; without this, the closure would resolve
-- `RenderContent` as an unset GLOBAL instead of the local, and clicking
-- any tab would error.
local RenderGroup
local RenderTabStrip
local RenderContent

-- Forward-declared so a TAB CLICK can recompute the scroll extent, the
-- same way navigating to a page does -- see RenderTabStrip's onClick.
-- Assigned further down, next to the rest of the content-scroll state.
local FinishContentScroll

-- inInlineContext: true once we're already rendering inside an inline
-- group's content. Real AceConfigDialog-3.0's documented Tree-group rule
-- (see the "Group Types" comment near the top of the real
-- AceConfigDialog-3.0.lua): "When a group is displayed inline, all
-- descendants will also be inline members of the group" -- i.e. inline-ness
-- is inherited by every descendant regardless of their OWN inline field,
-- not just checked group-by-group. A nested group can only become its own
-- sidebar tree page while no inline ancestor is already forcing it inline.
--
-- catName threads through purely so tab-state (lib.tabState, see
-- RenderTabStrip) can be keyed the same way pages already are
-- (BuildPageId(appName, catName, path)) -- has no bearing on inline/tree
-- logic itself.
RenderGroup = function(group, path, handler, root, appName, inInlineContext, catName)
    local args = group.args
    if type(args) ~= "table" then return end

    local keys = {}
    local k
    for k in pairs(args) do
        table.insert(keys, k)
    end
    SortOptionKeys(keys, args, root, appName, path, handler)

    -- Populated when this group itself is childGroups="tab" -- its non-
    -- inline group-type children are collected here instead of being
    -- rendered inline OR left for the sidebar tree, then rendered as one
    -- tab strip block after the rest of this group's own content (leaf
    -- args + inline children), matching real AceConfigDialog's own
    -- "FeedOptions then add the Group Control" ordering.
    local isTabGroup = (EffectiveChildGroups(group) == "tab") and not inInlineContext
    local tabChildren = {}

    local i
    for i = 1, table.getn(keys) do
        local key = keys[i]
        local opt = args[key]
        if type(opt) == "table" then
            local newPath = NewPath(path, key)
            local newHandler = opt.handler or handler
            if opt.type == "group" then
                if inInlineContext or EffectiveInline(opt) then
                    -- Rendered as a section header on THIS page, then its
                    -- children (unchanged from before).
                    local title = CreateLabel(content, {
                        color = THEME.accent,
                        inherits = "GameFontNormal",
                        justify = "LEFT",
                        width = CONTENT_WIDTH,
                        height = 18,
                    })
                    if title then
                        title:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -yCursor)
                        title:SetText(ResolveMember("name", root, appName, newPath, newHandler, key, opt) or key)
                    end
                    AddWidget(title)
                    local rule = CreateRule(content, { color = THEME.hover })
                    rule:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(yCursor + 20))
                    rule:SetWidth(CONTENT_WIDTH)
                    AddWidget(rule)
                    yCursor = yCursor + HEADER_H

                    RenderGroup(opt, newPath, newHandler, root, appName, true, catName)
                elseif isTabGroup and IsVisibleGroup(opt, root, appName, newPath, newHandler, key) then
                    table.insert(tabChildren, {
                        key = key,
                        opt = opt,
                        path = newPath,
                        handler = newHandler,
                        displayName = tostring(ResolveMember("name", root, appName, newPath, newHandler, key, opt) or key),
                    })
                end
                -- Otherwise: its own sidebar tree page (see
                -- CollectChildPages/BuildVisibleRows) -- not rendered here.
            else
                RenderLeaf(opt, key, newPath, newHandler, root, appName)
            end
        end
    end

    if isTabGroup and table.getn(tabChildren) > 0 then
        RenderTabStrip(group, tabChildren, path, root, appName, catName)
    end
end

-- Renders the tab-button row for a childGroups="tab" group, then the
-- currently selected tab's own content (recursing back into RenderGroup --
-- itself possibly ANOTHER childGroups="tab" group, see the note above).
-- Selection persists in lib.tabState, keyed by this GROUP's own path (not
-- the child's) so it round-trips correctly across re-renders/navigation.
RenderTabStrip = function(group, tabChildren, path, root, appName, catName)
    local numTabs = table.getn(tabChildren)
    local groupId = BuildPageId(appName, catName, path)

    local selectedKey = lib.tabState[groupId]
    local selectedTab
    local i
    for i = 1, numTabs do
        if tabChildren[i].key == selectedKey then selectedTab = tabChildren[i] end
    end
    if not selectedTab then
        selectedTab = tabChildren[1]
        lib.tabState[groupId] = selectedTab.key
    end

    -- MULTI-ROW, TEXT-MEASURED TAB LAYOUT.
    --
    -- This used to divide CONTENT_WIDTH evenly by the tab count and cram
    -- every tab onto ONE row. With a handful of tabs that is fine; with
    -- 12 (UnitFrames' per-unit General/Colors/Health/Power/Name/Portrait/
    -- icons/auras set) each tab got ~37px and the labels were cut down to
    -- one to three characters, forcing a click through every tab just to
    -- tell which one was which.
    --
    -- Now every tab is measured at its FULL label width and rows are
    -- filled greedily, wrapping to a new row when the next tab no longer
    -- fits -- so a label is never truncated, however many tabs there are.
    -- Each row is then JUSTIFIED: its leftover space is shared equally
    -- between that row's tabs so the row ends flush with the content
    -- width, with a per-tab TAB_MAX_WIDTH ceiling that stops a row of two
    -- short tabs from being stretched into two enormous slabs.
    local widths = {}
    for i = 1, numTabs do
        local w = MeasureTextWidth(tabChildren[i].displayName) + TAB_PADDING
        if w < TAB_MIN_WIDTH then w = TAB_MIN_WIDTH end
        if w > CONTENT_WIDTH then w = CONTENT_WIDTH end
        widths[i] = w
    end

    -- Greedy row packing. `used` is the sum of the row's tab widths, gaps
    -- excluded; a row always keeps at least one tab even if that single
    -- tab is wider than the content area (clamped above, so it can't be).
    local rows = {}
    local rowFirst = 1
    local used = 0
    for i = 1, numTabs do
        local count = i - rowFirst + 1
        local needed = used + widths[i] + (count - 1) * TAB_GAP
        if count > 1 and needed > CONTENT_WIDTH then
            table.insert(rows, { first = rowFirst, last = i - 1, used = used })
            rowFirst = i
            used = widths[i]
        else
            used = used + widths[i]
        end
    end
    table.insert(rows, { first = rowFirst, last = numTabs, used = used })

    -- Justify each row: spread the slack across its tabs, capped so no
    -- single tab grows past TAB_MAX_WIDTH. The remainder from the integer
    -- division goes to the row's last tab, so the row's right edge lands
    -- exactly where it should instead of drifting a pixel or two.
    local numRows = table.getn(rows)
    for i = 1, numRows do
        local row = rows[i]
        local count = row.last - row.first + 1
        local slack = CONTENT_WIDTH - row.used - (count - 1) * TAB_GAP
        if slack > 0 then
            local extra = math.floor(slack / count)
            local j
            local given = 0
            for j = row.first, row.last do
                local room = TAB_MAX_WIDTH - widths[j]
                if room < 0 then room = 0 end
                local add = extra
                if add > room then add = room end
                widths[j] = widths[j] + add
                given = given + add
            end
            -- Whatever the per-tab cap left unused goes to the last tab,
            -- still respecting its own ceiling.
            local leftover = slack - given
            if leftover > 0 then
                local room = TAB_MAX_WIDTH - widths[row.last]
                if room < 0 then room = 0 end
                if leftover > room then leftover = room end
                widths[row.last] = widths[row.last] + leftover
            end
        end
    end

    local rowOfTab = {}
    for i = 1, numRows do
        local j
        for j = rows[i].first, rows[i].last do
            rowOfTab[j] = i
        end
    end

    local tabX = 0
    local currentRow = 1
    for i = 1, numTabs do
        if rowOfTab[i] ~= currentRow then
            currentRow = rowOfTab[i]
            tabX = 0
        end
        local tabWidth = widths[i]
        local tabY = yCursor + (currentRow - 1) * (TAB_HEIGHT + TAB_GAP)
        local t = tabChildren[i]
        local isSelected = (t.key == selectedTab.key)
        -- background/border/textColor passed straight into CreateButton
        -- (rather than SetBackgroundColor/SetBorderColor afterward) so the
        -- OnEnter/OnLeave hover handlers -- which revert to whatever
        -- `options.border` was at CREATION time -- revert to the CORRECT
        -- (selected vs. not) color instead of always falling back to
        -- THEME.border. Safe to rely on creation-time-only styling here
        -- because tab buttons are fully recreated every render (unlike
        -- pooled sidebar rows), so there's no stale-selection risk.
        local btn = CreateButton(content, {
            text = t.displayName,
            width = tabWidth,
            height = TAB_HEIGHT,
            background = isSelected and THEME.accentFill or THEME.backdrop,
            border = isSelected and THEME.accent or THEME.border,
            textColor = isSelected and THEME.accent or THEME.text,
            onClick = function()
                lib.tabState[groupId] = t.key
                if currentPage then
                    RenderContent(currentPage)
                    -- BUG FIXED (MINOR 11): a tab click re-rendered the
                    -- content but never recomputed the SCROLL EXTENT --
                    -- only SelectPage (sidebar navigation) called
                    -- FinishContentScroll. So `content`'s height and
                    -- `contentMaxOffset` still described whichever tab
                    -- happened to be open when the page was entered: a
                    -- taller tab's options ran off the bottom of the
                    -- panel with the up/down scroll buttons still hidden
                    -- (contentMaxOffset stuck at 0), and the mouse wheel
                    -- had nothing to scroll either: the scrollbar stayed
                    -- hidden while the content visibly overflowed it.
                    --
                    -- Long-standing bug, but the multi-row tab strip
                    -- landing in this same version is what made it
                    -- routine: a wrapped strip is two or three rows tall
                    -- instead of one, so pages that used to just fit now
                    -- overflow.
                    if FinishContentScroll then FinishContentScroll() end
                end
            end,
        })
        btn:SetPoint("TOPLEFT", content, "TOPLEFT", tabX, -tabY)
        AddWidget(btn)
        tabX = tabX + tabWidth + TAB_GAP
    end
    yCursor = yCursor + numRows * TAB_HEIGHT + (numRows - 1) * TAB_GAP + ROW_GAP

    local rule = CreateRule(content, { color = THEME.hover })
    rule:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -yCursor)
    rule:SetWidth(CONTENT_WIDTH)
    AddWidget(rule)
    yCursor = yCursor + ROW_GAP

    RenderGroup(selectedTab.opt, selectedTab.path, selectedTab.handler, root, appName, false, catName)
end

-- page: { group, path, handler, root, appName, displayName, id, depth,
-- children, catName } -- see BuildRootPage/CollectChildPages below.
RenderContent = function(page)
    currentPage = page
    ClearContent()
    yCursor = 0

    local title = CreateLabel(content, {
        color = THEME.text,
        inherits = "GameFontNormal",
        justify = "LEFT",
        width = CONTENT_WIDTH,
        height = 22,
    })
    if title then
        title:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
        title:SetText(page.displayName)
    end
    AddWidget(title)

    local rule = CreateRule(content, { color = THEME.accent })
    rule:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -24)
    rule:SetWidth(CONTENT_WIDTH)
    AddWidget(rule)

    yCursor = 34

    RenderGroup(page.group, page.path, page.handler, page.root, page.appName, false, page.catName)
end

-- Walks group.args looking for non-inline "type=group" entries, which become
-- separate tree pages instead of inline content. Recurses THROUGH inline
-- groups (their args are flattened onto this same page, exactly like
-- RenderGroup does), so a non-inline group nested inside an inline group is
-- still found and still becomes its own page.
local function CollectChildPages(page)
    local children = {}

    -- inInlineContext: see the matching note on RenderGroup above -- must
    -- stay in lockstep with it, since this is what decides which groups
    -- RenderGroup will find already-consumed-as-inline vs. still needing
    -- their own page.
    local function Walk(group, path, handler, inInlineContext)
        local args = group.args
        if type(args) ~= "table" then return end

        local keys = {}
        local k
        for k in pairs(args) do
            table.insert(keys, k)
        end
        SortOptionKeys(keys, args, page.root, page.appName, path, handler)

        local isTabGroup = (EffectiveChildGroups(group) == "tab") and not inInlineContext

        local i
        for i = 1, table.getn(keys) do
            local key = keys[i]
            local opt = args[key]
            if type(opt) == "table" and opt.type == "group" then
                local newPath = NewPath(path, key)
                local newHandler = opt.handler or handler
                if inInlineContext or EffectiveInline(opt) then
                    Walk(opt, newPath, newHandler, true)
                elseif isTabGroup and IsVisibleGroup(opt, page.root, page.appName, newPath, newHandler, key) then
                    -- Tab child of a childGroups="tab" group: NOT its own
                    -- sidebar row (RenderGroup/RenderTabStrip renders it as
                    -- a tab on the SAME page instead) -- but still walk
                    -- INTO it, so a group nested deeper still surfaces as
                    -- a normal sidebar row. Real AceConfigDialog instead
                    -- gives a tab pane its own embedded nested-tree widget
                    -- for that case; LibConfig-1.0 has no such widget, so
                    -- this promotes it to the single global sidebar
                    -- (indented) instead -- browsable either way, just not
                    -- a pixel-perfect match of where it visually lives.
                    Walk(opt, newPath, newHandler, false)
                elseif IsVisibleGroup(opt, page.root, page.appName, newPath, newHandler, key) then
                    table.insert(children, {
                        id = BuildPageId(page.appName, page.catName, newPath),
                        appName = page.appName,
                        catName = page.catName,
                        group = opt,
                        path = newPath,
                        handler = newHandler,
                        root = page.root,
                        depth = page.depth + 1,
                        parent = page,
                        displayName = tostring(ResolveMember("name", page.root, page.appName, newPath, newHandler, key, opt) or key),
                        children = {},
                    })
                end
            end
        end
    end

    Walk(page.group, page.path, page.handler, false)
    return children
end

local function BuildRootPage(cat)
    return {
        id = BuildPageId(cat.appName, cat.name, {}),
        appName = cat.appName,
        catName = cat.name,
        group = cat.table,
        path = {},
        handler = cat.table.handler,
        root = cat.table,
        depth = 0,
        parent = nil,
        displayName = (cat.table.name ~= nil and tostring(cat.table.name)) or cat.name,
        children = {},
    }
end

-- Appends page, then (if it has children AND is expanded) its children,
-- depth-first, into rows -- the flattened list RenderSidebar draws.
local function AppendPageRows(rows, page)
    table.insert(rows, page)
    local children = CollectChildPages(page)
    page.children = children
    if table.getn(children) > 0 and lib.expandState[page.id] then
        local j
        for j = 1, table.getn(children) do
            AppendPageRows(rows, children[j])
        end
    end
end

local function BuildVisibleRows()
    local rows = {}
    local i
    for i = 1, table.getn(lib.categories) do
        local cat = lib.categories[i]
        if cat.table then
            AppendPageRows(rows, BuildRootPage(cat))
        end
    end
    return rows
end

local function StyleRow(row, text, selected)
    if row.label then
        row.label:SetText(text)
        pcall(row.label.SetTextColor, row.label, THEME.text[1], THEME.text[2], THEME.text[3], 1)
    end
    if selected then
        SetBackgroundColor(row, THEME.accentFill)
        SetBorderColor(row, THEME.accent)
        if row.label then
            pcall(row.label.SetTextColor, row.label, THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)
        end
    else
        SetBackgroundColor(row, THEME.backdrop)
        SetBorderColor(row, THEME.border)
    end
end

local function CreateSidebarRow(index)
    local row = CreateButton(sidebar, {
        name = "LibConfigRow" .. index,
        text = "",
        width = SIDEBAR_WIDTH - 12,
        height = ROW_HEIGHT,
    })
    if row.label then
        row.label:ClearAllPoints()
        row.label:SetPoint("LEFT", row, "LEFT", 10, BUTTON_LABEL_OFFSET_Y)
        pcall(row.label.SetWidth, row.label, SIDEBAR_WIDTH - 24)
        pcall(row.label.SetJustifyH, row.label, "LEFT")
    end

    -- Separate hit-target for expand/collapse only. The row itself always
    -- just navigates (see RenderSidebar) -- a combined toggle-on-select
    -- used to collapse a parent's children out from under you the moment
    -- you clicked back to it to look at its own page.
    local toggle = CreateButton(row, {
        name = "LibConfigRowToggle" .. index,
        text = "+",
        width = 16,
        height = ROW_HEIGHT - 4,
    })
    pcall(toggle.EnableMouse, toggle, true)
    local okLevel, level = pcall(row.GetFrameLevel, row)
    if okLevel and tonumber(level) then
        pcall(toggle.SetFrameLevel, toggle, tonumber(level) + 1)
    end
    row.toggle = toggle

    sidebarRows[index] = row
    return row
end

-- Pixels of left-indent per tree depth. Not pixel-perfect AceConfigDialog
-- parity -- just enough to read as nesting.
local SIDEBAR_INDENT = 14

-- Vertical padding above the first sidebar row and below the last.
local SIDEBAR_PAD = 8
local SIDEBAR_ROW_STRIDE = ROW_HEIGHT + 2

local function RenderSidebar()
    if not sidebar then return end
    local rows = BuildVisibleRows()
    local numRows = table.getn(rows)

    -- SCROLLING (MINOR 11). The sidebar is a plain Frame with hand-placed
    -- rows, not a ScrollFrame, so nothing clips it: once the tree is
    -- expanded far enough the rows simply ran off the bottom of the panel,
    -- with the overflow clearly visible past the sidebar's edge. Rows
    -- outside the visible band are therefore HIDDEN explicitly, exactly
    -- like the dropdown menu's own hand-placed rows.
    -- Scrolls in WHOLE ROWS, and only ever shows rows that fit ENTIRELY.
    -- The first attempt scrolled by pixels and hid a row once its TOP left
    -- the view, which let the last row hang past the sidebar's bottom edge
    -- by up to a row's height -- visible as rows drawn outside the panel.
    -- Sizing the band to exactly N items and quantising the offset avoids
    -- that, and also means a row is never sliced in half mid-scroll.
    local viewHeight = (sidebar:GetHeight() or 0) - SIDEBAR_PAD * 2
    if viewHeight < 0 then viewHeight = 0 end

    local maxVisible = math.floor(viewHeight / SIDEBAR_ROW_STRIDE)
    if maxVisible < 1 then maxVisible = 1 end

    local hiddenRows = numRows - maxVisible
    if hiddenRows < 0 then hiddenRows = 0 end
    local maxOffset = hiddenRows * SIDEBAR_ROW_STRIDE

    if sidebarOffset > maxOffset then sidebarOffset = maxOffset end
    if sidebarOffset < 0 then sidebarOffset = 0 end
    -- Snap to a whole row, so the band always starts on a row boundary.
    sidebarOffset = math.floor(sidebarOffset / SIDEBAR_ROW_STRIDE + 0.5) * SIDEBAR_ROW_STRIDE
    if sidebarOffset > maxOffset then sidebarOffset = maxOffset end

    local firstVisible = math.floor(sidebarOffset / SIDEBAR_ROW_STRIDE) + 1
    local lastVisible = firstVisible + maxVisible - 1
    local totalHeight = numRows * SIDEBAR_ROW_STRIDE

    -- The scrollbar lives INSIDE the sidebar's own width (there is only a
    -- MARGIN-wide gap to the content area, too narrow for it), so the rows
    -- give up that much width -- but only while it is actually shown.
    local scrollGutter = 0
    if maxOffset > 0 then scrollGutter = SCROLLBAR_GUTTER end

    if sidebarScrollBar then
        if maxOffset > 0 then
            sidebarScrollBar.SetShown(true)
            local ratio = 1
            if totalHeight > 0 then ratio = viewHeight / totalHeight end
            sidebarScrollBar.SetRange(maxOffset, ratio)
            sidebarScrollBar.SetValue(sidebarOffset)
        else
            sidebarScrollBar.SetShown(false)
        end
    end

    local i
    for i = 1, numRows do
        local page = rows[i]
        local row = sidebarRows[i] or CreateSidebarRow(i)
        local indent = page.depth * SIDEBAR_INDENT
        local hasChildren = table.getn(page.children) > 0

        -- Measured DOWN from the top of the row area (positive = down);
        -- the SetPoint below negates it back into WoW's convention.
        local rowTop = (i - 1) * SIDEBAR_ROW_STRIDE - sidebarOffset

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 6 + indent, -SIDEBAR_PAD - rowTop)
        pcall(row.SetWidth, row, SIDEBAR_WIDTH - 12 - indent - scrollGutter)

        local labelLeft = 10
        if row.toggle then
            if hasChildren then
                pcall(row.toggle.ClearAllPoints, row.toggle)
                pcall(row.toggle.SetPoint, row.toggle, "LEFT", row, "LEFT", 2, 0)
                row.toggle:Show()
                -- ElvUI's own PlusMinusButton sprite when the consumer
                -- registered artwork (see SetMedia), plain "+"/"-" text
                -- otherwise.
                SetButtonGlyph(row.toggle, lib.expandState[page.id] and "MINUS" or "PLUS")
                labelLeft = 20
            else
                row.toggle:Hide()
            end
            -- Rebound every render against the current `page` -- toggling
            -- only ever flips expandState and re-renders; it never selects,
            -- so it can never collapse (or navigate away from) whatever
            -- page you're currently looking at.
            row.toggle:SetScript("OnClick", function()
                lib.expandState[page.id] = not lib.expandState[page.id]
                RenderSidebar()
            end)
        end

        if row.label then
            pcall(row.label.ClearAllPoints, row.label)
            pcall(row.label.SetPoint, row.label, "LEFT", row, "LEFT", labelLeft, BUTTON_LABEL_OFFSET_Y)
            pcall(row.label.SetWidth, row.label, SIDEBAR_WIDTH - indent - labelLeft - 14 - scrollGutter)
        end

        -- Always just navigates. Never touches expandState -- see the note
        -- on row.toggle above for why a combined toggle-on-select bit us.
        row:SetScript("OnClick", function()
            SelectPage(page)
        end)

        local selected = (activePageId == page.id)
        StyleRow(row, page.displayName, selected)

        -- Outside the band of whole rows that fits: hide it outright
        -- rather than let it draw past the sidebar (nothing clips a plain
        -- Frame).
        if i < firstVisible or i > lastVisible then
            row:Hide()
            if row.label then row.label:Hide() end
            if row.toggle then row.toggle:Hide() end
        else
            row:Show()
            if row.label then row.label:Show() end
        end
    end
    for i = numRows + 1, table.getn(sidebarRows) do
        local row = sidebarRows[i]
        row:Hide()
        if row.label then row.label:Hide() end
        if row.toggle then row.toggle:Hide() end
    end
end

local function ScrollContentBy(delta)
    if not contentScroll then return end

    -- Close any open dropdown first (MINOR 11). Its popup menu is
    -- positioned once, at open time, against the scroll amount current at
    -- that moment (see AnchorMenuToButton in CreateDropdown) -- scrolling
    -- underneath an open menu would leave it stranded away from its own
    -- button. Closing is both simpler and better behaved than trying to
    -- keep a floating menu glued to a moving button.
    if activeDropdown then
        activeDropdown.SetOpen(false)
    end

    SetContentScroll(contentOffset + delta, true)
end

-- Applies an ABSOLUTE scroll offset. `fromWheel` distinguishes the two
-- callers: the mouse wheel / arrow buttons ask for a new offset and the
-- scrollbar thumb has to be moved to match, whereas the thumb ITSELF is
-- already where the user dragged it and must not be repositioned
-- mid-drag (see CreateScrollBar for why that breaks dragging on this
-- client).
SetContentScroll = function(offset, syncThumb)
    if not contentScroll then return end

    offset = tonumber(offset) or 0
    if offset < 0 then offset = 0 end
    if offset > contentMaxOffset then offset = contentMaxOffset end
    contentOffset = offset
    pcall(contentScroll.SetVerticalScroll, contentScroll, contentOffset)

    if syncThumb and contentScrollBar then
        contentScrollBar.SetValue(contentOffset)
    end
end

FinishContentScroll = function() -- forward-declared local, assigned here
    if not contentScroll or not content then return end
    content:SetHeight(yCursor + 8)
    pcall(contentScroll.UpdateScrollChildRect, contentScroll)
    pcall(contentScroll.SetVerticalScroll, contentScroll, 0)
    contentOffset = 0
    local ch = content:GetHeight() or 0
    local sh = contentScroll:GetHeight() or 0
    contentMaxOffset = ch - sh
    if contentMaxOffset < 0 then contentMaxOffset = 0 end

    if contentScrollBar then
        if contentMaxOffset > 0 then
            contentScrollBar.SetShown(true)
            -- Thumb length = how much of the content is visible, so its
            -- size tells you how long the page is at a glance.
            local ratio = 1
            if ch > 0 then ratio = sh / ch end
            contentScrollBar.SetRange(contentMaxOffset, ratio)
            contentScrollBar.SetValue(0)
        else
            contentScrollBar.SetShown(false)
        end
    end
end

SelectPage = function(page) -- forward-declared local, assigned here
    if not page then return end
    activePageId = page.id
    RenderContent(page)
    RenderSidebar()
    FinishContentScroll()
end

local function Build()
    panel = CreatePanel(UIParent, {
        name = "LibConfigPanel",
        width = PANEL_WIDTH,
        height = PANEL_HEIGHT,
    })
    panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    pcall(panel.SetFrameStrata, panel, "HIGH")

    if type(UISpecialFrames) == "table" then
        tinsert(UISpecialFrames, "LibConfigPanel")
    end
    panel:SetScript("OnHide", function()
        -- Force-commits a pending EditBox edit before the panel actually
        -- closes: typing a value then clicking Close (instead of pressing
        -- Enter first) would otherwise silently lose it. Hiding a
        -- frame doesn't reliably blur a focused EditBox child on this
        -- client the way it does on a real client (this project has
        -- already found the related "hiding a parent doesn't hide its
        -- children on UA" quirk elsewhere) -- OnEditFocusLost, which is
        -- what actually commits, never fired on its own. Explicitly
        -- clearing focus here (works regardless of which of the several
        -- ways the panel can close -- Close button, ESC via
        -- UISpecialFrames, etc. -- triggered this OnHide) fixes it
        -- directly rather than patching every individual close path.
        if focusedEditBox then
            pcall(focusedEditBox.ClearFocus, focusedEditBox)
            focusedEditBox = nil
        end
        SetListShown(panelChrome, false)
        if contentScrollBar then contentScrollBar.SetShown(false) end
        if sidebarScrollBar then sidebarScrollBar.SetShown(false) end
        ClearContent()
    end)

    panel.title = CreateLabel(panel, {
        color = THEME.text,
        inherits = "GameFontNormal",
        justify = "LEFT",
    })
    if panel.title then
        panel.title:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -14)
        panel.title:SetText("Options")
        table.insert(panelChrome, panel.title)
    end

    local headerRule = CreateRule(panel, { color = THEME.accent })
    headerRule:SetPoint("TOPLEFT", panel, "TOPLEFT", MARGIN, -(HEADER_HEIGHT - 12))
    headerRule:SetWidth(PANEL_WIDTH - MARGIN * 2)
    table.insert(panelChrome, headerRule)

    -- Drag-to-move the whole panel by its header strip. A Button, not
    -- `panel` itself (a plain
    -- Frame) -- this file's own already-proven drag recipe (the range
    -- slider thumb and color-picker marker above) needs a Button for
    -- reliable OnDragStart delivery, and the throwaway-StartMoving/
    -- StopMovingOrSizing-then-real-StartMoving sequence, on this client
    -- -- mirrored here rather than reinvented. Sized to the header strip
    -- only (title + the empty space beside it, down to `headerRule`),
    -- not the whole panel, so it never intercepts clicks on the sidebar/
    -- content/footer widgets below.
    local dragHandle = CreateFrame("Button", "LibConfigDragHandle", panel)
    dragHandle:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    dragHandle:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 0)
    dragHandle:SetHeight(HEADER_HEIGHT)
    pcall(dragHandle.EnableMouse, dragHandle, true)
    pcall(dragHandle.RegisterForDrag, dragHandle, "LeftButton")

    dragHandle:SetScript("OnDragStart", function()
        if not pcall(panel.SetMovable, panel, true) then return end
        if pcall(panel.StartMoving, panel) then
            pcall(panel.StopMovingOrSizing, panel)
        end
        pcall(panel.StartMoving, panel)
    end)
    dragHandle:SetScript("OnDragStop", function()
        pcall(panel.StopMovingOrSizing, panel)
    end)

    sidebar = CreatePanel(panel, {
        name = "LibConfigSidebar",
        width = SIDEBAR_WIDTH,
        height = PANEL_HEIGHT - HEADER_HEIGHT - FOOTER_HEIGHT,
        background = THEME.backdropFade,
    })
    sidebar:SetPoint("TOPLEFT", panel, "TOPLEFT", MARGIN, -HEADER_HEIGHT)

    -- Sidebar scrollbar, inside the sidebar's own right edge (the gap to
    -- the content area is only MARGIN wide, too narrow for it). Shown
    -- only when the tree is taller than the sidebar; RenderSidebar drives
    -- both that and the row width that frees up for it.
    sidebarScrollBar = CreateScrollBar(panel, {
        name = "LibConfigSidebarScrollBar",
        step = ROW_HEIGHT + 2,
        onScroll = function(offset)
            sidebarOffset = offset
            RenderSidebar()
        end,
    })
    sidebarScrollBar.frame:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", -4, -4)
    sidebarScrollBar.frame:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", -4, 4)
    sidebarScrollBar.SetShown(false)

    -- Mouse-wheel support for the sidebar. OnMouseWheel only fires
    -- reliably on a ScrollFrame on Unreal Azeroth (the same finding that
    -- shaped the dropdown menu and this project's chat/minimap wheel
    -- handling), so an invisible ScrollFrame is laid over the sidebar
    -- purely to catch the wheel. Mouse-wheel only -- normal clicks still
    -- reach the rows underneath.
    local sidebarWheel = CreateFrame("ScrollFrame", "LibConfigSidebarWheel", sidebar)
    sidebarWheel:SetAllPoints(sidebar)
    pcall(sidebarWheel.EnableMouseWheel, sidebarWheel, true)
    sidebarWheel:SetScript("OnMouseWheel", function(a1, a2)
        local delta = arg1
        if type(a1) == "number" then delta = a1 end
        if type(a2) == "number" then delta = a2 end
        if type(delta) ~= "number" then return end
        sidebarOffset = sidebarOffset - delta * (ROW_HEIGHT + 2) * 2
        if sidebarOffset < 0 then sidebarOffset = 0 end
        RenderSidebar()
    end)

    contentScroll = CreateFrame("ScrollFrame", "LibConfigContentScroll", panel)
    contentScroll:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", MARGIN, 0)
    -- Right edge pulled in by SCROLLBAR_GUTTER so the scrollbar has a strip
    -- of its own to live in, outside the scrollable viewport (CONTENT_WIDTH
    -- is reduced by the same amount).
    contentScroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -MARGIN - SCROLLBAR_GUTTER, FOOTER_HEIGHT)

    content = CreateFrame("Frame", "LibConfigContent", contentScroll)
    content:SetWidth(CONTENT_WIDTH)
    contentScroll:SetScrollChild(content)

    panel.close = CreateButton(panel, {
        name = "LibConfigClose",
        text = "Close",
        width = 100,
        height = 24,
        onClick = function() panel:Hide() end,
    })
    panel.close:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -MARGIN, MARGIN)
    table.insert(panelChrome, panel.close)

    -- Proper scrollbar down the right-hand gutter (MINOR 11), replacing
    -- the pair of loose "^"/"v" buttons that used to live in the footer
    -- next to Close.
    --
    -- HISTORY WORTH KEEPING, because it constrains where this can go.
    -- Originally the two buttons were anchored to `contentScroll`'s OWN
    -- bottom-right corner -- i.e. INSIDE the rectangle `contentScroll`
    -- uses for its viewport -- and, being siblings under `panel` rather
    -- than children of the ScrollFrame, its clipping never hid them. They
    -- sat permanently on top of whatever content scrolled into that
    -- corner and silently stole its clicks: a live report found a
    -- "select" near the bottom of a 15-item group whose OnEnter/tooltip
    -- fired but whose OnClick never opened the menu, fixed purely by
    -- moving that field earlier in the list. MINOR 7 moved them into the
    -- footer to get them out of the viewport entirely.
    --
    -- The scrollbar cannot go back on top of the content for exactly that
    -- reason, so `contentScroll`'s right edge is pulled in by
    -- SCROLLBAR_GUTTER (and CONTENT_WIDTH with it) and the bar occupies
    -- the strip that frees up -- a real gutter, never an overlay.
    contentScrollBar = CreateScrollBar(panel, {
        name = "LibConfigScrollBar",
        step = ROW_HEIGHT,
        onScroll = function(offset) SetContentScroll(offset) end,
    })
    contentScrollBar.frame:SetPoint("TOPLEFT", contentScroll, "TOPRIGHT", 4, 0)
    contentScrollBar.frame:SetPoint("BOTTOMLEFT", contentScroll, "BOTTOMRIGHT", 4, 0)
    contentScrollBar.SetShown(false)
    -- Deliberately NOT added to `panelChrome`: that list is toggled with a
    -- plain Show/Hide per entry, and children don't reliably follow a
    -- parent's visibility on this client, so the bar's own arrows and
    -- thumb would linger. Its visibility is driven by SetShown instead --
    -- from FinishContentScroll (does this page even overflow?) and from
    -- the panel's own show/hide paths.

    pcall(contentScroll.EnableMouseWheel, contentScroll, true)
    contentScroll:SetScript("OnMouseWheel", function(a1, a2)
        local delta = arg1
        if type(a1) == "number" then delta = a1 end
        if type(a2) == "number" then delta = a2 end
        if type(delta) ~= "number" then delta = 0 end
        ScrollContentBy(-delta * ROW_HEIGHT * 3)
    end)

    panel:Hide()
    sidebar:Hide()
    contentScroll:Hide()
    SetListShown(panelChrome, false)
    contentScrollBar.SetShown(false)
    sidebarScrollBar.SetShown(false)
end

local function EnsurePanel()
    if panel then return panel end
    Build()
    return panel
end

-- ===========================================================================
-- Public API
-- ===========================================================================
local function FindCategory(appName, name)
    local i
    for i = 1, table.getn(lib.categories) do
        local c = lib.categories[i]
        if (appName == nil or c.appName == appName) and c.name == name then
            return c
        end
    end
    return nil
end

function lib:RegisterOptionsTable(appName, name, configtable)
    if type(appName) ~= "string" or type(name) ~= "string" then
        return nil
    end
    lib.registry[appName] = lib.registry[appName] or {}
    lib.registry[appName][name] = configtable

    local found = false
    local i
    for i = 1, table.getn(lib.categories) do
        local c = lib.categories[i]
        if c.appName == appName and c.name == name then
            c.table = configtable
            found = true
            break
        end
    end
    if not found then
        table.insert(lib.categories, { appName = appName, name = name, table = configtable })
    end
    return configtable
end

-- Familiar AceConfigDialog-3.0 name; ensures the window exists and returns it.
function lib:AddToBlizOptions(appName, name)
    EnsurePanel()
    return panel
end

function lib:Open(appName, name)
    local cat = FindCategory(appName, name)
    if not cat then return end
    EnsurePanel()
    -- Show the window first, then build the widgets, so the widgets are created
    -- under a shown content frame (on this client a widget created under a
    -- hidden parent does not render its Button/backdrop regions).
    panel:Show()
    sidebar:Show()
    contentScroll:Show()
    content:Show()
    SetListShown(panelChrome, true)
    SelectPage(BuildRootPage(cat))
end

function lib:OpenToCategory(name)
    lib:Open(nil, name)
end

function lib:Close()
    if panel then panel:Hide() end
end
