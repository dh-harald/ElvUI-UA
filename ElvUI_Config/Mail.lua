local E, L, V, P, G = unpack(ElvUI)

-- Mail module options. Real ElvUI has no mailbox module, so this category
-- has no upstream counterpart to match; the settings live in `E.global`
-- (account-wide) rather than in a profile, which keeps `E.db` compatible
-- with a real ElvUI profile.
--
-- The enable toggle also decides the window's look: with the module ON the
-- mailbox is always skinned, because the module's own controls are drawn in
-- this UI's style and it pulls the window skin in itself. The per-window
-- skin toggle under Skins > Blizzard is disabled while that is the case.
E.Options.args.mail = {
	type = "group",
	name = L["Mail"],
	order = 7,
	get = function(info) return E.global.mail[ info[ElvUI.Compat.getn(info)] ] end,
	set = function(info, value)
		local key = info[ElvUI.Compat.getn(info)]
		E.global.mail[key] = value
		-- Only whether the module loads at all needs a restart; the rest are
		-- read fresh on the next inbox refresh or bulk run.
		if key == "enable" then E:RequestReload("global") end
	end,
	args = {
		intro = {
			order = 1,
			type = "description",
			name = L["Adds bulk handling to the native mailbox: open several mails at once, pick which ones with a checkbox, and send more than one item at a time."],
		},
		enable = {
			order = 2,
			type = "toggle",
			name = L["Enable"],
			desc = L["With this off the mailbox is left to the Blizzard window skin instead. Requires /reload to take effect."],
		},
		expiryWarning = {
			order = 3,
			type = "toggle",
			name = L["Warn About Deleted Mail"],
			desc = L["Colours the expiry time of mail that will be DELETED when it runs out, instead of returned to its sender. The client only colours it by time left, so the two look alike until the last day."],
			disabled = function() return not E.global.mail.enable end,
		},
		moneySummary = {
			order = 4,
			type = "toggle",
			name = L["Summarize Collected Money"],
			desc = L["Prints one total at the end of a bulk run, when money came from more than one mail."],
			disabled = function() return not E.global.mail.enable end,
		},
		cleanEmptied = {
			order = 5,
			type = "toggle",
			name = L["Remove Emptied Mail"],
			desc = L["After a bulk run, removes the mail it emptied, so the mailbox is not left full of empty rows. A mail with a letter still in it is never removed -- the test is the client's own: nothing attached, and nothing left to read."],
			disabled = function() return not E.global.mail.enable end,
		},
		autoComplete = {
			order = 6,
			type = "toggle",
			name = L["Complete Recipient Names"],
			desc = L["Typing a recipient drops a short list of matching names under the field: your own characters on this realm, your friends and your guild. Click one, or press Tab to take the first."],
			disabled = function() return not E.global.mail.enable end,
		},
		express = {
			order = 7,
			type = "toggle",
			name = L["Modifier Clicks"],
			desc = L["Shift-click a row in the inbox to take that mail's attachments, and Ctrl-click to send it back to its sender, without opening the mail first. Returning a mail this way is not confirmed and cannot be undone."],
			disabled = function() return not E.global.mail.enable end,
		},
	},
}
