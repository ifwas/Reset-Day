local hoverAlpha = 0.6
local t = Def.ActorFrame {}

local frameWidth = 280
local frameY = 35
local frameX = SCREEN_WIDTH - 250

local sortTable = {
	SortOrder_Group = THEME:GetString("SortOrder", "Group"),
	SortOrder_Title = THEME:GetString("SortOrder", "Title"),
	SortOrder_BPM = THEME:GetString("SortOrder", "BPM"),
	SortOrder_TopGrades = THEME:GetString("SortOrder", "TopGrades"),
	SortOrder_Artist = THEME:GetString("SortOrder", "Artist"),
	SortOrder_Genre = THEME:GetString("SortOrder", "Genre"),
	SortOrder_ModeMenu = THEME:GetString("SortOrder", "ModeMenu"),
	SortOrder_Length = THEME:GetString("SortOrder", "Length"),
	SortOrder_DateAdded = THEME:GetString("SortOrder", "DateAdded"),
	SortOrder_Favorites = THEME:GetString("SortOrder", "Favorites"),
	SortOrder_Overall = THEME:GetString("SortOrder", "Overall"),
	SortOrder_Stream = THEME:GetString("SortOrder", "Stream"),
	SortOrder_Jumpstream = THEME:GetString("SortOrder", "Jumpstream"),
	SortOrder_Handstream = THEME:GetString("SortOrder", "Handstream"),
	SortOrder_Stamina = THEME:GetString("SortOrder", "Stamina"),
	SortOrder_JackSpeed = THEME:GetString("SortOrder", "JackSpeed"),
	SortOrder_Chordjack = THEME:GetString("SortOrder", "Chordjack"),
	SortOrder_Technical = THEME:GetString("SortOrder", "Technical"),
	SortOrder_Author = THEME:GetString("SortOrder", "Author"),
	SortOrder_Ungrouped = THEME:GetString("SortOrder", "Ungrouped")
}

local groupSortCycle = {
	"SortOrder_Group",
	"SortOrder_Title",
	"SortOrder_Artist",
	"SortOrder_Genre",
	"SortOrder_BPM",
	"SortOrder_Length",
	"SortOrder_DateAdded",
	"SortOrder_Favorites",
	"SortOrder_Author",
	"SortOrder_Ungrouped"
}

local function getCurrentGroupSortLabel()
	local sort = GAMESTATE:GetSortOrder()
	return sortTable[sort] or tostring(sort or "Group")
end

