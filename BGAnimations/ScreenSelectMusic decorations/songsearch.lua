local searchstring = ""
local active = false
local whee
local lastsearchstring = ""
local instantSearch = themeConfig:get_data().global.InstantSearch

local interludeIconTargetSize = 48
local searchBarX = SCREEN_WIDTH - 420
local searchBarY = 70
local searchBarWidth = 410
local searchBarHeight = 35

local function normalizeInterludeIcon(self)
	local width = self:GetWidth()
	local height = self:GetHeight()
	if width > 0 and height > 0 then
		self:zoom(interludeIconTargetSize / math.max(width, height))
	end
end

local function pointInSearchBar(x, y)
	return x >= searchBarX and x <= searchBarX + searchBarWidth and y >= searchBarY - searchBarHeight / 2 and y <= searchBarY + searchBarHeight / 2
end

local function getSearchDisplayState()
	if active then
		return searchstring .. "_", color("#00FF00")
	elseif searchstring ~= "" then
		return searchstring, color("#FFFFFF")
	end
	return "Click or press Tab to search", color("#888888")
end

local function beginSearch()
	active = true
	MESSAGEMAN:Broadcast("BeginningSearch")
	whee:Move(0)
	MESSAGEMAN:Broadcast("RefreshSearchResults")
	MESSAGEMAN:Broadcast("UpdateString")
end

local function endSearch()
	if not instantSearch then
		whee:SongSearch(searchstring)
	end
	active = false
	MESSAGEMAN:Broadcast("EndingSearch")
	MESSAGEMAN:Broadcast("UpdateString")
end

local function searchInput(event)
	local deviceButton = event.DeviceInput and event.DeviceInput.button or ""
	if event.type == "InputEventType_FirstPress" and deviceButton == "DeviceButton_left mouse button" and getenv("StatsOverlayActive") then
		return false
	end
	if event.type == "InputEventType_FirstPress" and deviceButton == "DeviceButton_left mouse button" and getenv("SuppressSongSearchClick") then
		setenv("SuppressSongSearchClick", false)
		return false
	end

	if event.type == "InputEventType_FirstPress" and active and (deviceButton == "DeviceButton_left mouse button" or deviceButton == "DeviceButton_right mouse button") then
		endSearch()
		return false
	end

	if event.type == "InputEventType_FirstPress" and active and (deviceButton == "DeviceButton_mousewheel up" or deviceButton == "DeviceButton_mousewheel down") then
		return false
	end

	if event.type == "InputEventType_FirstPress" and deviceButton == "DeviceButton_left mouse button" and pointInSearchBar(INPUTFILTER:GetMouseX(), INPUTFILTER:GetMouseY()) then
		if not active then
			beginSearch()
		end
		return true
	end

	if event.type == "InputEventType_FirstPress" and deviceButton == "DeviceButton_tab" then
		active = not active
		if active then
			beginSearch()
		else
			endSearch()
		end
		return true
	end

	if event.type ~= "InputEventType_Release" and active == true then
		if event.button == "Back" then
			searchstring = ""
			whee:SongSearch(searchstring)
			active = false
			MESSAGEMAN:Broadcast("EndingSearch")
		elseif event.button == "Start" or deviceButton == "DeviceButton_enter" then
			endSearch()
		elseif event.DeviceInput.button == "DeviceButton_space" then
			searchstring = searchstring .. " "
		elseif event.DeviceInput.button == "DeviceButton_backspace" then
			searchstring = searchstring:sub(1, -2)
		elseif event.DeviceInput.button == "DeviceButton_delete" then
			searchstring = ""
		else
			local CtrlPressed = INPUTFILTER:IsControlPressed()
			if event.DeviceInput.button == "DeviceButton_v" and CtrlPressed then
				searchstring = searchstring .. Arch.getClipboard()
			elseif event.char and event.char:match('[%%%+%-%!%@%#%$%^%&%*%(%)%=%_%.%,%:%;%\'%"%>%<%?%/%~%|%w%[%]%{%}%`%\\]') and (not tonumber(event.char) or CtrlPressed) then
				searchstring = searchstring .. event.char
			end
		end
		if lastsearchstring ~= searchstring then
			MESSAGEMAN:Broadcast("UpdateString")
			if instantSearch then
				whee:SongSearch(searchstring)
			end
			lastsearchstring = searchstring
		end
		return true
	end
end

local t = Def.ActorFrame {
	BeginCommand = function(self)
		whee = SCREENMAN:GetTopScreen():GetMusicWheel()
		SCREENMAN:GetTopScreen():AddInputCallback(searchInput)
	end,
	Def.Quad {
		InitCommand = function(self)
			self:xy(searchBarX, searchBarY):zoomto(searchBarWidth, searchBarHeight):halign(0):diffuse(color("#000000")):diffusealpha(0.5)
		end,
		SetDynamicAccentColorMessageCommand = function(self, params)
			self:finishtweening():linear(0.2):diffuse(params.color):diffusealpha(0.3)
		end
	},
	Def.ActorFrame {
		InitCommand = function(self)
			self:xy(SCREEN_WIDTH - 392, 70):zoom(0.45)
		end,
		Def.Sprite {
			Texture = THEME:GetPathG("", "Interlude Icons/magnifying-glass-solid.png"),
			InitCommand = function(self)
				self:halign(0.5):valign(0.5)
			end,
			OnCommand = function(self)
				normalizeInterludeIcon(self)
				self:playcommand("UpdateState")
			end,
			UpdateStringMessageCommand = function(self)
				self:playcommand("UpdateState")
			end,
			UpdateStateCommand = function(self)
				local _, iconColor = getSearchDisplayState()
				self:diffuse(iconColor)
			end
		}
	},
	LoadFont("Common Normal") .. {
		InitCommand = function(self)
			self:xy(SCREEN_WIDTH - 375, 70):zoom(0.4):halign(0)
		end,
		UpdateStringMessageCommand = function(self)
			local displayText, textColor = getSearchDisplayState()
			self:settext(displayText)
			self:diffuse(textColor)
		end,
		BeginCommand = function(self)
			self:playcommand("UpdateString")
		end
	}
}

return t
