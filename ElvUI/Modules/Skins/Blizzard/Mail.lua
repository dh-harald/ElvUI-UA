-- Skins > Blizzard > Mail -- reskins the mailbox in place: MailFrame with
-- its Inbox and Send Mail tabs, plus OpenMailFrame, the separate top-level
-- window that shows one received letter. Same recipe family as
-- Merchant.lua: strip the native chrome, draw elvBackground/elvField child
-- frames (never SetBackdrop a native frame), let the sweep pick up the
-- generic leftovers.
--
-- Structure per `FrameXML/MailFrame.xml`/`.lua`:
--
-- - `MailFrame` carries the portrait and the four corner art pieces as its
--   OWN Texture regions, so one non-recursive strip clears them. The
--   native tab switch (`MailFrameTab_OnClick`) re-`SetTexture`s all four
--   on every switch, which the strip survives: it hides each region AND
--   replaces its `Show` with a no-op, and the native code never calls
--   `Show` on them.
-- - **An inbox row's sender and subject are FontStrings on the row's own
--   BACKGROUND layer**, so they must be promoted to OVERLAY: the row's
--   field surface is a child frame pinned to the row's base frame level,
--   and at equal levels draw order falls back to draw layer, which would
--   put the surface on top of its own row's text.
-- - An inbox row's icon button is NOT `ItemButtonTemplate`: its slot art
--   is a named BACKGROUND texture (`$parentSlot`) and its icon is
--   `$parentIcon`, not `$parentIconTexture`, so `Util.SkinItemButton`
--   (which keys off that name) does not fit and the pair is handled here.
--   The three OpenMailFrame attachment buttons ARE `ItemButtonTemplate`
--   and go through `Util.SkinItemButton` unchanged.
-- - The row's native CheckedTexture is left alone: it marks which mail is
--   currently open in OpenMailFrame, a live state, not decoration.
-- - `OpenMail_Update` runs when the mailbox opens, not only when a letter
--   is opened, so OpenMailFrame's own OnShow is enough of a trigger and no
--   native function needs wrapping.
--
-- The Mail module (`Modules/Mail/`) adds its own checkbox column and
-- buttons to the inbox. Those are our frames, already ElvUI-styled, and
-- are kept out of both the strip walk and the sweep by name.
--
-- SCOPE: outer chrome and panel on all three frames, inbox rows and their
-- icon buttons, page arrows, both tabs, close buttons, the Send Mail
-- scroll area, edit boxes, money fields and buttons, and OpenMailFrame's
-- letter/package/money buttons, scroll area and action buttons.
-- Deliberately NOT done: the Send Mail layout itself, which the Mail
-- module rebuilds for multiple attachments.

local E, L, V, P, G = unpack(ElvUI)
local _G = _G or getfenv()
local S = E:GetModule("Skins")

-- Real ElvUI's own insets for this window (`Blizzard/Mail.lua`,
-- source/ElvUI-vanilla): clear of the portrait, stopping above the tab row
-- that hangs below the frame.
local PANEL_LEFT, PANEL_TOP, PANEL_RIGHT, PANEL_BOTTOM = 10, -12, -30, 74
local OPEN_LEFT, OPEN_TOP, OPEN_RIGHT, OPEN_BOTTOM = 12, -12, -34, 74

-- FontStrings sitting DIRECTLY on a frame that gets a panel surface; see
-- the header for why they have to move up a draw layer.
local MAIL_TEXTS = {
	"InboxTitleText",
	"InboxCurrentPage",
	"InboxTooMuchMail",
	"SendMailTitleText",
	"SendMailErrorText",
	"SendMailMoneyText",
}

local OPEN_MAIL_TEXTS = {
	"OpenMailTitleText",
	"OpenMailAttachmentText",
	"OpenMailSenderLabel",
	"OpenMailSender",
	"OpenMailSubjectLabel",
	"OpenMailSubject",
}

local function PromoteTexts(names)
	local i
	for i = 1, table.getn(names) do
		local fs = _G[names[i]]
		if fs then pcall(fs.SetDrawLayer, fs, "OVERLAY") end
	end
end

local function RowCount()
	return tonumber(_G.INBOXITEMS_TO_DISPLAY) or 7
end