local function cycleGroupSort(top)
	if not top or not top.GetMusicWheel then return end
	local wheel = top:GetMusicWheel()
	if not wheel or not wheel.ChangeSort then return end
	local currentSort = GAMESTATE:GetSortOrder()
	for index, sortType in ipairs(groupSortCycle) do
		if sortType == currentSort then
			wheel:ChangeSort(groupSortCycle[(index % #groupSortCycle) + 1])
			return
		end
	end
	wheel:ChangeSort(groupSortCycle[1])
end

local sortY = 100
local sortX = SCREEN_WIDTH - 200
local gearButtonX = SCREEN_WIDTH - 34
local gearIconZoom = 0.028
local buttonHeight = 25
local buttonGap = 6
local groupButtonWidth = 170
local panelButtonWidth = 76
local groupButtonX = gearButtonX - 12 - groupButtonWidth
local playlistsButtonX = groupButtonX - panelButtonWidth - buttonGap
local tagsButtonX = playlistsButtonX - panelButtonWidth - buttonGap

t[#t + 1] = Def.Quad {
	InitCommand = function(self)
		self:xy(tagsButtonX - 8, sortY):zoomto((SCREEN_WIDTH - 20) - (tagsButtonX - 8), buttonHeight + 8):halign(0):valign(0.5):diffuse(color("#000000")):diffusealpha(0.18)
	end,
	SetDynamicAccentColorMessageCommand = function(self, params)
		self:finishtweening():linear(0.2):diffuse(params.color):diffusealpha(0.12)
	end
}

local function switchToPanel(tabIndex)
	local previous = getTabIndex()
	local nextIndex = previous == tabIndex and 0 or tabIndex
	setTabIndex(nextIndex)
	MESSAGEMAN:Broadcast("TabChanged", {from = previous, to = nextIndex})
end

local function makePanelButton(label, tabIndex, x, width)
	local o = Def.ActorFrame {
		InitCommand = function(self)
			self:xy(x, sortY)
		end,
		BeginCommand = function(self)
			self:queuecommand("Set")
		end,
		SetCommand = function(self)
			local active = getTabIndex() == tabIndex
			self:GetChild("BG"):stoptweening():linear(0.08):diffuse(active and getMainColor("positive") or color("#111111")):diffusealpha(active and 0.42 or 0.72)
			self:GetChild("Label"):diffuse(active and color("#FFFFFF") or getMainColor("positive"))
		end,
		TabChangedMessageCommand = function(self)
			self:queuecommand("Set")
		end
	}
	o[#o + 1] = UIElements.QuadButton(1, 1) .. {
		Name = "BG",
		InitCommand = function(self)
			self:zoomto(width, buttonHeight):halign(0):valign(0.5):diffuse(color("#111111")):diffusealpha(0.72)
		end,
		MouseDownCommand = function(self, params)
			if params.event == "DeviceButton_left mouse button" then
				switchToPanel(tabIndex)
			end
		end,
		MouseOverCommand = function(self)
			self:stoptweening():linear(0.08):diffusealpha(0.9)
		end,
		MouseOutCommand = function(self)
			self:GetParent():queuecommand("Set")
		end,
		SetDynamicAccentColorMessageCommand = function(self, params)
			if getTabIndex() ~= tabIndex then
				self:finishtweening():linear(0.2):diffuse(params.color):diffusealpha(0.24)
			end
		end
	}
	o[#o + 1] = LoadFont("Common Normal") .. {
		Name = "Label",
		InitCommand = function(self)
			self:xy(width / 2, 0):halign(0.5):valign(0.5):zoom(0.34):settext(label):maxwidth((width - 14) / 0.34):diffuse(getMainColor("positive"))
		end
	}
	return o
end

local function makeGroupButton(x, width)
	local o = Def.ActorFrame {
		InitCommand = function(self)
			self:xy(x, sortY)
		end,
		BeginCommand = function(self)
			self:queuecommand("Set")
		end,
		SetCommand = function(self)
			self:GetChild("Label"):settext("Group: " .. getCurrentGroupSortLabel())
			self:GetChild("BG"):diffuse(color("#111111")):diffusealpha(0.72)
			self:GetChild("Label"):diffuse(getMainColor("positive"))
		end,
		SortOrderChangedMessageCommand = function(self)
			self:queuecommand("Set")
		end,
		SetDynamicAccentColorMessageCommand = function(self, params)
			self:GetChild("BG"):finishtweening():linear(0.2):diffuse(params.color):diffusealpha(0.24)
		end
	}
	o[#o + 1] = UIElements.QuadButton(1, 1) .. {
		Name = "BG",
		InitCommand = function(self)
			self:zoomto(width, buttonHeight):halign(0):valign(0.5):diffuse(color("#111111")):diffusealpha(0.72)
		end,
		MouseDownCommand = function(self, params)
			if params.event == "DeviceButton_left mouse button" then
				cycleGroupSort(SCREENMAN:GetTopScreen())
			end
		end,
		MouseOverCommand = function(self)
			self:stoptweening():linear(0.08):diffusealpha(0.9)
		end,
		MouseOutCommand = function(self)
			self:GetParent():queuecommand("Set")
		end
	}
	o[#o + 1] = LoadFont("Common Normal") .. {
		Name = "Label",
		InitCommand = function(self)
			self:xy(width / 2, 0):halign(0.5):valign(0.5):zoom(0.34):maxwidth((width - 14) / 0.34):diffuse(getMainColor("positive"))
		end
	}
	return o
end

t[#t + 1] = makePanelButton("Tags", 9, tagsButtonX, panelButtonWidth)
t[#t + 1] = makePanelButton("Playlists", 7, playlistsButtonX, panelButtonWidth)
t[#t + 1] = makeGroupButton(groupButtonX, groupButtonWidth)

t[#t + 1] = UIElements.QuadButton(1, 1) .. {
	Name = "MusicWheelSettingsButton",
	InitCommand = function(self)
		self:xy(gearButtonX, sortY):zoomto(24, 24):diffuse(color("#FFFFFF")):diffusealpha(0.08)
	end,
	MusicWheelSettingsOverlayStateChangedMessageCommand = function(self, params)
		self:stoptweening():linear(0.08):diffusealpha(params and params.active and 0.2 or 0.08)
	end,
	MouseOverCommand = function(self)
		self:stoptweening():linear(0.08):diffusealpha(0.2)
	end,
	MouseOutCommand = function(self)
		if getenv("MusicWheelSettingsOverlayActive") then
			self:stoptweening():linear(0.08):diffusealpha(0.2)
		else
			self:stoptweening():linear(0.08):diffusealpha(0.08)
		end
	end
}

t[#t + 1] = Def.Sprite {
	Texture = THEME:GetPathG("", "Interlude Icons/gear-solid.png"),
	InitCommand = function(self)
		self:xy(gearButtonX, sortY):zoom(gearIconZoom):halign(0.5):valign(0.5):diffuse(getMainColor("positive"))
	end,
	MouseOverCommand = function(self)
		self:diffusealpha(hoverAlpha)
	end,
	MouseOutCommand = function(self)
		self:diffusealpha(1)
	end
}

return t
