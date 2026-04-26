local profile = PROFILEMAN:GetProfile(PLAYER_1)
local frameX = 20
local frameY = 280
local frameWidth = capWideScale(get43size(400), 400)
local score
local song
local steps
local noteField = false
local infoOnScreen = false
local heyiwasusingthat = false
local mcbootlarder
local pOptions = GAMESTATE:GetPlayerState():GetCurrentPlayerOptions()
local usingreverse = pOptions:UsingReverse()
local prevX = capWideScale(get43size(98), 98)
local prevY = 55
local prevrevY = 60
local boolthatgetssettotrueonsongchangebutonlyifonatabthatisntthisone = false
local hackysack = false
local songChanged = false
local songChanged2 = false
local previewVisible = false
local onlyChangedSteps = false
local shouldPlayMusic = false
local prevtab = 0
local ctags = {}
local previewLoopToken = 0
local pendingPreviewSeekPosition = nil
local pendingPreviewSeekSong = nil

local interludeIconTargetSize = 48
local dropdownDrawOrder = 10000
local bottomButtonY = SCREEN_BOTTOM - 58
local bottomButtonIconSize = 32
local bottomButtonIconTextGap = 6
local bottomButtonPositions = {
	Collection = SCREEN_WIDTH - 355,
	Random = SCREEN_WIDTH - 235,
	Practice = SCREEN_WIDTH - 125,
	Play = SCREEN_WIDTH - 55,
}

local itsOn = false

local translated_info = {
	GoalTarget = THEME:GetString("ScreenSelectMusic", "GoalTargetString"),
	MaxCombo = THEME:GetString("ScreenSelectMusic", "MaxCombo"),
	BPM = THEME:GetString("ScreenSelectMusic", "BPM"),
	NegBPM = THEME:GetString("ScreenSelectMusic", "NegativeBPM"),
	UnForceStart = THEME:GetString("GeneralInfo", "UnforceStart"),
	ForceStart = THEME:GetString("GeneralInfo", "ForceStart"),
	Unready = THEME:GetString("GeneralInfo", "Unready"),
	Ready = THEME:GetString("GeneralInfo", "Ready"),
	TogglePreview = THEME:GetString("ScreenSelectMusic", "TogglePreview"),
	PlayerOptions = THEME:GetString("ScreenSelectMusic", "PlayerOptions"),
}

local function stopPreviewLoop()
	previewLoopToken = previewLoopToken + 1
	pendingPreviewSeekPosition = nil
	pendingPreviewSeekSong = nil
end

local function applyPendingPreviewSeek()
	local top = SCREENMAN:GetTopScreen()
	if not top or not top.SetSampleMusicPosition then return end
	if pendingPreviewSeekPosition == nil then return end
	if pendingPreviewSeekSong and GAMESTATE:GetCurrentSong() ~= pendingPreviewSeekSong then
		pendingPreviewSeekPosition = nil
		pendingPreviewSeekSong = nil
		return
	end
	top:SetSampleMusicPosition(pendingPreviewSeekPosition)
	pendingPreviewSeekPosition = nil
	pendingPreviewSeekSong = nil
end

local function getPreviewStartSeconds(song)
	if not song then return 0 end
	local candidates = {
		function() return song:GetSampleStart() end,
		function() return song:GetSampleStartSeconds() end,
		function() return song:GetMusicSampleStartSeconds() end,
		function() return song:GetPreviewStartSeconds() end,
	}
	for _, candidate in ipairs(candidates) do
		local ok, value = pcall(candidate)
		if ok and type(value) == "number" and value >= 0 then
			return value
		end
	end
	return 0
end

local function playPreviewMusicPart(song, startSeconds)
	if not song then return 0 end
	local musicPath = song:GetMusicPath()
	local songLength = song:MusicLengthSeconds()
	if not musicPath or musicPath == "" or not songLength or songLength <= 0 then
		return 0
	end
	startSeconds = math.max(0, math.min(startSeconds or 0, songLength))
	local playLength = math.max(songLength - startSeconds, 0)
	if playLength <= 0 then return 0 end
	SOUND:StopMusic()
	SOUND:PlayMusicPart(musicPath, startSeconds, playLength)
	MESSAGEMAN:Broadcast("PreviewMusicStarted")
	return playLength
end

local function schedulePreviewLoop(song, token, delay, restartAtBeginning)
	local top = SCREENMAN:GetTopScreen()
	if not top or not top.setTimeout or delay <= 0 then return end
	top:setTimeout(function()
		if previewLoopToken ~= token then return end
		if not previewVisible then return end
		if GAMESTATE:GetCurrentSong() ~= song then return end
		local startSeconds = restartAtBeginning and 0 or getPreviewStartSeconds(song)
		local nextDelay = playPreviewMusicPart(song, startSeconds)
		if nextDelay > 0 then
			schedulePreviewLoop(song, token, nextDelay, true)
		end
	end, delay)
end

local function playMusicForPreview(song, startSeconds)
	stopPreviewLoop()
	if type(startSeconds) ~= "number" then
		startSeconds = getPreviewStartSeconds(song)
	end
	local top = SCREENMAN:GetTopScreen()
	if top and top.PlayCurrentSongSampleMusic then
		SOUND:StopMusic()
		pendingPreviewSeekPosition = startSeconds
		pendingPreviewSeekSong = song
		top:PlayCurrentSongSampleMusic(true, true)
		MESSAGEMAN:Broadcast("PreviewMusicStarted")
	else
		local token = previewLoopToken
		local initialDelay = playPreviewMusicPart(song, startSeconds)
		if initialDelay > 0 then
			schedulePreviewLoop(song, token, initialDelay, true)
		else
			SOUND:StopMusic()
			MESSAGEMAN:Broadcast("PreviewMusicStarted")
		end
	end

	restartedMusic = true

	-- use this opportunity to set all the random booleans to make it consistent
	songChanged = false
	boolthatgetssettotrueonsongchangebutonlyifonatabthatisntthisone = false
	hackysack = false
end

-- to toggle calc info display stuff
local function toggleCalcInfo(state)
	infoOnScreen = state

	if infoOnScreen then
		MESSAGEMAN:Broadcast("CalcInfoOn")
	else
		MESSAGEMAN:Broadcast("CalcInfoOff")
	end
end

local hoverAlpha = 0.8
local hoverAlpha2 = 0.6

local function normalizeInterludeIcon(self, visualScale)
	local width = self:GetWidth()
	local height = self:GetHeight()
	if width > 0 and height > 0 then
		self:zoom((interludeIconTargetSize / math.max(width, height)) * (visualScale or 1))
	end
end

-- to reduce repetitive code for setting preview visibility with booleans
local function setPreviewPartsState(state)
	if state == nil then return end
	mcbootlarder:visible(state)
	mcbootlarder:GetChild("NoteField"):visible(state)
	heyiwasusingthat = not state
	previewVisible = state
	if not state then
		stopPreviewLoop()
	end
	if state ~= infoOnScreen and not state then
		toggleCalcInfo(false)
	end
end

local function getRelativeTime(dateStr)
	if not dateStr or dateStr == "" then return "" end
	local y, m, d, h, min, s = dateStr:match("(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+)")
	if not y then return dateStr end
	local t = os.time({year=y, month=m, day=d, hour=h, min=min, sec=s})
	local diff = os.time() - t
	if diff < 60 then return "just now"
	elseif diff < 3600 then return math.floor(diff/60) .. "m ago"
	elseif diff < 86400 then return math.floor(diff/3600) .. "h ago"
	elseif diff < 2592000 then return math.floor(diff/86400) .. "d ago"
	elseif diff < 31536000 then return math.floor(diff/2592000) .. "mo ago"
	else return math.floor(diff/31536000) .. "y ago" end
end

local function getScoreDateRelative(score)
	if not score then return "" end
	return getRelativeTime(score:GetDate())
end

local function getJudgeLabel(score)
	if not score then return "J4" end
	local j = table.find(ms.JudgeScalers, notShit.round(score:GetJudgeScale(), 2))
	if not j then j = 4 end
	if j < 4 then j = 4 end
	return "J" .. j
end

local function getAverageOfNumberList(values)
	if not values or #values == 0 then return nil end
	local sum = 0
	local count = 0
	for _, value in ipairs(values) do
		if value ~= nil and value == value and value ~= math.huge and value ~= -math.huge then
			sum = sum + value
			count = count + 1
		end
	end
	if count == 0 then return nil end
	return sum / count
end

local skillsetPatternModIndexByName = {
	Stream = 1,
	Jumpstream = 2,
	Handstream = 3,
	Chordjack = 4,
	ChordJack = 4,
	Technical = 5,
}

local skillsetBaseKeyByName = {
	Stream = "NPSBase",
	Jumpstream = "NPSBase",
	Handstream = "NPSBase",
	Chordjack = "CJBase",
	ChordJack = "CJBase",
	Technical = "TechBase",
}

local skillsetBpmScaleByName = {
	Stream = 15,
	Jumpstream = 15,
	Handstream = 15,
	Chordjack = 15,
	ChordJack = 15,
	Technical = 15,
}