-- Mail's own icon-button shape: kill the slot art, crop the icon to the
-- button's edge, add the shared 1px border.
local function StyleMailIconButton(button)
	if not button then return end

	local okName, name = pcall(button.GetName, button)
	if okName and name then
		local slot = _G[name.."Slot"]
		if slot then
			pcall(slot.SetTexture, slot, nil)
			pcall(slot.Hide, slot)
			slot.Show = E.noop
		end

		local icon = _G[name.."Icon"]
		if icon then
			pcall(icon.SetTexCoord, icon, 0.08, 0.92, 0.08, 0.92)
			pcall(icon.ClearAllPoints, icon)
			pcall(icon.SetPoint, icon, "TOPLEFT", button, "TOPLEFT", 1, -1)
			pcall(icon.SetPoint, icon, "BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
		end
	end

	if ElvUI.Util and ElvUI.Util.CreateButtonBorder then
		ElvUI.Util.CreateButtonBorder(button)
	end
end

local function StyleInboxRow(i)
	local row = _G["MailItem"..i]
	if not row then return end

	S:StripTextures(row, false)
	S:CreateField(row, 2, -1, -2, 2)

	local sender = _G["MailItem"..i.."Sender"]
	if sender then pcall(sender.SetDrawLayer, sender, "OVERLAY") end
	local subject = _G["MailItem"..i.."Subject"]
	if subject then pcall(subject.SetDrawLayer, subject, "OVERLAY") end

	StyleMailIconButton(_G["MailItem"..i.."Button"])
end

-- An edit box here carries its own label ("To:", "Subject:") and, in the
-- money row, its coin icon as regions on its BACKGROUND layer -- the same
-- layer `S:StyleEditBox` disables to get rid of the native input border.
-- Both are moved up a layer first, so only the border art is lost.
-- The border pieces themselves are named ($parentLeft/Middle/Right) and are
-- left where they are: the edit box styling kills them by name.
local function PromoteEditBoxArt(box)
	if not box then return end

	local okName, name = pcall(box.GetName, box)
	local okRegions, regions = pcall(function() return { box:GetRegions() } end)
	if not okRegions or type(regions) ~= "table" then return end

	local i
	for i = 1, table.getn(regions) do
		local region = regions[i]
		local okType, regionType = pcall(region.GetObjectType, region)
		if okType and regionType == "FontString" then
			pcall(region.SetDrawLayer, region, "OVERLAY")
		elseif okType and regionType == "Texture" then
			local okRegionName, regionName = pcall(region.GetName, region)
			local isBorder = okName and okRegionName and regionName
				and (regionName == name.."Left" or regionName == name.."Middle"
					or regionName == name.."Mid" or regionName == name.."Right")
			if not isBorder then
				pcall(region.SetDrawLayer, region, "ARTWORK")
			end
		end
	end
end

-- The native input border does not sit on the edit box's own rect: its left
-- piece is anchored OUTSIDE it (8px for the name/subject boxes, 5px for the
-- money fields), so the field a player sees natively is that much wider than
-- the widget. Our own field surface covers the rect exactly, which left every
-- box looking shifted right against the labels and coin icons anchored to the
-- native geometry. Each box therefore gets its surface stretched back out to
-- where its own border art started.
local function StyleEditBoxWithArt(box, leftOverhang)
	if not box then return end

	PromoteEditBoxArt(box)
	S:StyleEditBox(box)

	local bg = box.elvBackground
	if bg and leftOverhang then
		pcall(bg.ClearAllPoints, bg)
		pcall(bg.SetPoint, bg, "TOPLEFT", box, "TOPLEFT", -leftOverhang, 0)
		pcall(bg.SetPoint, bg, "BOTTOMRIGHT", box, "BOTTOMRIGHT", 0, 0)
	end
end

local RADIO_SIZE = 22

local function StyleRadioButton(button)
	if not button then return end
	pcall(button.SetWidth, button, RADIO_SIZE)
	pcall(button.SetHeight, button, RADIO_SIZE)
	S:StyleCheckBox(button)
end

-- "Postage:" is a FontString region of the cost money frame, anchored to that
-- frame's LEFT -- its vertical centre -- while the digits inside the frame
-- draw a few pixels lower, so the two never lined up. Nudged down to sit on
-- the same line as the amount. It is the frame's only direct FontString; the
-- digits live on the frame's gold/silver/copper child buttons.
local function AlignCostLabel()
	local frame = _G.SendMailCostMoneyFrame
	if not frame then return end

	local okRegions, regions = pcall(function() return { frame:GetRegions() } end)
	if not okRegions or type(regions) ~= "table" then return end

	local i
	for i = 1, table.getn(regions) do
		local region = regions[i]
		local okType, regionType = pcall(region.GetObjectType, region)
		if okType and regionType == "FontString" then
			pcall(region.ClearAllPoints, region)
			pcall(region.SetPoint, region, "RIGHT", frame, "LEFT", -3, -4)
		end
	end
end

-- The letter the player is WRITING is the one piece of text in this window
-- that cannot be recoloured in place. `SendMailBodyEditBox` inherits
-- `MailTextFontNormal` from XML (`MailFrame.xml:648`) -- a dark face drawn
-- for parchment -- and on Unreal Azeroth every way to change that is closed:
-- `SetTextColor` and `SetFontObject` are both inert on it, and its internal
-- FontString is not reachable (`GetNumRegions()` returns 0). Legacy takes
-- `SetTextColor` normally, so this is that client's gap, not a rule.
--
-- An EditBox WE create has no font at all until one is set, and takes
-- `SetFontObject` on both clients -- the same "new works, native does not"
-- split as `SetBackdrop` on native frames. So the box the player types in is
-- ours, laid over the native one, and every keystroke is mirrored into the
-- native box: the send path reads `SendMailBodyEditBox:GetText()`
-- (`MailFrame.lua:506`), so nothing downstream changes. The mirror runs both
-- ways -- the native code clears its own box after a send
-- (`MailFrame.lua:556`) and that has to reach the visible one.
local composeBox
local composeMirror

local function SyncComposeFromNative(native)
	local okText, text = pcall(native.GetText, native)
	text = (okText and text) or ""
	if text == composeMirror then return end
	composeMirror = text
	pcall(composeBox.SetText, composeBox, text)
end

local function BuildComposeBox()
	if composeBox then return end

	local native = _G.SendMailBodyEditBox
	local holder = _G.SendMailScrollChildFrame
	if not (native and holder) then return end

	local ok, box = pcall(CreateFrame, "EditBox", "ElvUI_MailBody", holder)
	if not (ok and box) then return end

	local okW, width = pcall(native.GetWidth, native)
	local okH, height = pcall(native.GetHeight, native)
	pcall(box.SetWidth, box, (okW and width) or 270)
	pcall(box.SetHeight, box, (okH and height) or 200)
	pcall(box.SetPoint, box, "TOPLEFT", native, "TOPLEFT", 0, 0)
	pcall(box.SetMultiLine, box, true)
	pcall(box.SetAutoFocus, box, false)
	pcall(box.SetMaxLetters, box, 500)
	-- The font object is handed over HERE, at creation, and nothing touches
	-- the box's colour afterwards. On Unreal Azeroth that is the only moment
	-- it takes: `SetTextColor` never works on this box (measured), and
	-- `SetFontObject` on an ALREADY BUILT box does not recolour it either --
	-- neither a light nor a dark object changed a box that was already on
	-- screen. So the colour the letter is written in is decided by whichever
	-- font object arrives on this line, and it has to be a white one.
	--
	-- `GameFontHighlightSmall` is white by definition (`Fonts.xml:103-104`).
	-- The mail face (`MailTextFontNormal`) cannot be used, however much it
	-- would match the letter as READ: it carries a dark parchment colour that
	-- there is no way to override here.
	pcall(box.SetFontObject, box, _G.GameFontHighlightSmall or _G.ChatFontNormal)
	pcall(box.EnableMouse, box, true)

	-- Keyboard reaches an EditBox through focus, so nothing here enables it
	-- frame-wide: a visible keyboard-enabled frame swallows every key on
	-- Unreal Azeroth, and Escape is the way back out of the letter.
	box:SetScript("OnEscapePressed", function() pcall(box.ClearFocus, box) end)
	box:SetScript("OnTextChanged", function()
		local okText, text = pcall(box.GetText, box)
		composeMirror = (okText and text) or ""
		pcall(native.SetText, native, composeMirror)
	end)
	-- Catches the native side writing into its own box, which no event
	-- reports: a send resets it, and a reply prefills it.
	box:SetScript("OnUpdate", function() SyncComposeFromNative(native) end)

	composeBox = box

	-- The native box keeps holding the text the send path reads; only its
	-- unreadable rendering is taken out of the way.
	pcall(native.Hide, native)
	SyncComposeFromNative(native)
end

local function StyleSendMail()
	local frame = _G.SendMailFrame
	if not frame then return end

	S:StripTextures(frame, false)

	local scroll = _G.SendMailScrollFrame
	if scroll then
		S:StripTextures(scroll, true)
		S:CreateField(scroll, 0, 0, 0, 0)
	end
	S:HandleScrollBar(_G.SendMailScrollFrameScrollBar)

	BuildComposeBox()

	StyleEditBoxWithArt(_G.SendMailNameEditBox, 8)
	StyleEditBoxWithArt(_G.SendMailSubjectEditBox, 8)
	StyleEditBoxWithArt(_G.SendMailMoneyGold, 5)
	StyleEditBoxWithArt(_G.SendMailMoneySilver, 5)
	StyleEditBoxWithArt(_G.SendMailMoneyCopper, 5)

	S:StyleUIPanelButton(_G.SendMailMailButton)
	S:StyleUIPanelButton(_G.SendMailCancelButton)
	S:StyleUIPanelButton(_G.SendMailStationeryButton)

	-- Send Money / C.O.D. are radio buttons (`UIRadioButtonTemplate`), so the
	-- sweep's checkbox recognition -- which matches the checkbox art by file
	-- name -- never sees them. Styled by name instead, with the checkbox
	-- recipe: they end up square rather than round, which is what every other
	-- two-state control in this UI looks like.
	--
	-- Enlarged first: a radio button is smaller than a checkbox natively, and
	-- the mark this recipe draws is inset inside the box, so at native size
	-- the checked state was a few pixels wide and easy to miss.
	StyleRadioButton(_G.SendMailSendMoneyButton)
	StyleRadioButton(_G.SendMailCODButton)

	AlignCostLabel()

	-- The attachment slot's icon IS the button's own normal texture (it is
	-- set from the attached item), so only the surrounding art is stripped
	-- and the border added -- nothing here may touch the normal texture.
	local package = _G.SendMailPackageButton
	if package then
		S:StripTextures(package, false)
		if ElvUI.Util and ElvUI.Util.CreateButtonBorder then
			ElvUI.Util.CreateButtonBorder(package)
		end
	end
end

local function ApplyMailChrome(frame)
	S:StripTextures(frame, false)
	S:CreatePanel(frame, PANEL_LEFT, PANEL_TOP, PANEL_RIGHT, PANEL_BOTTOM)
	PromoteTexts(MAIL_TEXTS)

	local i
	for i = 1, RowCount() do
		StyleInboxRow(i)
	end

	-- Same page-arrow shape as the spellbook's, minus the separate
	-- BACKGROUND square the merchant's pair carries. The "Prev"/"Next"
	-- labels beside them are kept: they are the only page affordance once
	-- the native art is gone.
	S:StyleSquareIconButton(_G.InboxPrevPageButton, "LEFT", 0.5)
	S:StyleSquareIconButton(_G.InboxNextPageButton, "RIGHT", 0.5)

	S:StyleTab(_G.MailFrameTab1)
	S:StyleTab(_G.MailFrameTab2)

	StyleSendMail()

	S:StyleCloseButton(_G.InboxCloseButton)
	local close = _G.InboxCloseButton
	if close and frame.elvBackground then
		pcall(close.ClearAllPoints, close)
		pcall(close.SetPoint, close, "TOPRIGHT", frame.elvBackground, "TOPRIGHT", -4, -4)
	end

	S:SkinChildren(frame)
end

-- "From:"/"Subject:" and the values beside them: both labels carry an
-- explicit 16px height while the values auto-size (MailFrame.xml), so the
-- native LEFT-to-RIGHT anchor that should centre the sender against its
-- label leaves it 2 units low (measured on this client: label top 619,
-- value top 617). The subject value is anchored differently again --
-- natively it hangs off the label's TOPRIGHT with a -4 offset, in a
-- smaller font -- and reads as visibly dropped. Both get the same
-- centring anchor, the sender with the measured correction.
local function AlignLabelledText(value, label, yOffset)
	if not (value and label) then return end
	pcall(value.ClearAllPoints, value)
	pcall(value.SetPoint, value, "LEFT", label, "RIGHT", 5, yOffset)
end

local function AlignOpenMailHeaders()
	AlignLabelledText(_G.OpenMailSender, _G.OpenMailSenderLabel, 2)
	AlignLabelledText(_G.OpenMailSubject, _G.OpenMailSubjectLabel, 0)
end

local function ApplyOpenMailChrome(frame)
	S:StripTextures(frame, false)
	S:CreatePanel(frame, OPEN_LEFT, OPEN_TOP, OPEN_RIGHT, OPEN_BOTTOM)
	PromoteTexts(OPEN_MAIL_TEXTS)
	AlignOpenMailHeaders()

	local scroll = _G.OpenMailScrollFrame
	if scroll then
		S:StripTextures(scroll, true)
		S:CreateField(scroll, 0, 0, 0, 0)
	end
	S:HandleScrollBar(_G.OpenMailScrollFrameScrollBar)

	local body = _G.OpenMailBodyText
	if body then pcall(body.SetTextColor, body, 1, 1, 1) end

	-- Auction invoice text, recoloured exactly as real ElvUI does it. The
	-- first is a font object rather than a FontString, which carries no
	-- methods on every client -- harmless where it does nothing.
	local invoice = _G.InvoiceTextFontNormal
	if invoice then pcall(invoice.SetTextColor, invoice, 1, 1, 1) end
	local buyMode = _G.OpenMailInvoiceBuyMode
	if buyMode then pcall(buyMode.SetTextColor, buyMode, 1, 0.80, 0.10) end

	-- Auction invoices draw their own separator line on parchment; on the
	-- dark panel it reads as a stray bright bar.
	S:Kill(_G.OpenMailArithmeticLine)

	if ElvUI.Util and ElvUI.Util.SkinItemButton then
		ElvUI.Util.SkinItemButton(_G.OpenMailLetterButton)
		ElvUI.Util.SkinItemButton(_G.OpenMailPackageButton)
		ElvUI.Util.SkinItemButton(_G.OpenMailMoneyButton)
	end

	S:StyleUIPanelButton(_G.OpenMailReplyButton)
	S:StyleUIPanelButton(_G.OpenMailDeleteButton)
	S:StyleUIPanelButton(_G.OpenMailCancelButton)

	S:StyleCloseButton(_G.OpenMailCloseButton)
	local close = _G.OpenMailCloseButton
	if close and frame.elvBackground then
		pcall(close.ClearAllPoints, close)
		pcall(close.SetPoint, close, "TOPRIGHT", frame.elvBackground, "TOPRIGHT", -4, -4)
	end

	S:SkinChildren(frame)
end

local mailSkinApplied = false
local function InstallMailSkin()
	if mailSkinApplied then return end
	local frame = _G.MailFrame
	if not frame then return end
	mailSkinApplied = true

	-- Our own inbox widgets: never stripped, never swept.
	local i
	for i = 1, RowCount() do
		S.stripSkipNames["ElvUI_MailSelect"..i] = true
		S.autoSkinSkipNames["ElvUI_MailSelect"..i] = true
	end
	S.stripSkipNames["ElvUI_MailOpenAll"] = true
	S.autoSkinSkipNames["ElvUI_MailOpenAll"] = true
	S.stripSkipNames["ElvUI_MailOpenSelected"] = true
	S.autoSkinSkipNames["ElvUI_MailOpenSelected"] = true
	S.stripSkipNames["ElvUI_MailReturnSelected"] = true
	S.autoSkinSkipNames["ElvUI_MailReturnSelected"] = true
	S.stripSkipNames["ElvUI_MailBody"] = true
	S.autoSkinSkipNames["ElvUI_MailBody"] = true

	local handle = S:MakeDraggable(frame)
	if handle then
		pcall(handle.SetPoint, handle, "TOPRIGHT", frame, "TOPRIGHT", PANEL_RIGHT, 0)
	end
	pcall(frame.SetUserPlaced, frame, true)

	ApplyMailChrome(frame)

	-- The Send Mail tab is a sibling frame the outer OnShow does not cover:
	-- switching tabs shows it without reopening the window.
	local ok = S:TryHookScript(frame, "OnShow", function() ApplyMailChrome(frame) end)
	local sendFrame = _G.SendMailFrame
	if sendFrame then
		local sendOk = S:TryHookScript(sendFrame, "OnShow", function() StyleSendMail() end)
		ok = ok and sendOk
	end

	local openFrame = _G.OpenMailFrame
	if openFrame then
		ApplyOpenMailChrome(openFrame)
		local openOk = S:TryHookScript(openFrame, "OnShow", function() ApplyOpenMailChrome(openFrame) end)
		ok = ok and openOk
	end

	if not ok then S:ReportSkinProblem() end
end

-- Entry point for the Mail module, which owns the window's look while it
-- runs: its own controls are drawn in this UI's style, so the window they
-- sit in has to be too, whatever the per-window skin toggle says. Idempotent
-- -- if the toggle already installed the skin, this is a no-op.
function S:ApplyMailSkin()
	InstallMailSkin()
end

-- Registered path: gated by `skins.blizzard.mail`, for when the Mail module
-- is switched off and the toggle alone decides the window's look.
local function LoadSkin()
	InstallMailSkin()
end

S:AddBlizzardSkin("mail", LoadSkin)
