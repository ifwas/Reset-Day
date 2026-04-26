if IsSMOnlineLoggedIn() then
	CloseConnection()
end

local t = Def.ActorFrame {}

local frameX = THEME:GetMetric("ScreenTitleMenu", "ScrollerX") - 10
local frameY = THEME:GetMetric("ScreenTitleMenu", "ScrollerY")
local titleMusicLoopToken = 0
local titleMusicSong = nil
local titleMusicStartPosition = 0
local titleMusicStartedAt = nil
local titleMusicPaused = false
local titleQuote = getRandomQuotes and getRandomQuotes(3) or ""

local function getTitleMenuSong()
	if MenuMusicState and MenuMusicState.GetMenuSong then
		local savedSong = MenuMusicState.GetMenuSong()
		if savedSong then
			return savedSong
		end
	end
	local allSongs = SONGMAN:GetAllSongs()
	if allSongs and #allSongs > 0 then
		if MenuMusicState and MenuMusicState.Save then
			MenuMusicState.Save(allSongs[1], 0, true)
		end
		return allSongs[1]
	end
	return nil
end

local function broadcastTitleAccent(colorValue)
	MESSAGEMAN:Broadcast("SetDynamicAccentColor", {color = colorValue or getMainColor("highlight")})
end

local function getSavedSamplePosition(song)
	if not song then return 0 end
	local saved = MenuMusicState and MenuMusicState.LoadSavedPosition and MenuMusicState.LoadSavedPosition() or 0
	local length = song:MusicLengthSeconds() or 0
	if length <= 0 then return 0 end
	if saved >= length then return 0 end
	return math.max(0, math.min(saved, length))
end

local function getCurrentTitlePlaybackPosition()
	if not titleMusicSong or not titleMusicStartedAt then
		return titleMusicStartPosition or 0
	end
	local length = titleMusicSong:MusicLengthSeconds() or 0
	local elapsed = math.max(0, os.clock() - titleMusicStartedAt)
	local pos = (titleMusicStartPosition or 0) + elapsed
	if length > 0 then
		pos = math.min(pos, length)
	end
	return pos
end

local function captureTitleMusicState()
	if MenuMusicState and MenuMusicState.Save and titleMusicSong then
		MenuMusicState.Save(titleMusicSong, getCurrentTitlePlaybackPosition(), true)
	end
end

local function stopTitleMusicLoop()
	titleMusicLoopToken = titleMusicLoopToken + 1
	captureTitleMusicState()
	titleMusicStartedAt = nil
end

