-- DataBars module -- shared scaffolding for real ElvUI's "data bar" family
-- (Experience, Reputation, ...), giving the XP/Reputation bars their own
-- real modules rather than leaving them permanently hidden as generic
-- ActionBars chrome.
--
-- Kept as a SEPARATE file from XPBar.lua/ReputationBar.lua, in its own
-- Modules/DataBars/ folder, deliberately mirroring real ElvUI's own actual
-- file layout (ElvUI-vanilla/ElvUI/Modules/DataBars/{DataBars,
-- Experience,Reputation}.lua), rather than folding everything into one
-- flat Modules/XPBar.lua file the way this project's other single-feature
-- modules (Minimap.lua, WorldMap.lua) are written.

local E, L, V, P, G = unpack(ElvUI)
local M = E:NewModule("DataBars", "AceEvent-3.0")
E.DataBars = M

-- Settings: `P.databars.experience` / `P.databars.reputation`
-- (Settings/Profile.lua).

-- Ported from real ElvUI's own DataBars.lua, adapted to this project's
-- available primitives -- no E:SetInside/
-- E:RegisterStatusBar/E:FontTemplate/E.UIParent/E.media.normTex (a whole
-- Skins-module infrastructure this project doesn't have yet, same gap
-- already noted for WorldMap/ActionBars). Frame CONSTRUCTION technique
-- (backdrop anchor + inset StatusBar) instead follows UnrealUI's own
-- proven-on-UA xpbar.lua (UnrealUI/modules/xpbar.lua) --
-- everything else (field names, defaults, settings, formatting, event
-- list) comes from real ElvUI instead.
--
-- name: frame name (e.g. "ElvUI_ExperienceBar", matching real ElvUI's
-- own global name exactly, in case anything else in this project or a
-- future module ever looks it up by name).
-- color: {r,g,b,a} for the main fill.
function M:CreateBar(name, color)
	local anchor = CreateFrame("Frame", name, UIParent)
	pcall(anchor.SetBackdrop, anchor, {
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\Buttons\\WHITE8x8",
		edgeSize = 1,
	})
	pcall(anchor.SetBackdropColor, anchor, 0.1, 0.1, 0.1, 1)
	pcall(anchor.SetBackdropBorderColor, anchor, 0, 0, 0, 1)
	anchor:SetFrameStrata("LOW")
	anchor:Hide()

	local bar = CreateFrame("StatusBar", nil, anchor)
	bar:SetPoint("TOPLEFT", anchor, "TOPLEFT", 1, -1)
	bar:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -1, 1)
	-- E.media.normTex -- real ElvUI has NO per-bar statusbar field for
	-- DataBars/Experience (no "statusbar" key under P.databars.experience
	-- in its own Settings/Profile.lua) -- it reads the ONE shared,
	-- PRIVATE `E.media.normTex` instead, same as MirrorTimers (see
	-- Core/MirrorTimers.lua's own comment, and Init.lua's, for the full
	-- explanation), matching real ElvUI's actual variable name rather
	-- than an invented per-module one.
	pcall(bar.SetStatusBarTexture, bar, E.media and E.media.normTex or "Interface\\Buttons\\WHITE8x8")
	bar:SetStatusBarColor(color[1], color[2], color[3], color[4] or 1)
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(0)
	anchor.statusBar = bar

	local text = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	text:SetPoint("CENTER", bar, "CENTER", 0, 0)
	anchor.text = text

	return anchor
end

-- Shared "hide a native frame/region for good" helper, used by both
-- XPBar.lua and ReputationBar.lua. Same "hide once, then permanently
-- neuter Show()" pattern established in Modules/ActionBars/
-- ActionBars.lua's own HideFrame.
--
-- Handles REGIONS (Texture/FontString) as well as Frames -- the native
-- watch bar's chrome is mostly Textures parented to a StatusBar, and a
-- region has no UnregisterAllEvents/SetScript/EnableMouse at all
-- (indexing those just yields nil, and every call here is pcall'd
-- anyway, so the same function covers both cases without a type check).
function M:HideNativeFrame(object)
	if not object then return end
	pcall(object.UnregisterAllEvents, object)
	pcall(object.SetScript, object, "OnEvent", nil)
	pcall(object.SetScript, object, "OnUpdate", nil)
	pcall(object.Hide, object)
	pcall(object.SetAlpha, object, 0)
	if object.EnableMouse then pcall(object.EnableMouse, object, false) end
	if object.Show then
		object.Show = E.noop
	end
end

-- Sets a bar's alpha on EVERY layer it is built from, not just the outer
-- anchor frame.
--
-- Both bars implement `mouseover` the way real ElvUI does -- one
-- `bar:SetAlpha(0)` on the outer frame, back to 1 on OnEnter -- which
-- relies on alpha CASCADING to child frames. It doesn't on UA: hiding a
-- parent frame doesn't hide its children there, and alpha behaves the
-- same way. So the anchor alone fading would leave the inner StatusBar,
-- the rested overlay and the text -- i.e. everything actually visible --
-- at full alpha, and the setting would look like it did nothing at all.
--
-- Same class of fix as this module's own OnEnter/OnLeave wiring, which
-- already had to be attached per-layer rather than relying on the outer
-- frame receiving the mouse for its children.
function M:SetBarAlpha(bar, alpha)
	if not bar then return end

	-- Built by table.insert rather than as a literal `{ bar,
	-- bar.statusBar, bar.rested, bar.text }` on purpose: `rested` only
	-- exists on the XP bar, and a nil in the middle of a table
	-- constructor leaves a HOLE, which makes table.getn's result
	-- undefined (Lua 5.0 and 5.1 alike) -- it could stop at the hole and
	-- silently never reach `text`.
	local layers = {}
	table.insert(layers, bar)
	if bar.statusBar then table.insert(layers, bar.statusBar) end
	if bar.rested then table.insert(layers, bar.rested) end
	if bar.text then table.insert(layers, bar.text) end

	local i
	for i = 1, table.getn(layers) do
		pcall(layers[i].SetAlpha, layers[i], alpha)
	end
end

function M:Initialize()
	self.db = E.db.databars
	self:LoadExperienceBar()
	self:LoadReputationBar()

	-- Both bars hide themselves when they have nothing to show (no watched
	-- faction / max level), which would also take their own mover drag
	-- handle down with them -- the handle is a CHILD of the frame it moves.
	-- Both UpdateXXX functions already keep the frame visible while
	-- E.moversUnlocked is true; this just makes them re-evaluate the
	-- INSTANT move mode toggles, instead of on their next 2s poll tick
	-- (which read as "the bar is missing from /moveui" in practice).
	if E.RegisterMoverStateCallback then
		E:RegisterMoverStateCallback(function()
			M:UpdateExperience()
			M:UpdateReputation()
		end)
	end
end

local function InitializeCallback()
	M:Initialize()
end

E:RegisterInitialModule(M:GetName(), InitializeCallback)