local function getSkillsetValueAtRate(steps, rate, skillsetName)
	local ok, value = pcall(function()
		if skillsetName == "Overall" then
			return steps:GetMSD(rate, 1)
		elseif skillsetName == "Stream" then
			return steps:GetMSD(rate, 2)
		elseif skillsetName == "Jumpstream" then
			return steps:GetMSD(rate, 3)
		elseif skillsetName == "Handstream" then
			return steps:GetMSD(rate, 4)
		elseif skillsetName == "Stamina" then
			return steps:GetMSD(rate, 5)
		elseif skillsetName == "JackSpeed" then
			return steps:GetMSD(rate, 6)
		elseif skillsetName == "Chordjack" or skillsetName == "ChordJack" then
			return steps:GetMSD(rate, 7)
		elseif skillsetName == "Technical" then
			return steps:GetMSD(rate, 8)
		end
		return nil
	end)
	if ok and value and value > 0 then return value end
	return nil
end

local function getOrderedRelevantSkillsets(steps, rate)
	if not steps then return {} end
	local scored = {}
	for _, skillsetName in ipairs(ms.SkillSets) do
		if skillsetName ~= "Overall" then
			local value = getSkillsetValueAtRate(steps, rate, skillsetName)
			if value then
				scored[#scored + 1] = {name = skillsetName, value = value}
			end
		end
	end
	table.sort(scored, function(a, b) return a.value > b.value end)
	local ordered = {}
	for _, entry in ipairs(scored) do
		ordered[#ordered + 1] = entry.name
	end
	return ordered
end

local function getDominantSkillsets(steps, rate, maxCount)
	if not steps then return {} end
	local ordered = getOrderedRelevantSkillsets(steps, rate)
	if #ordered == 0 then return {} end
	local results = {}
	local topSkillset = ordered[1]
	local suppressSecondary = {
		Technical = true,
		Stamina = true,
	}
	for _, skillsetName in ipairs(ordered) do
		if skillsetName ~= "Overall" then
			local allow = true
			if suppressSecondary[skillsetName] and skillsetName ~= topSkillset then
				allow = false
			end
			if allow then
				results[#results + 1] = skillsetName
				if #results >= maxCount then break end
			end
		end
	end
	return results
end

local function getPrimarySkillsetLabel(steps)
	if not steps then return "Uncategorised" end
	local rate = getCurRateValue()
	local dominant = getDominantSkillsets(steps, rate, 1)
	if #dominant == 0 then return "Uncategorised" end
	return ms.SkillSetsTranslatedByName[dominant[1]] or dominant[1]
end

local function getPatternBpmForSkillset(steps, rate, skillsetName)
	if not steps then return nil end
	local patternIndex = skillsetPatternModIndexByName[skillsetName]
	local baseKey = skillsetBaseKeyByName[skillsetName] or "NPSBase"
	local bpmScale = skillsetBpmScaleByName[skillsetName] or 15
	if not patternIndex then return nil end
	local okOut, calcOut = pcall(function()
		return steps:GetCalcDebugOutput()
	end)
	local okExt, calcExt = pcall(function()
		return steps:GetCalcDebugExt()
	end)
	if not okOut or not okExt or calcOut == nil or calcExt == nil then return nil end
	local diffValues = calcOut["CalcDiffValue"]
	local patternMods = calcExt["DebugTotalPatternMod"]
	local baseValues = diffValues and diffValues[baseKey]
	if baseValues == nil and baseKey ~= "NPSBase" then
		baseValues = diffValues and diffValues["NPSBase"]
	end
	if diffValues == nil or patternMods == nil or baseValues == nil then return nil end
	local baseLeft = getAverageOfNumberList(baseValues[1])
	local baseRight = getAverageOfNumberList(baseValues[2])
	local baseNps = 0
	local baseCount = 0
	if baseLeft then
		baseNps = baseNps + baseLeft
		baseCount = baseCount + 1
	end
	if baseRight then
		baseNps = baseNps + baseRight
		baseCount = baseCount + 1
	end
	if baseCount == 0 then return nil end
	baseNps = (baseNps / baseCount) * rate
	local patternLeft = patternMods["Left"] and patternMods["Left"][patternIndex]
	local patternRight = patternMods["Right"] and patternMods["Right"][patternIndex]
	local modLeft = getAverageOfNumberList(patternLeft)
	local modRight = getAverageOfNumberList(patternRight)
	local patternMod = 0
	local modCount = 0
	if modLeft then
		patternMod = patternMod + modLeft
		modCount = modCount + 1
	end
	if modRight then
		patternMod = patternMod + modRight
		modCount = modCount + 1
	end
	if modCount == 0 then return nil end
	patternMod = patternMod / modCount
	return math.floor((baseNps * patternMod * bpmScale) + 0.5)
end

local function getMinaPatternBpmBreakdown(steps)
	if not steps then return "" end
	local rate = getCurRateValue()
	local dominant = getDominantSkillsets(steps, rate, 2)
	if #dominant == 0 then return "" end
	local parts = {}
	for _, skillsetName in ipairs(dominant) do
		local bpm = getPatternBpmForSkillset(steps, rate, skillsetName)
		if bpm then
			local translated = ms.SkillSetsTranslatedByName[skillsetName] or skillsetName
			parts[#parts + 1] = string.format("%d BPM %s", bpm, translated)
		end
	end
	return table.concat(parts, ", ")
end

local function toggleNoteField()
	local nf = mcbootlarder:GetChild("NoteField")
	if song and not noteField then -- first time setup
		noteField = true
		MESSAGEMAN:Broadcast("ChartPreviewOn") -- for banner reaction... lazy -mina
		mcbootlarder:playcommand("SetupNoteField")
		mcbootlarder:xy(prevX, prevY)
		mcbootlarder:diffusealpha(1)

		pOptions = GAMESTATE:GetPlayerState():GetCurrentPlayerOptions()
		usingreverse = pOptions:UsingReverse()
		local usingscrollmod = false
		if pOptions:Split() ~= 0 or pOptions:Alternate() ~= 0 or pOptions:Cross() ~= 0 or pOptions:Centered() ~= 0 then
			usingscrollmod = true
		end

		nf:y(prevY * 2.85)
		if usingscrollmod then
			nf:y(prevY * 3.55)
		elseif usingreverse then
			nf:y(prevY * 2.85 + prevrevY)
		end

		if not songChanged then
			playMusicForPreview(song)
			tryingToStart = true
		else
			tryingToStart = false
		end
		songChanged = false
		hackysack = false
		previewVisible = true
		return true
	end

	if song then
		nf:diffusealpha(1)
		if mcbootlarder:IsVisible() then
			mcbootlarder:visible(false)
			nf:visible(false)
			MESSAGEMAN:Broadcast("ChartPreviewOff")
			toggleCalcInfo(false)
			previewVisible = false
			hackysack = changingSongs
			changingSongs = false
			return false
		else
			mcbootlarder:visible(true)
			nf:visible(true)
			if boolthatgetssettotrueonsongchangebutonlyifonatabthatisntthisone or songChanged or songChanged2 then
				if not restartedMusic then
					playMusicForPreview(song)
				end
				boolthatgetssettotrueonsongchangebutonlyifonatabthatisntthisone = false
				hackysack = false
				songChanged = false
				songChanged2 = false
			end
			MESSAGEMAN:Broadcast("ChartPreviewOn")
			previewVisible = true
			return true
		end
	end
	return false
end

local mintyFreshIntervalFunction = nil
local update = false
local t = Def.ActorFrame {
	Name = "wifetwirler",
	BeginCommand = function(self)
		self:draworder(dropdownDrawOrder)
		self:SortByDrawOrder()
		self:queuecommand("MintyFresh")
	end,
	OffCommand = function(self)
		self:bouncebegin(0.2):xy(-500, 0):diffusealpha(0)
		stopPreviewLoop()
		toggleCalcInfo(false)
		self:sleep(0.04):queuecommand("Invis")
	end,
	InvisCommand= function(self)
		self:visible(false)
	end,
	OnCommand = function(self)
		self:bouncebegin(0.2):xy(0, 0):diffusealpha(1)
	end,
	CurrentSongChangedMessageCommand = function()
		stopPreviewLoop()
		-- This will disable mirror when switching songs if OneShotMirror is enabled or if permamirror is flagged on the chart (it is enabled if so in screengameplayunderlay/default)
		if playerConfig:get_data(pn_to_profile_slot(PLAYER_1)).OneShotMirror or profile:IsCurrentChartPermamirror() then
			local modslevel = topscreen == "ScreenEditOptions" and "ModsLevel_Stage" or "ModsLevel_Preferred"
			local playeroptions = GAMESTATE:GetPlayerState():GetPlayerOptions(modslevel)
			playeroptions:Mirror(false)
		end
		-- if not on General and we started the noteField and we changed tabs then changed songs
		-- this means the music should be set again as long as the preview is still "on" but off screen
		if getTabIndex() ~= 0 and noteField and heyiwasusingthat then
			boolthatgetssettotrueonsongchangebutonlyifonatabthatisntthisone = true
		end

		-- if the preview was turned on ever but is currently not on screen as the song changes
		-- this goes hand in hand with the above boolean
		if noteField and not previewVisible then
			songChanged = true
		end

		-- check to see if the song actually really changed
		-- >:(
		if noteField and GAMESTATE:GetCurrentSong() ~= song then
			-- always true if switching songs and preview has ever been opened
			songChanged2 = true
			restartedMusic = false
		else
			songChanged2 = false
		end

		-- an awkwardly named bool describing the fact that we just changed songs
		-- used in notefield creation function to see if we should restart music
		-- it is immediately turned off when toggling notefield
		changingSongs = true
		tryingToStart = false

		-- if switching songs, we want the notedata to disappear temporarily
		if noteField and songChanged2 and previewVisible then
			mcbootlarder:GetChild("NoteField"):finishtweening()
			mcbootlarder:GetChild("NoteField"):diffusealpha(0)
		end
	end,
	DelayedChartUpdateMessageCommand = function(self)
		-- wait for the music wheel to settle before playing the music
		-- to keep things very slightly more easy to deal with
		-- and reduce a tiny bit of lag
		local s = GAMESTATE:GetCurrentSong()
		local unexpectedlyChangedSong = s ~= song

		shouldPlayMusic = false
		-- should play the music because the notefield is visible
		shouldPlayMusic = shouldPlayMusic or (noteField and mcbootlarder:GetChild("NoteField") and mcbootlarder:GetChild("NoteField"):IsVisible())
		-- should play the music if we switched songs while on a different tab
		shouldPlayMusic = shouldPlayMusic or boolthatgetssettotrueonsongchangebutonlyifonatabthatisntthisone
		-- should play the music if we switched to a song from a pack tab
		-- also applies for if we just toggled the notefield or changed screen tabs
		shouldPlayMusic = shouldPlayMusic or hackysack
		-- should play the music if we already should and we either jumped song or we didnt change the song
		shouldPlayMusic = shouldPlayMusic and (not onlyChangedSteps or unexpectedlyChangedSong) and not tryingToStart

		-- at this point the music will or will not play ....

		boolthatgetssettotrueonsongchangebutonlyifonatabthatisntthisone = false
		hackysack = false
		tryingToStart = false
		songChanged = false
		onlyChangedSteps = true
	end,
	PlayingSampleMusicMessageCommand = function(self)
		-- delay setting the music for preview up until after the sample music starts (smoothness)
		if pendingPreviewSeekPosition ~= nil then
			local top = SCREENMAN:GetTopScreen()
			if top and top.setTimeout then
				top:setTimeout(function()
					applyPendingPreviewSeek()
				end, 0.01)
			else
				applyPendingPreviewSeek()
			end
		elseif shouldPlayMusic then
			shouldPlayMusic = false
			local s = GAMESTATE:GetCurrentSong()
			if s then
				if mcbootlarder and mcbootlarder:GetChild("NoteField") then mcbootlarder:GetChild("NoteField"):diffusealpha(1) end
				playMusicForPreview(s)
			end
		end
	end,
	MintyFreshCommand = function(self)
		self:finishtweening()
		local bong = GAMESTATE:GetCurrentSong()
		-- if not on a song and preview is on, hide it (dont turn it off)
		if not bong and noteField and mcbootlarder:IsVisible() then
			setPreviewPartsState(false)
			MESSAGEMAN:Broadcast("ChartPreviewOff")
		end

		-- if the song changed
		if song ~= bong then
			if not lockbools then
				onlyChangedSteps = false
			end
			if not song and previewVisible and not lockbools then
				hackysack = true -- used in cases when moving from null song (pack hover) to a song (this fixes searching and preview not working)
			end
			song = bong
			self:queuecommand("MortyFarts")
		else
			if not lockbools and not songChanged2 then
				onlyChangedSteps = true
			end
		end

		-- on general tab
		if getTabIndex() == 0 then
			-- if preview was on and should be made visible again
			if heyiwasusingthat and bong and noteField then
				setPreviewPartsState(true)
				MESSAGEMAN:Broadcast("ChartPreviewOn")
			elseif bong and noteField and previewVisible then
				-- make sure that it is visible even if it isnt, when it should be
				-- (haha lets call this 1000000 times nothing could go wrong)
				setPreviewPartsState(true)
			end

			self:visible(true)
			self:queuecommand("On")
			update = true
		else
			-- changing tabs off of general with preview on, hide the preview
			if bong and noteField and mcbootlarder:IsVisible() then
				setPreviewPartsState(false)
				MESSAGEMAN:Broadcast("ChartPreviewOff")
			end

			self:queuecommand("Off")
			update = false
		end
		lockbools = false
	end,
	TabChangedMessageCommand = function(self)
		local newtab = getTabIndex()
		if newtab ~= prevtab then
			self:queuecommand("MintyFresh")
			prevtab = newtab
			if getTabIndex() == 0 and noteField then
				mcbootlarder:GetChild("NoteField"):diffusealpha(1)
				lockbools = true
			elseif getTabIndex() ~= 0 and noteField then
				hackysack = mcbootlarder:IsVisible()
				onlyChangedSteps = false
				boolthatgetssettotrueonsongchangebutonlyifonatabthatisntthisone = false
				lockbools = true
			end
		end
	end,
	MilkyTartsCommand = function(self) -- when entering pack screenselectmusic explicitly turns visibilty on notefield off -mina
		if noteField and mcbootlarder:IsVisible() then
			toggleCalcInfo(false)
		end
	end,
	CurrentStepsChangedMessageCommand = function(self)
		-- this basically queues MintyFresh every 0.5 seconds but only once and also resets the 0.5 seconds
		-- if you scroll again
		-- so if you scroll really fast it doesnt pop at all until you slow down
		-- lag begone
		local topscr = SCREENMAN:GetTopScreen()

		if mintyFreshIntervalFunction ~= nil then
			topscr:clearInterval(mintyFreshIntervalFunction)
			mintyFreshIntervalFunction = nil
		end
		mintyFreshIntervalFunction = topscr:setInterval(function()
			self:queuecommand("MintyFresh")
			if mintyFreshIntervalFunction ~= nil then
				topscr:clearInterval(mintyFreshIntervalFunction)
				mintyFreshIntervalFunction = nil
			end
		end,
		0.05)
	end,
	CurrentRateChangedMessageCommand = function(self)
		if mintyFreshIntervalFunction ~= nil then
			local topscr = SCREENMAN:GetTopScreen()
			if topscr then
				topscr:clearInterval(mintyFreshIntervalFunction)
			end
			mintyFreshIntervalFunction = nil
		end
		pendingPreviewSeekPosition = nil
		pendingPreviewSeekSong = nil
		shouldPlayMusic = false
		self:playcommand("MintyFresh")
	end,
}

local breakdown
local primarySkill

-- State update helper (crucial for InfoDisplayPanel)
t[#t + 1] = Def.ActorFrame {
	MintyFreshCommand = function(self)
		song = GAMESTATE:GetCurrentSong()
		if song then
			score = GetDisplayScore()
			steps = GAMESTATE:GetCurrentSteps()

			if GAMESTATE:GetCurrentStyle():ColumnsPerPlayer() == 4 then 
				breakdown = getMinaPatternBpmBreakdown(steps)
				primarySkill = getPrimarySkillsetLabel(steps)
			end 

		else
			score = nil
			steps = nil
			breakdown = nil 
			primarySkill = nil 
			ctags = {}
		end
	end,
	CurrentSongChangedMessageCommand = function(self)
		self:queuecommand("MintyFresh")
	end,
	CurrentStepsChangedMessageCommand = function(self)
		self:queuecommand("MintyFresh")
	end,
	CurrentRateChangedMessageCommand = function(self)
		self:playcommand("MintyFresh")
	end
}

-- Information Display Panel
t[#t + 1] = Def.ActorFrame {
	Name = "InfoDisplayPanel",
	InitCommand = function(self)
		self:xy(frameX, frameY + 30):queuecommand("Set")
	end,
	SetCommand = function(self)
		self:visible(not getenv("StatsOverlayActive"))
	end,
	StatsOverlayStateChangedMessageCommand = function(self)
		self:queuecommand("Set")
	end,

	-- ROW 1: Colored status boxes
	(function()
		local boxW = (frameWidth - 10) / 3
		local boxH = 30
		local f = Def.ActorFrame{}
		
		-- Box backgrounds
		local function makeBoxBG(xIdx)
			return Def.Quad {
				InitCommand = function(self)
					self:xy((boxW * xIdx) + (5 * xIdx), 0):zoomto(boxW, boxH)
					self:halign(0):valign(0)
					self:diffuse(color("#000000")):diffusealpha(0.6)
				end
			}
		end
		f[#f+1] = makeBoxBG(0)
		f[#f+1] = makeBoxBG(1)
		f[#f+1] = makeBoxBG(2)

		-- Left Box: Skillset
		f[#f+1] = LoadFont("Common Large") .. {
			Name = "SkillsetStringMain",
			InitCommand = function(self)
				self:x(boxW/2):zoom(0.33):halign(0.5):valign(0.5):diffuse(color("#FFFFFF"))
			end,
			MintyFreshCommand = function(self)
				self:y((boxH/2) - 5)
				if not song or not primarySkill then
					self:settext("--")
					return 
				end
				self:settext(primarySkill)
				
				if GAMESTATE:GetCurrentStyle():ColumnsPerPlayer() ~= 4 then
					self:settext("Uncategorised")
				elseif breakdown == "" then 
					self:y(boxH/2)
				end
			end
		}
		f[#f+1] = LoadFont("Common Normal") .. {
			InitCommand = function(self)
				self:xy(boxW/2, boxH - 5):zoom(0.25):halign(0.5):valign(0.5):diffuse(color("#BBBBBB"))
				self:maxwidth((boxW - 8) / 0.20)
			end,
			MintyFreshCommand = function(self)
				if not song or not breakdown or GAMESTATE:GetCurrentStyle():ColumnsPerPlayer() ~= 4 then
					self:settext("")
					return 
				end

				self:settext(breakdown)
			end
		}

		-- Center Box: Clear Type
		f[#f+1] = LoadFont("Common Large") .. {
			InitCommand = function(self)
				self:xy(boxW + 5 + boxW/2, boxH/2 - 4):zoom(0.3):halign(0.5):valign(0.5)
			end,
			MintyFreshCommand = function(self)
				if not song then
					self:settext("--"):diffuse(color("#666666"))
				elseif score then
					self:settext(getClearTypeFromScore(PLAYER_1, score, 0))
					self:diffuse(getClearTypeFromScore(PLAYER_1, score, 2))
				else
					self:settext("--"):diffuse(color("#666666"))
				end
			end
		}
		f[#f+1] = LoadFont("Common Normal") .. {
			InitCommand = function(self)
				self:xy(boxW + 5 + boxW/2, boxH - 5):zoom(0.25):halign(0.5):valign(0.5):diffuse(color("#BBBBBB"))
			end,
			MintyFreshCommand = function(self)
				if not song then
					self:settext("--")
				elseif score then
					self:settextf("(%.2fx) • %s", score:GetMusicRate(), getScoreDateRelative(score))
				else
					self:settext("")
				end
			end
		}

		-- Right Box: Score
		f[#f+1] = LoadFont("Common Large") .. {
			InitCommand = function(self)
				self:xy((boxW*2) + 10 + boxW/2, boxH/2 - 4):zoom(0.3):halign(0.5):valign(0.5)
			end,
			MintyFreshCommand = function(self)
				if not song then
					self:settext("--"):diffuse(color("#666666"))
				elseif score then
					local perc = score:GetWifeScore() * 100
					if perc >= 99.7 then
						self:settextf("%.4f%% [%s]", perc, getJudgeLabel(score))
					else
						self:settextf("%.2f%% [%s]", perc, getJudgeLabel(score))
					end
					self:diffuse(byGrade(score:GetWifeGrade()))
				else
					self:settext("--"):diffuse(color("#666666"))
				end
			end
		}
		f[#f+1] = LoadFont("Common Normal") .. {
			InitCommand = function(self)
				self:xy((boxW*2) + 10 + boxW/2, boxH - 5):zoom(0.25):halign(0.5):valign(0.5):diffuse(color("#00FF00"))
			end,
			MintyFreshCommand = function(self)
				if not song then
					self:settext("--"):diffuse(color("#666666"))
				elseif score then
					self:settextf("(%.2fx) • %s", score:GetMusicRate(), getScoreDateRelative(score))
					self:diffuse(color("#00FF00"))
				else
					self:settext("")
				end
			end
		}
		
		return f
	end)(),

	-- ROW 2: Rate (Left) & Last Played (Right)
	LoadFont("Common Large") .. {
		InitCommand = function(self)
			self:xy(0, 40):zoom(0.3):halign(0):valign(0):diffuse(color("#FFFFFF"))
		end,
		MintyFreshCommand = function(self)
			self:settextf("%.2fx", getCurRateValue())
		end
	},
	LoadFont("Common Large") .. {
		InitCommand = function(self)
			self:xy(frameWidth, 40):zoom(0.3):halign(1):valign(0):diffuse(color("#FFFFFF"))
		end,
		MintyFreshCommand = function(self)
			if not song then
				self:settext("--")
			elseif score then
				self:settext("Last played " .. getScoreDateRelative(score))
			else
				self:settext("Never played")
			end
		end
	},

	-- ROW 3: Chart string (Left) & Radar string (Right)
	LoadFont("Common Normal") .. {
		InitCommand = function(self)
			self:xy(0, 56):zoom(0.27):halign(0):valign(0):diffuse(color("#DDDDDD"))
		end,
		MintyFreshCommand = function(self)
			if not song then
				self:settext("--")
			elseif steps then
				local stype = steps:GetStepsType():gsub("StepsType_","")
				local diff = ToEnumShortString(steps:GetDifficulty())
				local meter = steps:GetMeter()
				self:settextf("%s %s %d", stype, diff, meter)
			else
				self:settext("")
			end
		end
	},
	LoadFont("Common Normal") .. {
		InitCommand = function(self)
			self:xy(frameWidth, 58):zoom(0.27):halign(1):valign(0):diffuse(color("#DDDDDD"))
		end,
		MintyFreshCommand = function(self)
			if not song then
				self:settext("--")
			elseif steps then
				local stype = steps:GetStepsType():gsub("StepsType_","")
				local notes = steps:GetRadarValues(PLAYER_1):GetValue("RadarCategory_Notes")
				local holds = steps:GetRadarValues(PLAYER_1):GetValue("RadarCategory_Holds")
				self:settextf("%s | %d Notes | %d Holds", stype, notes, holds)
			else
				self:settext("")
			end
		end
	},

	-- ROW 4: Icons (Star, Note, Clock)
	(function()
		local icY = 76
		local f = Def.ActorFrame{}
		-- MSD Rate
		f[#f+1] = LoadFont("Common Large") .. {
			InitCommand = function(self)
				self:xy(0, icY):zoom(0.45):halign(0):valign(0.5)
			end,
			MintyFreshCommand = function(self)
				if not song then
					self:settext("--"):diffuse(color("#666666"))
				elseif steps then
					local msd = steps:GetMSD(getCurRateValue(), 1)
					self:settextf("%.2f", msd)
					self:diffuse(byMSD(msd))
				else
					self:settext("--"):diffuse(color("#666666"))
				end
			end
		}

		-- Note Icon
		f[#f+1] = Def.Sprite {
			Texture = THEME:GetPathG("", "Interlude Icons/music-solid.png"),
			InitCommand = function(self)
				self:xy(frameWidth/2 - 20, icY):halign(0.5):valign(0.5):diffuse(color("#FFFFFF"))
			end,
			OnCommand = function(self)
				normalizeInterludeIcon(self, 0.4)
			end,
		}
		-- BPM
		f[#f+1] = LoadFont("Common Large") .. {
			InitCommand = function(self)
				self:xy(frameWidth/2 - 15, icY):zoom(0.45):halign(0):valign(0.5):diffuse(color("#FFFFFF"))
			end,
			MintyFreshCommand = function(self)
				if not song then
					self:settext("--")
				elseif steps then
					local bpmVals = steps:GetDisplayBpms()
					if bpmVals and bpmVals[2] then
						local bpm = bpmVals[2] * getCurRateValue()
						self:settextf("%d", math.floor(bpm + 0.5))
					else
						self:settext("--")
					end
				else
					self:settext("--")
				end
			end
		}

		-- Clock Icon
		f[#f+1] = Def.Sprite {
			Texture = THEME:GetPathG("", "Interlude Icons/stopwatch-solid.png"),
			InitCommand = function(self)
				self:xy(frameWidth - 45, icY):halign(0.5):valign(0.5):diffuse(color("#FFFFFF"))
			end,
			OnCommand = function(self)
				normalizeInterludeIcon(self, 0.4)
			end,
		}
		-- Duration
		f[#f+1] = LoadFont("Common Large") .. {
			InitCommand = function(self)
				self:xy(frameWidth - 40, icY):zoom(0.45):halign(0):valign(0.5):diffuse(color("#FFFFFF"))
			end,
			MintyFreshCommand = function(self)
				if not song then
					self:settext("--")
				elseif song then
					self:settext(SecondsToMSS(song:GetStepsSeconds() / getCurRateValue()))
				else
					self:settext("--:--")
				end
			end
		}
		return f
	end)()
}

local enabledC = "#099948"
local disabledC = "#ff6666"
local force = false
local ready = false
local function toggleButton(textEnabled, textDisabled, msg, x, extrawidth, y, enabledF)
	local ison = false
	return Def.ActorFrame {
		InitCommand = function(self)
			self:xy(10 - 115 + capWideScale(get43size(384), 384) + x, 66 + capWideScale(get43size(120), 120) + y)
			self.updatebutton = function()
				if self.ison ~= nil then
					ison = self.ison
				end

				-- wtf
				self:GetChild("Top"):diffuse((ison and color(enabledC) or (isOver(self:GetChild("Top")) and getMainColor("highlight") or color(disabledC))))
				self:GetChild("Words"):settext(ison and textEnabled or textDisabled)
			end
		end,

		Def.Quad {
			Name = "BG",
			InitCommand = function(self)
				self:zoomto(50 + extrawidth + 1.5, 24 + 1.5)
				self:diffuse(color("#333333"))
			end,
		},
		UIElements.QuadButton(1, 1) .. {
			Name = "Top",
			InitCommand = function(self)
				self:zoomto(50 + extrawidth, 24)
				self:diffuse(color(disabledC))
			end,
			MouseOverCommand = function(self)
				self:diffuse(ison and color(enabledC) or getMainColor("highlight"))
			end,
			MouseOutCommand = function(self)
				self:diffuse(color(ison and enabledC or disabledC))
			end,
			MouseDownCommand = function(self, params)
				if params.event == "DeviceButton_left mouse button" then
					if enabledF then
						ison = enabledF()
					else
						ison = (not ison)
					end
					
					-- wtf 2
					self:diffuse(ison and color(enabledC) or getMainColor("highlight"))
					NSMAN:SendChatMsg(msg, 1, NSMAN:GetCurrentRoomName())
				end
			end,
		},
		LoadFont("Common Large") .. {
			Name = "Words",
			InitCommand = function(self)
				self:zoom(0.3)
				self:diffuse(color("#FFFFFF"))
				self:maxwidth((50 + extrawidth) / 0.3)
				self:settext(textDisabled)
			end,
		},
	}
end
local forceStart = toggleButton(translated_info["UnForceStart"], translated_info["ForceStart"], "/force", -35, 30, 11) .. {
	Name = "ForceStart",
}
local readyButton = nil
do
	-- do-end block to minimize the scope of 'f'
	local areWeReadiedUp = function()
		local top = SCREENMAN:GetTopScreen()
		if top:GetName() == "ScreenNetSelectMusic" then
			local qty = top:GetUserQty()
			local loggedInUser = NSMAN:GetLoggedInUsername()
			for i = 1, qty do
				local user = top:GetUser(i)
				if user == loggedInUser then
					return top:GetUserReady(i)
				end
			end
			-- ???? this should never happen
			-- retroactive - had this happen once and i still dont know why
			error "Could not find ourselves in the userlist"
		end
	end
	readyButton = toggleButton(translated_info["Unready"], translated_info["Ready"], "/ready", 50, 0, 11, areWeReadiedUp) .. {
		Name = "Ready",
		UsersUpdateMessageCommand = function(self)
			self.ison = areWeReadiedUp()
			self.updatebutton()
		end
	}
end

local sn = Var ("LoadingScreen")
if sn and sn:find("Net") ~= nil then
	t[#t + 1] = forceStart
	t[#t + 1] = readyButton
end

-- t[#t+1] = LoadFont("Common Large") .. {
-- InitCommand=function(self)
-- 	self:xy((capWideScale(get43size(384),384))+68,SCREEN_BOTTOM-135):halign(1):zoom(0.4,maxwidth,125)
-- end,
-- BeginCommand=function(self)
-- 	self:queuecommand("Set")
-- end,
-- SetCommand=function(self)
-- if song then
-- self:settext(song:GetOrTryAtLeastToGetSimfileAuthor())
-- else
-- self:settext("")
-- end
-- end,
-- CurrentStepsChangedMessageCommand=function(self)
-- 	self:queuecommand("Set")
-- end,
-- RefreshChartInfoMessageCommand=function(self)
-- 	self:queuecommand("Set")
-- end,
-- }

-- active filters display
-- t[#t+1] = Def.Quad{InitCommand=cmd(xy,16,capWideScale(SCREEN_TOP+172,SCREEN_TOP+194);zoomto,SCREEN_WIDTH*1.35*0.4 + 8,24;halign,0;valign,0.5;diffuse,color("#000000");diffusealpha,0),
-- EndingSearchMessageCommand=function(self)
-- self:diffusealpha(1)
-- end
-- }
-- t[#t+1] = LoadFont("Common Large") .. {
-- InitCommand=function(self)
-- 	self:xy(20,capWideScale(SCREEN_TOP+170,SCREEN_TOP+194)):halign(0):zoom(0.4):settext("Active Filters: "..GetPersistentSearch()):maxwidth(SCREEN_WIDTH*1.35)
-- end,
-- EndingSearchMessageCommand=function(self, msg)
-- self:settext("Active Filters: "..msg.ActiveFilter)
-- end
-- }

-- tags?
t[#t + 1] = LoadFont("Common Normal") .. {
	InitCommand = function(self)
		self:xy(frameX + 300, frameY - 60):halign(0):zoom(0.6):maxwidth(capWideScale(54, 450) / 0.6)
	end,
	MintyFreshCommand = function(self)
		if song and ctags[1] then
			self:settext(ctags[1])
		else
			self:settext("")
		end
	end,
	ChartPreviewOnMessageCommand = function(self)
		self:visible(false)
	end,
	ChartPreviewOffMessageCommand = function(self)
		self:visible(true)
	end
}

t[#t + 1] = LoadFont("Common Normal") .. {
	InitCommand = function(self)
		self:xy(frameX + 300, frameY - 30):halign(0):zoom(0.6):maxwidth(capWideScale(54, 450) / 0.6)
	end,
	MintyFreshCommand = function(self)
		if song and ctags[2] then
			self:settext(ctags[2])
		else
			self:settext("")
		end
	end
}

t[#t + 1] = LoadFont("Common Normal") .. {
	InitCommand = function(self)
		self:xy(frameX + 300, frameY):halign(0):zoom(0.6):maxwidth(capWideScale(54, 450) / 0.6)
	end,
	MintyFreshCommand = function(self)
		if song and ctags[3] then
			self:settext(ctags[3])
		else
			self:settext("")
		end
	end
}

--Chart Preview Button
local yesiwantnotefield = false
local lastratepresses = {0,0}

local function adjustMusicRate(delta)
	local rate = GAMESTATE:GetSongOptionsObject("ModsLevel_Preferred"):MusicRate()
	local nextRate = clamp(rate + delta, MIN_MUSIC_RATE, MAX_MUSIC_RATE)
	if math.abs(nextRate - rate) < 0.001 then return end
	GAMESTATE:GetSongOptionsObject("ModsLevel_Preferred"):MusicRate(nextRate)
	GAMESTATE:GetSongOptionsObject("ModsLevel_Song"):MusicRate(nextRate)
	GAMESTATE:GetSongOptionsObject("ModsLevel_Current"):MusicRate(nextRate)
	MESSAGEMAN:Broadcast("CurrentRateChanged")
end

local function ihatestickinginputcallbackseverywhere(event)
	if event.type ~= "InputEventType_Release" and getTabIndex() == 0 then
		if event.DeviceInput.button == "DeviceButton_space" then
			toggleNoteField()
		end
		if event.GameButton == "EffectUp" then
			lastratepresses[1] = 0
		end
		if event.GameButton == "EffectDown" then
			lastratepresses[2] = 0
		end
	end
	if event.type == "InputEventType_FirstPress" then
		local CtrlPressed = INPUTFILTER:IsControlPressed()
		if CtrlPressed and event.DeviceInput.button == "DeviceButton_l" then
			MESSAGEMAN:Broadcast("LoginHotkeyPressed")
		end
		if event.GameButton == "EffectUp" then
			lastratepresses[1] = GetTimeSinceStart()
		end
		if event.GameButton == "EffectDown" then
			lastratepresses[2] = GetTimeSinceStart()
		end
		-- this sucks so bad
		if math.abs(lastratepresses[1] - lastratepresses[2]) < 0.05 and lastratepresses[1] ~= 0 and lastratepresses[2] ~= 0 then
			MESSAGEMAN:Broadcast("Code", {Name="ResetRate"})
			ChangeMusicRate(nil, {Name="ResetRate"})
		elseif getTabIndex() == 0 and event.GameButton == "EffectUp" and not INPUTFILTER:IsControlPressed() then
			adjustMusicRate(0.05)
		elseif getTabIndex() == 0 and event.GameButton == "EffectDown" and not INPUTFILTER:IsControlPressed() then
			adjustMusicRate(-0.05)
		end
	end
	return false
end

local prevplayerops = "Main"

local collectionOverlayOpen = false
local collectionOverlayMode = "main"
local collectionPlaylistPage = 1
local collectionPlaylistPageSize = 6

local function openCollectionTab()
	local tind = getTabIndex()
	setTabIndex(7)
	MESSAGEMAN:Broadcast("TabChanged", {from = tind, to = 7})
end

local function broadcastCollectionOverlayState()
	MESSAGEMAN:Broadcast("CollectionOverlayStateChanged", {
		open = collectionOverlayOpen,
		mode = collectionOverlayMode,
		page = collectionPlaylistPage,
	})
end

local function setCollectionOverlayOpen(open, mode)
	collectionOverlayOpen = open == true
	if collectionOverlayOpen then
		collectionOverlayMode = mode or collectionOverlayMode or "main"
	else
		collectionOverlayMode = "main"
		collectionPlaylistPage = 1
	end
	broadcastCollectionOverlayState()
end

local function toggleCollectionOverlay()
	if collectionOverlayOpen then
		setCollectionOverlayOpen(false)
		return
	end
	if not GAMESTATE:GetCurrentSong() or not GAMESTATE:GetCurrentSteps() then
		ms.ok("No chart selected.")
		return
	end
	setCollectionOverlayOpen(true, "main")
end

local function getSelectMusicPlaylists()
	local playlists = SONGMAN:GetPlaylists() or {}
	table.sort(playlists, function(a, b)
		local aName = a and a.GetName and a:GetName() or ""
		local bName = b and b.GetName and b:GetName() or ""
		return aName:lower() < bName:lower()
	end)
	return playlists
end

local function getCurrentChartKey()
	local currentSteps = GAMESTATE:GetCurrentSteps()
	if not currentSteps then return nil end
	local ok, chartKey = pcall(function() return currentSteps:GetChartKey() end)
	if ok then
		return chartKey
	end
	return nil
end

local function findPlaylistByName(name)
	if not name or name == "" then return nil end
	for _, playlist in ipairs(getSelectMusicPlaylists()) do
		if playlist and playlist:GetName() == name then
			return playlist
		end
	end
	return nil
end

local function playlistContainsChart(playlist, chartKey)
	if not playlist or not chartKey then return false, nil end
	local ok, keys = pcall(function() return playlist:GetChartkeys() end)
	if not ok or not keys then return false, nil end
	for i, key in ipairs(keys) do
		if key == chartKey then
			return true, i
		end
	end
	return false, nil
end

local function tryCallMethod(target, methodNames, ...)
	if not target then return false end
	for _, methodName in ipairs(methodNames) do
		local method = target[methodName]
		if type(method) == "function" then
			local ok = pcall(method, target, ...)
			if ok then
				return true
			end
		end
	end
	return false
end

local function ensurePlaylistExists(name)
	local playlist = findPlaylistByName(name)
	if playlist then
		return true, playlist
	end
	local ok = tryCallMethod(SONGMAN, {"CreatePlaylist", "AddPlaylist", "MakePlaylist", "NewPlaylist"}, name)
	if ok then
		playlist = findPlaylistByName(name)
	end
	return playlist ~= nil, playlist
end

local function addCurrentChartToPlaylist(name)
	local chartKey = getCurrentChartKey()
	local currentSong = GAMESTATE:GetCurrentSong()
	local currentSteps = GAMESTATE:GetCurrentSteps()
	if not currentSong or not currentSteps or not chartKey then
		ms.ok("No chart selected.")
		return false
	end
	local okCreate, playlist = ensurePlaylistExists(name)
	if not okCreate or not playlist then
		ms.ok("Could not create or find playlist '" .. tostring(name) .. "'.")
		return false
	end
	local exists = playlistContainsChart(playlist, chartKey)
	if exists then
		ms.ok("Chart is already in '" .. name .. "'.")
		return true
	end
	local rate = getCurRateValue and getCurRateValue() or 1
	local ok = false
	ok = tryCallMethod(playlist, {"AddChart", "AddChartKey"}, chartKey, rate)
	if not ok then ok = tryCallMethod(playlist, {"AddChart", "AddChartKey"}, chartKey) end
	if not ok then ok = tryCallMethod(playlist, {"AddSong"}, currentSong, currentSteps, rate) end
	if not ok then ok = tryCallMethod(playlist, {"AddSong"}, currentSong, currentSteps) end
	if not ok then ok = tryCallMethod(playlist, {"AddSteps"}, currentSteps, rate) end
	if not ok then ok = tryCallMethod(playlist, {"AddSteps"}, currentSteps) end
	if not ok then
		ms.ok("Failed to add chart to '" .. name .. "'.")
		return false
	end
	ms.ok("Added chart to '" .. name .. "'.")
	broadcastCollectionOverlayState()
	return true
end

local function removeCurrentChartFromPlaylist(name)
	local playlist = findPlaylistByName(name)
	local chartKey = getCurrentChartKey()
	if not playlist or not chartKey then return false end
	local exists, index = playlistContainsChart(playlist, chartKey)
	if not exists or not index then return false end
	return tryCallMethod(playlist, {"DeleteChart"}, index)
end

local function isCurrentChartFavorited()
	local currentSong = GAMESTATE:GetCurrentSong()
	if currentSong and currentSong.IsFavorited then
		local ok, result = pcall(function() return currentSong:IsFavorited() end)
		if ok then
			return result
		end
	end
	local playlist = findPlaylistByName("Favorites")
	local chartKey = getCurrentChartKey()
	local exists = playlistContainsChart(playlist, chartKey)
	return exists
end

local function toggleCurrentChartFavorite()
	local currentSong = GAMESTATE:GetCurrentSong()
	local desired = not isCurrentChartFavorited()
	if currentSong then
		local ok = false
		if desired then
			ok = tryCallMethod(currentSong, {"SetFavorited"}, true)
			if not ok then ok = tryCallMethod(currentSong, {"AddToFavorites", "Favorite", "SetFavorite"}) end
		else
			ok = tryCallMethod(currentSong, {"SetFavorited"}, false)
			if not ok then ok = tryCallMethod(currentSong, {"RemoveFromFavorites", "Unfavorite", "SetFavorite"}, false) end
		end
		if ok then
			ms.ok(desired and "Chart favourited." or "Chart unfavourited.")
			broadcastCollectionOverlayState()
			return true
		end
	end
	local okCreate = ensurePlaylistExists("Favorites")
	if not okCreate then
		ms.ok("Could not access Favorites.")
		return false
	end
	if desired then
		local added = addCurrentChartToPlaylist("Favorites")
		if added then
			broadcastCollectionOverlayState()
		end
		return added
	end
	local removed = removeCurrentChartFromPlaylist("Favorites")
	if removed then
		ms.ok("Chart unfavourited.")
		broadcastCollectionOverlayState()
	else
		ms.ok("Chart is not in Favorites.")
	end
	return removed
end

local function createPlaylistAndAddCurrentChart()
	easyInputStringWithFunction("New playlist name:", 64, false, function(answer)
		if not answer or answer == "" then return end
		local success = addCurrentChartToPlaylist(answer)
		if success then
			collectionOverlayMode = "playlist"
			broadcastCollectionOverlayState()
		end
	end)
end

local function collectionPlaylistPageCount()
	return math.max(1, math.ceil(#getSelectMusicPlaylists() / collectionPlaylistPageSize))
end

local function updateCollectionPlaylistPage(delta)
	collectionPlaylistPage = clamp(collectionPlaylistPage + delta, 1, collectionPlaylistPageCount())
	broadcastCollectionOverlayState()
end

local function collectionPlaylistForRow(row)
	return getSelectMusicPlaylists()[row + ((collectionPlaylistPage - 1) * collectionPlaylistPageSize)]
end

local function collectionMenuRow(y, width, labelGetter, mouseDown, textGetter)
	return Def.ActorFrame {
		InitCommand = function(self) self:xy(0, y) end,
		UIElements.QuadButton(1, 1) .. {
			InitCommand = function(self)
				self:zoomto(width, 34):halign(0):valign(0):diffuse(color("#1f2833")):diffusealpha(0.94)
			end,
			MouseDownCommand = mouseDown,
			MouseOverCommand = function(self) self:diffusealpha(1) end,
			MouseOutCommand = function(self) self:diffusealpha(0.94) end,
		},
		LoadFont("Common Large") .. {
			InitCommand = function(self)
				self:xy(12, 17):halign(0):valign(0.5):zoom(0.3)
			end,
			SetCommand = function(self)
				local label = type(labelGetter) == "function" and labelGetter() or labelGetter
				self:settext(label or "")
				self:diffuse(textGetter and textGetter() or color("#FFFFFF"))
			end,
			CollectionOverlayStateChangedMessageCommand = function(self) self:queuecommand("Set") end,
			CurrentSongChangedMessageCommand = function(self) self:queuecommand("Set") end,
			CurrentStepsChangedMessageCommand = function(self) self:queuecommand("Set") end,
		}
	}
end

local function collectionPlaylistRow(row, y)
	return Def.ActorFrame {
		InitCommand = function(self) self:xy(0, y) end,
		collectionMenuRow(0, 320, function()
			local playlist = collectionPlaylistForRow(row)
			if not playlist then return "" end
			local name = playlist:GetName()
			local exists = playlistContainsChart(playlist, getCurrentChartKey())
			return exists and (name .. "  ✓") or name
		end, function(self, params)
			if params.event == "DeviceButton_left mouse button" then
				local playlist = collectionPlaylistForRow(row)
				if playlist then
					local added = addCurrentChartToPlaylist(playlist:GetName())
					if added then
						setCollectionOverlayOpen(false)
					end
				end
			end
		end, function()
			local playlist = collectionPlaylistForRow(row)
			if not playlist then return color("#FFFFFF") end
			local exists = playlistContainsChart(playlist, getCurrentChartKey())
			return exists and getMainColor("highlight") or color("#FFFFFF")
		end) .. {
			SetCommand = function(self)
				self:visible(collectionPlaylistForRow(row) ~= nil)
			end,
			CollectionOverlayStateChangedMessageCommand = function(self) self:queuecommand("Set") end,
			CurrentSongChangedMessageCommand = function(self) self:queuecommand("Set") end,
			CurrentStepsChangedMessageCommand = function(self) self:queuecommand("Set") end,
		}
	}
end

local function startSongWithPracticeMode(enabled)
	local slot = pn_to_profile_slot(PLAYER_1)
	local data = playerConfig:get_data(slot)
	data.PracticeMode = enabled
	playerConfig:set_dirty(slot)
	playerConfig:save(slot)

	if GAMESTATE then
		if GAMESTATE.SetPracticeMode then
			pcall(function()
				GAMESTATE:SetPracticeMode(enabled)
			end)
		elseif GAMESTATE.ApplyGameCommand then
			pcall(function()
				GAMESTATE:ApplyGameCommand(enabled and "mod,practice" or "mod,no practice")
			end)
		end
	end

	local pstate = GAMESTATE and GAMESTATE.GetPlayerState and GAMESTATE:GetPlayerState(PLAYER_1) or nil
	if pstate and pstate.GetPlayerOptions then
		local okPreferred, preferred = pcall(function()
			return pstate:GetPlayerOptions("ModsLevel_Preferred")
		end)
		if okPreferred and preferred and preferred.Practice then
			pcall(function()
				preferred:Practice(enabled)
			end)
		end
		local okCurrent, current = pcall(function()
			return pstate:GetPlayerOptions("ModsLevel_Current")
		end)
		if okCurrent and current and current.Practice then
			pcall(function()
				current:Practice(enabled)
			end)
		end
	end

	local top = SCREENMAN:GetTopScreen()
	if top and top.SelectCurrent then
		top:SelectCurrent()
	end
end

t[#t + 1] = Def.ActorFrame {
	Name = "LittleButtonsOnTheLeft",
	InitCommand = function(self)
		self:queuecommand("Set")
	end,
	SetCommand = function(self)
		self:visible(not getenv("StatsOverlayActive"))
	end,
	StatsOverlayStateChangedMessageCommand = function(self)
		self:queuecommand("Set")
	end,

	Def.Sprite {
		Name = "PreviewViewerIcon",
		Texture = THEME:GetPathG("", "Interlude Icons/eye-solid.png"),
		InitCommand = function(self)
			self:xy(24, SCREEN_BOTTOM - 58):halign(0.5):valign(0.5):diffuse(getMainColor("positive"))
		end,
		OnCommand = function(self)
			normalizeInterludeIcon(self, 0.4)
		end,
		MouseDownCommand = function(self, params)
			if params.event == "DeviceButton_left mouse button" and (song or noteField) then
				toggleNoteField()
			elseif params.event == "DeviceButton_right mouse button" and (song or noteField) then
				if mcbootlarder:IsVisible() then
					toggleCalcInfo(not infoOnScreen)
				else
					if toggleNoteField() then
						toggleCalcInfo(true)
					end
				end
			end
		end,
		MouseOverCommand = function(self)
			self:diffusealpha(hoverAlpha2)
		end,
		MouseOutCommand = function(self)
			self:diffusealpha(1)
		end,
		MintyFreshCommand = function(self)
			self:visible(song ~= nil)
		end,
	},

	UIElements.TextToolTip(1, 1, "Common Normal") .. {
		Name = "PreviewViewer",
		BeginCommand = function(self)
			mcbootlarder = self:GetParent():GetParent():GetChild("ChartPreview")
			SCREENMAN:GetTopScreen():AddInputCallback(MPinput)
			SCREENMAN:GetTopScreen():AddInputCallback(ihatestickinginputcallbackseverywhere)
			self:xy(72, SCREEN_BOTTOM - 58):zoom(0.5):halign(0.5)
			self:settext("Preview")
			self:diffuse(getMainColor("positive"))
		end,
		MouseDownCommand = function(self, params)
			if params.event == "DeviceButton_left mouse button" and (song or noteField) then
				toggleNoteField()
			elseif params.event == "DeviceButton_right mouse button" and (song or noteField) then
				if mcbootlarder:IsVisible() then
					toggleCalcInfo(not infoOnScreen)
				else
					if toggleNoteField() then
						toggleCalcInfo(true)
					end
				end
			end
		end,
		MouseOverCommand = function(self) self:diffusealpha(hoverAlpha2) end,
		MouseOutCommand = function(self) self:diffusealpha(1) end,
		ChartPreviewOnMessageCommand = function(self)
			local ready = self:GetParent():GetParent():GetChild("Ready")
			local force = self:GetParent():GetParent():GetChild("ForceStart")
			if ready ~= nil then
				ready:visible(false)
			end
			if force ~= nil then
				force:visible(false)
			end
		end,
		ChartPreviewOffMessageCommand = function(self)
			if SCREENMAN:GetTopScreen():GetName():find("Net") ~= nil then
				local ready = self:GetParent():GetParent():GetChild("Ready")
				local force = self:GetParent():GetParent():GetChild("ForceStart")
				if ready ~= nil then
					ready:visible(true)
				end
				if force ~= nil then
					force:visible(true)
				end
			end
		end,
		MintyFreshCommand = function(self)
			if song then
				self:settext(translated_info["TogglePreview"])
			else
				self:settext("")
			end
		end,
	},

	Def.Sprite {
		Name = "PlayerOptionsIcon",
		Texture = THEME:GetPathG("", "Interlude Icons/bolt-solid.png"),
		InitCommand = function(self)
			self:xy(188, SCREEN_BOTTOM - 58):halign(0.5):valign(0.5):diffuse(getMainColor("positive"))
		end,
		OnCommand = function(self)
			normalizeInterludeIcon(self, 0.4)
		end,
		MouseDownCommand = function(self, params)
			if params.event == "DeviceButton_left mouse button" and song then
				SCREENMAN:GetTopScreen():OpenOptions()
			end
		end,
		MouseOverCommand = function(self) self:diffusealpha(hoverAlpha2) end,
		MouseOutCommand = function(self) self:diffusealpha(1) end,
	},

	UIElements.TextToolTip(1, 1, "Common Normal") .. {
		Name = "PlayerOptionsButton",
		BeginCommand = function(self)
			self:xy(232, SCREEN_BOTTOM - 58):halign(0.5):zoom(0.5)
			self:settext("Mods")
			self:diffuse(getMainColor("positive"))
		end,
		MouseOverCommand = function(self)
			self:diffusealpha(hoverAlpha2)
		end,
		MouseOutCommand = function(self)
			self:diffusealpha(1)
		end,
		MouseDownCommand = function(self, params)
			if params.event == "DeviceButton_left mouse button" and song then
				SCREENMAN:GetTopScreen():OpenOptions()
			end
		end,
		OptionsScreenClosedMessageCommand = function(self)
			local nextplayerops = getenv("NewOptions") or "Main"
			if nextplayerops == prevplayerops then
				setenv("NewOptions", "Main")
				prevplayerops = "Main"
				return
			end
			prevplayerops = nextplayerops
			setenv("NewOptions", nextplayerops)
			SCREENMAN:GetTopScreen():OpenOptions()
		end,
	},

	-- Judge Dropdown Menu
	Def.ActorFrame {
		Name = "JudgeDropdown",
		InitCommand = function(self)
			self:xy(390, SCREEN_BOTTOM - 75):visible(false):draworder(dropdownDrawOrder)
		end,
		JudgeChangedMessageCommand = function(self)
			self:visible(false)
		end,
		-- Menu Background
		Def.Quad {
			InitCommand = function(self)
				self:zoomto(80, 140):valign(1):diffuse(color("#111111")):diffusealpha(0.95)
			end
		},
		-- Menu Items (J4 to J9)
		(function()
			local items = Def.ActorFrame{}
			local function makeJudgeItem(i)
				return UIElements.TextToolTip(1, 1, "Common Normal") .. {
					InitCommand = function(self)
						self:y(-22 * (i - 3.5)):zoom(0.5):settext("Judge " .. i)
						if GetTimingDifficulty() == i then
							self:diffuse(getMainColor("highlight"))
						else
							self:diffuse(color("#FFFFFF"))
						end
					end,
					MouseDownCommand = function(self, params)
						if params.event == "DeviceButton_left mouse button" then
							local scale = ms.JudgeScalers[i]
							SetTimingDifficulty(scale)
							PREFSMAN:SavePreferences()
							MESSAGEMAN:Broadcast("JudgeChanged")
							MESSAGEMAN:Broadcast("JudgeDisplayChanged")
						end
					end,
					MouseOverCommand = function(self) self:diffusealpha(0.6) end,
					MouseOutCommand = function(self) self:diffusealpha(1) end,
					JudgeChangedMessageCommand = function(self)
						if GetTimingDifficulty() == i then
							self:diffuse(getMainColor("highlight"))
						else
							self:diffuse(color("#FFFFFF"))
						end
					end
				}
			end
			for i = 4, 9 do
				items[#items+1] = makeJudgeItem(i)
			end
			return items
		end)()
	},

	UIElements.TextToolTip(1, 1, "Common Normal") .. {
		Name = "Wife3J4Button",
		BeginCommand = function(self)
			self:xy(390, SCREEN_BOTTOM - 58):halign(0.5):zoom(0.5)
			self:settext("Judge " .. GetTimingDifficulty())
			self:diffuse(getMainColor("positive"))
		end,
		MouseDownCommand = function(self, params)
			if params.event == "DeviceButton_left mouse button" then
				local dd = self:GetParent():GetChild("JudgeDropdown")
				dd:visible(not dd:IsVisible())
			elseif params.event == "DeviceButton_right mouse button" then
				-- Cycle backwards as a shortcut
				local cur = GetTimingDifficulty()
				local nextJ = (cur > 4) and (cur - 1) or 9
				local scale = ms.JudgeScalers[nextJ]
				SetTimingDifficulty(scale)
				PREFSMAN:SavePreferences()
				MESSAGEMAN:Broadcast("JudgeChanged")
				MESSAGEMAN:Broadcast("JudgeDisplayChanged")
			end
		end,
		MouseOverCommand = function(self) self:diffusealpha(hoverAlpha2) end,
		MouseOutCommand = function(self) self:diffusealpha(0.9) end,
		JudgeChangedMessageCommand = function(self)
			self:settext("Judge " .. GetTimingDifficulty())
		end
	},

	UIElements.QuadButton(1, 1) .. {
		Name = "RightButtonsBackdrop",
		InitCommand = function(self)
			self:xy(SCREEN_WIDTH - 400, SCREEN_BOTTOM - 78):halign(0):valign(0)
			self:zoomto(400, 44):diffuse(getMainColor("frames")):diffusealpha(0.9)
		end,
		SetDynamicAccentColorMessageCommand = function(self, params)
			self:diffuse(params.color):diffusealpha(0.9)
		end
	},

	UIElements.TextToolTip(1, 1, "Common Normal") .. {
		Name = "CollectionButton",
		BeginCommand = function(self)
			self:xy(bottomButtonPositions.Collection, bottomButtonY):halign(0):zoom(0.5)
			self:settext("Collection")
			self:diffuse(getMainColor("positive"))
		end,
		MouseDownCommand = function(self, params)
			if params.event == "DeviceButton_left mouse button" then
				toggleCollectionOverlay()
			end
		end,
		MouseOverCommand = function(self) self:diffusealpha(hoverAlpha2) end,
		MouseOutCommand = function(self) self:diffusealpha(1) end,
	},

	Def.Sprite {
		Name = "CollectionIcon",
		Texture = THEME:GetPathG("", "Interlude Icons/list-solid.png"),
		InitCommand = function(self)
			self:xy(bottomButtonPositions.Collection - bottomButtonIconTextGap, bottomButtonY):halign(1):valign(0.5):diffuse(getMainColor("positive"))
		end,
		OnCommand = function(self)
			normalizeInterludeIcon(self, bottomButtonIconSize / interludeIconTargetSize)
		end,
		MouseDownCommand = function(self, params)
			if params.event == "DeviceButton_left mouse button" then
				toggleCollectionOverlay()
			end
		end,
		MouseOverCommand = function(self) self:diffusealpha(hoverAlpha2) end,
		MouseOutCommand = function(self) self:diffusealpha(1) end,
	},

	Def.ActorFrame {
		Name = "CollectionOverlay",
		InitCommand = function(self)
			self:xy(SCREEN_WIDTH - 360, SCREEN_BOTTOM - 88):visible(false):draworder(dropdownDrawOrder)
		end,
		SetCommand = function(self)
			self:visible(collectionOverlayOpen and GAMESTATE:GetCurrentSong() ~= nil and GAMESTATE:GetCurrentSteps() ~= nil)
		end,
		CollectionOverlayStateChangedMessageCommand = function(self) self:queuecommand("Set") end,
		CurrentSongChangedMessageCommand = function(self)
			setCollectionOverlayOpen(false)
		end,
		CurrentStepsChangedMessageCommand = function(self)
			setCollectionOverlayOpen(false)
		end,
		TabChangedMessageCommand = function(self)
			setCollectionOverlayOpen(false)
		end,
		Def.Quad {
			InitCommand = function(self)
				self:zoomto(320, 244):halign(0):valign(1):diffuse(color("#111111")):diffusealpha(0.95)
			end,
			SetCommand = function(self)
				self:zoomto(320, collectionOverlayMode == "playlist" and 244 or 154)
			end,
			CollectionOverlayStateChangedMessageCommand = function(self) self:queuecommand("Set") end,
		},
		LoadFont("Common Large") .. {
			InitCommand = function(self)
				self:xy(12, -224):halign(0):valign(0.5):zoom(0.34)
			end,
			SetCommand = function(self)
				self:settext(collectionOverlayMode == "playlist" and "Add to collection" or "Chart actions")
				self:y(collectionOverlayMode == "playlist" and -224 or -134)
			end,
			CollectionOverlayStateChangedMessageCommand = function(self) self:queuecommand("Set") end,
		},
		Def.ActorFrame {
			SetCommand = function(self) self:visible(collectionOverlayMode == "main") end,
			CollectionOverlayStateChangedMessageCommand = function(self) self:queuecommand("Set") end,
			collectionMenuRow(-118, 320, function()
				return isCurrentChartFavorited() and "Unlike chart  >" or "Like chart  >"
			end, function(self, params)
				if params.event == "DeviceButton_left mouse button" then
					toggleCurrentChartFavorite()
				end
			end, function()
				return isCurrentChartFavorited() and getMainColor("highlight") or color("#FFFFFF")
			end),
			collectionMenuRow(-78, 320, "Add to collection  >", function(self, params)
				if params.event == "DeviceButton_left mouse button" then
					collectionOverlayMode = "playlist"
					broadcastCollectionOverlayState()
				end
			end),
			collectionMenuRow(-38, 320, "Practice this chart  >", function(self, params)
				if params.event == "DeviceButton_left mouse button" and GAMESTATE:GetCurrentSong() then
					setCollectionOverlayOpen(false)
					startSongWithPracticeMode(true)
				end
			end)
		},
		Def.ActorFrame {
			SetCommand = function(self) self:visible(collectionOverlayMode == "playlist") end,
			CollectionOverlayStateChangedMessageCommand = function(self) self:queuecommand("Set") end,
			collectionMenuRow(-196, 64, "Back", function(self, params)
				if params.event == "DeviceButton_left mouse button" then
					collectionOverlayMode = "main"
					broadcastCollectionOverlayState()
				end
			end),
			Def.ActorFrame {
				InitCommand = function(self) self:xy(72, -196) end,
				collectionMenuRow(0, 248, "New collection", function(self, params)
					if params.event == "DeviceButton_left mouse button" then
						createPlaylistAndAddCurrentChart()
					end
				end),
			},
			collectionMenuRow(-156, 64, "Prev", function(self, params)
				if params.event == "DeviceButton_left mouse button" then
					updateCollectionPlaylistPage(-1)
				end
			end),
			Def.ActorFrame {
				InitCommand = function(self) self:xy(256, -156) end,
				collectionMenuRow(0, 64, "Next", function(self, params)
					if params.event == "DeviceButton_left mouse button" then
						updateCollectionPlaylistPage(1)
					end
				end),
			},
			LoadFont("Common Large") .. {
				InitCommand = function(self)
					self:xy(160, -139):halign(0.5):valign(0.5):zoom(0.24)
				end,
				SetCommand = function(self)
					self:settext(string.format("%d / %d", collectionPlaylistPage, collectionPlaylistPageCount()))
				end,
				CollectionOverlayStateChangedMessageCommand = function(self) self:queuecommand("Set") end,
			},
			collectionPlaylistRow(1, -112),
			collectionPlaylistRow(2, -74),
			collectionPlaylistRow(3, -36),
			collectionPlaylistRow(4, 2),
			collectionPlaylistRow(5, 40),
			collectionPlaylistRow(6, 78),
		}
	},

	Def.Sprite {
		Name = "RandomIcon",
		Texture = THEME:GetPathG("", "Interlude Icons/shuffle-solid.png"),
		InitCommand = function(self)
			self:xy(bottomButtonPositions.Random - bottomButtonIconTextGap, bottomButtonY):halign(1):valign(0.5):diffuse(getMainColor("positive"))
		end,
		OnCommand = function(self)
			normalizeInterludeIcon(self, bottomButtonIconSize / interludeIconTargetSize)
		end,
		MouseDownCommand = function(self, params)
			if params.event == "DeviceButton_left mouse button" and SelectRandomSong then
				SelectRandomSong()
			end
		end,
		MouseOverCommand = function(self) self:diffusealpha(hoverAlpha2) end,
		MouseOutCommand = function(self) self:diffusealpha(1) end,
	},

	UIElements.TextToolTip(1, 1, "Common Normal") .. {
		Name = "RandomButton",
		BeginCommand = function(self)
			self:xy(bottomButtonPositions.Random, bottomButtonY):halign(0):zoom(0.5)
			self:settext("Random")
			self:diffuse(getMainColor("positive"))
		end,
		MouseDownCommand = function(self, params)
			if params.event == "DeviceButton_left mouse button" and SelectRandomSong then
				SelectRandomSong()
			end
		end,
		MouseOverCommand = function(self) self:diffusealpha(hoverAlpha2) end,
		MouseOutCommand = function(self) self:diffusealpha(1) end,
	},

	UIElements.TextToolTip(1, 1, "Common Normal") .. {
		Name = "PracticeButton",
		BeginCommand = function(self)
			self:xy(bottomButtonPositions.Practice, bottomButtonY):halign(0):zoom(0.5)
			self:settext("Practice")
			self:diffuse(getMainColor("positive"))
		end,
		MouseDownCommand = function(self, params)
			if params.event == "DeviceButton_left mouse button" and song then
				startSongWithPracticeMode(true)
			end
		end,
		MouseOverCommand = function(self) self:diffusealpha(hoverAlpha2) end,
		MouseOutCommand = function(self) self:diffusealpha(1) end,
	},

	Def.Sprite {
		Name = "PracticeIcon",
		Texture = THEME:GetPathG("", "Interlude Icons/stopwatch-solid.png"),
		InitCommand = function(self)
			self:xy(bottomButtonPositions.Practice - bottomButtonIconTextGap, bottomButtonY):halign(1):valign(0.5):diffuse(getMainColor("positive"))
		end,
		OnCommand = function(self)
			normalizeInterludeIcon(self, bottomButtonIconSize / interludeIconTargetSize)
		end,
		MouseDownCommand = function(self, params)
			if params.event == "DeviceButton_left mouse button" and song then
				startSongWithPracticeMode(true)
			end
		end,
		MouseOverCommand = function(self) self:diffusealpha(hoverAlpha2) end,
		MouseOutCommand = function(self) self:diffusealpha(1) end,
	},



	UIElements.TextToolTip(1, 1, "Common Normal") .. {
		Name = "PlayButton",
		BeginCommand = function(self)
			self:xy(bottomButtonPositions.Play, bottomButtonY):halign(0):zoom(0.7)
			self:settext("Play")
			self:diffuse(getMainColor("positive"))
		end,
		MouseDownCommand = function(self, params)
			if params.event == "DeviceButton_left mouse button" then
				startSongWithPracticeMode(false)
			end
		end,
		MouseOverCommand = function(self) self:diffusealpha(hoverAlpha2) end,
		MouseOutCommand = function(self) self:diffusealpha(1) end,
	},

	Def.Sprite {
		Name = "PlayIcon",
		Texture = THEME:GetPathG("", "Interlude Icons/play-solid.png"),
		InitCommand = function(self)
			self:xy(bottomButtonPositions.Play - bottomButtonIconTextGap, bottomButtonY):halign(1):valign(0.5):diffuse(getMainColor("positive"))
		end,
		OnCommand = function(self)
			normalizeInterludeIcon(self, bottomButtonIconSize / interludeIconTargetSize)
		end,
		MouseDownCommand = function(self, params)
			if params.event == "DeviceButton_left mouse button" then
				startSongWithPracticeMode(false)
			end
		end,
		MouseOverCommand = function(self) self:diffusealpha(hoverAlpha2) end,
		MouseOutCommand = function(self) self:diffusealpha(1) end,
	},



}

t[#t + 1] = LoadActorWithParams("../_chartpreview.lua", {yPos = prevY, yPosReverse = prevrevY})
return t