local function getNextTitleMenuSong(currentSong)
	local allSongs = SONGMAN:GetAllSongs()
	if not allSongs or #allSongs == 0 then return nil end
	if not currentSong then
		return allSongs[1]
	end
	for i, song in ipairs(allSongs) do
		if song == currentSong then
			return allSongs[(i % #allSongs) + 1]
		end
	end
	return allSongs[1]
end

local function playTitleMusic(song, startPosition)
	if not song then return end
	local musicPath = song:GetMusicPath()
	local length = song:MusicLengthSeconds() or 0
	if not musicPath or musicPath == "" or length <= 0 then return end
	startPosition = math.max(0, math.min(startPosition or 0, length))
	if startPosition >= length then
		startPosition = 0
	end
	titleMusicSong = song
	titleMusicStartPosition = startPosition
	titleMusicStartedAt = os.clock()
	titleMusicPaused = false
	local token = titleMusicLoopToken
	SOUND:StopMusic()
	SOUND:PlayMusicPart(musicPath, startPosition, math.max(length - startPosition, 0))
	if MenuMusicState and MenuMusicState.Save then
		MenuMusicState.Save(song, startPosition, true)
	end
	local top = SCREENMAN:GetTopScreen()
	if top and top.setTimeout then
		top:setTimeout(function()
			if token ~= titleMusicLoopToken then return end
			local nextSong = getNextTitleMenuSong(song)
			if nextSong and MenuMusicState and MenuMusicState.Save then
				MenuMusicState.Save(nextSong, 0)
			end
		end, math.max(length - startPosition, 0))
	end
end

TitleMenuMusicState = {
	TogglePause = function()
		local song = titleMusicSong or getTitleMenuSong()
		if not song then return false end
		if titleMusicPaused then
			playTitleMusic(song, getCurrentTitlePlaybackPosition())
		else
			stopTitleMusicLoop()
			SOUND:StopMusic()
			titleMusicPaused = true
		end
		return true
	end,
	IsPaused = function()
		return titleMusicPaused
	end,
}

local function applyMetricChoice(choiceMetricName)
	GAMESTATE:ApplyGameCommand(THEME:GetMetric("ScreenTitleMenu", choiceMetricName))
end

local function utilityButton(x, label, choiceMetricName)
	return Def.ActorFrame {
		InitCommand = function(self)
			self:xy(x, 0)
		end,
		UIElements.QuadButton(1, 1) .. {
			InitCommand = function(self)
				self:halign(0):valign(0.5):zoomto(132, 40):diffuse(color("#000000")):diffusealpha(0.38)
			end,
			MouseOverCommand = function(self)
				self:stoptweening():linear(0.1):diffusealpha(0.58)
			end,
			MouseOutCommand = function(self)
				self:stoptweening():linear(0.1):diffusealpha(0.38)
			end,
			MouseDownCommand = function(self, params)
				if params.event == "DeviceButton_left mouse button" then
					applyMetricChoice(choiceMetricName)
				end
			end
		},
		Def.Quad {
			InitCommand = function(self)
				self:halign(0):valign(0.5):zoomto(132, 40):diffuse(getMainColor("frames")):diffusealpha(0.42)
			end,
			SetDynamicAccentColorMessageCommand = function(self, params)
				self:finishtweening():linear(0.2):diffuse(params.color):diffusealpha(0.42)
			end
		},
		LoadFont("Common Normal") .. {
			InitCommand = function(self)
				self:xy(66, 0):halign(0.5):zoom(0.5):settext(label)
			end,
			MouseOverCommand = function(self)
				self:diffusealpha(0.75)
			end,
			MouseOutCommand = function(self)
				self:diffusealpha(1)
			end,
			MouseDownCommand = function(self, params)
				if params.event == "DeviceButton_left mouse button" then
					applyMetricChoice(choiceMetricName)
				end
			end
		}
	}
end

--Left gray rectangle
t[#t + 1] = Def.Quad {
	InitCommand = function(self)
		self:xy(0, 0):halign(0):valign(0):zoomto(SCREEN_WIDTH, SCREEN_HEIGHT):diffuse(color("#080A12")):diffusealpha(1)
	end
}

--Right gray rectangle
t[#t + 1] = Def.Quad {
	InitCommand = function(self)
		self:xy(0, 52):halign(0):valign(0):zoomto(SCREEN_WIDTH, SCREEN_HEIGHT - 104):diffuse(getMainColor("highlight")):diffusealpha(0.12)
	end,
	SetDynamicAccentColorMessageCommand = function(self, params)
		self:finishtweening():linear(0.2):diffuse(params.color):diffusealpha(0.12)
	end
}

--Light purple line
t[#t + 1] = Def.Quad {
	InitCommand = function(self)
		self:xy(0, SCREEN_CENTER_Y - 118):halign(0):valign(0):zoomto(SCREEN_WIDTH, 236):diffuse(color("#FFFFFF")):diffusealpha(0.05)
	end,
	SetDynamicAccentColorMessageCommand = function(self, params)
		self:finishtweening():linear(0.2):diffuse(params.color):diffusealpha(0.08)
	end
}

--Dark purple line
t[#t + 1] = Def.Quad {
	InitCommand = function(self)
		self:xy(0, SCREEN_CENTER_Y - 80):halign(0):valign(0):zoomto(SCREEN_WIDTH, 160):diffuse(color("#000000")):diffusealpha(0.18)
	end
}

t[#t + 1] = LoadActor(THEME:GetPathG("", "logo")) .. {
	Name = "TitleLogo",
	InitCommand = function(self)
		self:xy(150, SCREEN_CENTER_Y):zoomto(220, 220)
	end
}

t[#t + 1] = Def.ActorFrame {
	Name = "TitleQuote",
	InitCommand = function(self)
		self:xy(SCREEN_CENTER_X, 92)
	end,
	Def.Quad {
		InitCommand = function(self)
			self:zoomto(610, 34):diffuse(color("#000000")):diffusealpha(0.32)
		end
	},
	Def.Quad {
		InitCommand = function(self)
			self:zoomto(610, 34):diffuse(getMainColor("frames")):diffusealpha(0.22)
		end,
		SetDynamicAccentColorMessageCommand = function(self, params)
			self:finishtweening():linear(0.2):diffuse(params.color):diffusealpha(0.22)
		end
	},
	LoadFont("Common Large") .. {
		Name = "QuoteText",
		InitCommand = function(self)
			self:zoom(0.48):maxwidth(1180):settext(titleQuote)
			self:diffuse(color("#FFFFFF"))
		end,
		SetCommand = function(self)
			local parent = self:GetParent()
			local currentSong = getTitleMenuSong()
			local lastSong = parent and parent.GetAttribute and parent:GetAttribute("LastQuoteSong") or nil
			if currentSong ~= lastSong then
				titleQuote = getRandomQuotes and getRandomQuotes(3) or ""
				if parent and parent.SetAttribute then
					parent:SetAttribute("LastQuoteSong", currentSong)
				end
			end
			self:settext(titleQuote)
		end,
		BeginCommand = function(self)
			self:playcommand("Set")
		end,
		MenuMusicStateChangedMessageCommand = function(self)
			self:playcommand("Set")
		end
	}
}

t[#t + 1] = Def.Sprite {
	Name = "SongBackground",
	InitCommand = function(self)
		self:diffusealpha(0)
	end,
	BeginCommand = function(self)
		self:queuecommand("Refresh")
	end,
	RefreshCommand = function(self)
		local song = getTitleMenuSong()
		if song and song:GetBackgroundPath() then
			self:visible(true)
			self:finishtweening()
			self:LoadBackground(song:GetBackgroundPath())
			self:scaletocover(0, 0, SCREEN_WIDTH, SCREEN_BOTTOM)
			self:smooth(0.3):diffusealpha(0.28)
			if self:GetTexture() then
				broadcastTitleAccent(self:GetTexture():GetAverageColor(14))
			else
				broadcastTitleAccent()
			end
		else
			self:visible(false)
			broadcastTitleAccent()
		end
	end,
	MenuMusicStateChangedMessageCommand = function(self)
		self:queuecommand("Refresh")
	end,
	OffCommand = function(self)
		self:stoptweening():linear(0.2):diffusealpha(0)
	end
}

local playingMusic = {}
local playingMusicCounter = 1

local function applyTitleChoice(choice)
	SCREENMAN:GetTopScreen():playcommand("MadeChoicePlayer_1")
	SCREENMAN:GetTopScreen():playcommand("Choose")
	if choice == "Multi" or choice == "GameStart" then
		GAMESTATE:JoinPlayer()
	end
	GAMESTATE:ApplyGameCommand(THEME:GetMetric("ScreenTitleMenu", "Choice" .. choice))
end

--Title text
t[#t + 1] = UIElements.TextToolTip(1, 1, "Common Large") .. {
	InitCommand=function(self)
		self:xy(125,frameY-82):zoom(0.7):align(0.5,1)
		self:diffusetopedge(Saturation(getMainColor("highlight"), 0.5))
		self:diffusebottomedge(Saturation(getMainColor("positive"), 0.8))
	end,
	OnCommand=function(self)
		self:settext("")
		self:visible(false)
	end,
	MouseOverCommand = function(self)
		self:diffusealpha(0.6)
	end,
	MouseOutCommand = function(self)
		self:diffusealpha(1)
	end,
}

--Theme text
t[#t + 1] = LoadFont("Common Large") .. {
	InitCommand=function(self)
		self:xy(125,frameY-52):zoom(0.325):align(0.5,1)
		self:diffusetopedge(Saturation(getMainColor("highlight"), 0.5))
		self:diffusebottomedge(Saturation(getMainColor("positive"), 0.8))
	end,
	OnCommand=function(self)
		self:settext("")
		self:visible(false)
	end
}

--Version number
t[#t + 1] = UIElements.TextToolTip(1, 1, "Common Large") .. {
	Name = "Version",
	InitCommand=function(self)
		self:xy(125,frameY-35):zoom(0.25):align(0.5,1)
		self:diffusetopedge(Saturation(getMainColor("highlight"), 0.5))
		self:diffusebottomedge(Saturation(getMainColor("positive"), 0.8))
	end,
	BeginCommand = function(self)
		self:settext("")
		self:visible(false)
	end,
	MouseDownCommand = function(self, params)
		if params.event == "DeviceButton_left mouse button" then
			DLMAN:ShowProjectReleases()
		end
	end
}

--game update button
local gameneedsupdating = false
local buttons = {x = 20, y = 20, width = 142, height = 42, fontScale = 0.35, color = getMainColor("frames")}
t[#t + 1] = Def.ActorFrame {
	BeginCommand = function(self)
		local song = getTitleMenuSong()
		if song then
			local startPosition = getSavedSamplePosition(song)
			if MenuMusicState and MenuMusicState.Save then
				MenuMusicState.Save(song, startPosition, true)
			end
			playTitleMusic(song, startPosition)
		end
	end,
	EndCommand = function(self)
		TitleMenuMusicState = nil
		stopTitleMusicLoop()
	end,
	MenuMusicStateChangedMessageCommand = function(self)
		local song = getTitleMenuSong()
		if song and (song ~= titleMusicSong or not titleMusicStartedAt) then
			local startPosition = getSavedSamplePosition(song)
			stopTitleMusicLoop()
			playTitleMusic(song, startPosition)
		end
	end,
	InitCommand = function(self)
		self:xy(buttons.x,buttons.y)
	end,
	UIElements.QuadButton(1, 1) .. {
		InitCommand = function(self)
			self:zoomto(buttons.width, buttons.height):halign(0):valign(0):diffuse(buttons.color):diffusealpha(0)
			self:playcommand("LastVersionUpdated")
		end,
		LastVersionUpdatedMessageCommand = function(self)
			local latest = tonumber((DLMAN:GetLastVersion():gsub("[.]", "", 1)))
			local current = tonumber((GAMESTATE:GetEtternaVersion():gsub("[.]", "", 1)))
			if latest and latest > current then
				gameneedsupdating = true
			end
			self:playcommand("On")
		end,
		OnCommand = function(self)
			if gameneedsupdating then
				self:diffusealpha(0.3)
			end
		end,
		MouseDownCommand = function(self, params)
			if params.event == "DeviceButton_left mouse button" and gameneedsupdating then
				DLMAN:ShowProjectReleases()
			end
		end
	},
	LoadFont("Common Large") .. {
		OnCommand = function(self)
			self:xy(1.7, 1):align(0,0):zoom(buttons.fontScale):diffuse(getMainColor("positive"))
			if gameneedsupdating then
				self:settext(THEME:GetString("ScreenTitleMenu", "UpdateAvailable"))
			else
				self:settext("")
			end
		end
	}
}

t[#t + 1] = Def.ActorFrame {
	Name = "TitleMenuUtilities",
	InitCommand = function(self)
		self:xy(SCREEN_WIDTH - 432, SCREEN_HEIGHT - 58)
	end,
	utilityButton(0, "Report a Bug", "ChoiceReportABug"),
	utilityButton(144, "Editor", "ChoiceAV"),
	utilityButton(288, "GitHub", "ChoiceGitHub")
}

local function mysplit(inputstr, sep)
	if sep == nil then
		sep = "%s"
	end
	local t = {}
	i = 1
	for str in string.gmatch(inputstr, "([^" .. sep .. "]+)") do
		t[i] = str
		i = i + 1
	end
	return t
end

t[#t + 1] = LoadActor(THEME:GetPathB("", "_frame"))
t[#t + 1] = LoadActor(THEME:GetPathB("", "_PlayerInfo"))

return t
