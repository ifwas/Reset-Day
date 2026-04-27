local t = Def.ActorFrame {}
t[#t + 1] = LoadActor("../_frame")

translated_info = {
	Replay = THEME:GetString("ScreenEvaluation", "ReplayTitle")
}

local function formatSessionTime(seconds)
	seconds = math.max(0, math.floor(seconds or 0))
	local hours = math.floor(seconds / 3600)
	local minutes = math.floor((seconds % 3600) / 60)
	local secs = seconds % 60
	if hours > 0 then
		return string.format("%02d:%02d:%02d", hours, minutes, secs)
	end
	return string.format("%02d:%02d", minutes, secs)
end

local function getDisplayName()
	if DLMAN:IsLoggedIn() then
		return DLMAN:GetUsername()
	end
	local profile = GetPlayerOrMachineProfile(PLAYER_1)
	if profile then
		local name = profile:GetDisplayName()
		if name ~= "" then
			return name
		end
	end
	return "Guest"
end

local function getLocalProfileSummaryText()
	local profile = GetPlayerOrMachineProfile(PLAYER_1)
	if not profile then
		return "Local: Guest"
	end
	local name = profile:GetDisplayName()
	if not name or name == "" then
		name = "Guest"
	end
	local rating = profile.GetPlayerRating and profile:GetPlayerRating() or 0
	return string.format("Local: %s (%5.2f)", name, rating)
end

local function getOnlineProfileSummaryText()
	if DLMAN:IsLoggedIn() then
		return string.format("Online: %s (%5.2f)", DLMAN:GetUsername(), DLMAN:GetSkillsetRating("Overall"))
	end
	return "Online: Not logged in"
end

local function getStepHeaderText()
	local steps = GAMESTATE:GetCurrentSteps()
	local style = GAMESTATE:GetCurrentStyle()
	if not steps then return "" end
	local columns = style and style:ColumnsPerPlayer() or 4
	local diff = getDifficulty(steps:GetDifficulty())
	return string.format("%dK %s %d", columns, getShortDifficulty(diff), steps:GetMeter())
end

local function getPackCreditText()
	local song = GAMESTATE:GetCurrentSong()
	local steps = GAMESTATE:GetCurrentSteps()
	if not song then return "" end
	local group = song:GetGroupName() or "Unknown group"
	local credit = steps and steps:GetAuthorCredit() or ""
	if credit ~= "" then
		return string.format("From %s · Charted by %s", group, credit)
	end
	return string.format("From %s", group)
end

local usingCustomWindows = false
local lastSnapshot = nil

local function getCurrentScore()
	local score = SCOREMAN:GetMostRecentScore()
	if not score then
		score = SCOREMAN:GetTempReplayScore()
	end
	return score
end

-- Variables for rescoring
local dvt = {}
local judge = GetTimingDifficulty()

-- Build the rst table expected by the global getRescoredWife3Judge(version, judgeScale, rst).
-- Uses score tap-note counts (reliable) instead of radar values (fragile on eval screen).
local function getRescoreElements()
	local score = getCurrentScore()
	if not score then return nil end
	local replay = score:GetReplay()
	if not replay then return nil end
	replay:LoadAllData()
	local offsetVec = replay:GetOffsetVector()
	if not offsetVec or #offsetVec == 0 then return nil end

	-- totalTaps: sum of all judgment buckets from the stored score
	local judgeNames = {
		"TapNoteScore_W1", "TapNoteScore_W2", "TapNoteScore_W3",
		"TapNoteScore_W4", "TapNoteScore_W5", "TapNoteScore_Miss"
	}
	local totalTaps = 0
	for _, name in ipairs(judgeNames) do
		totalTaps = totalTaps + score:GetTapNoteScore(name)
	end

	-- holds/mines for the wife3 penalty terms
	local pss = STATSMAN:GetCurStageStats():GetPlayerStageStats()
	local holdsMissed = 0
	local minesHit = 0
	if pss then
		local ok1, rp = pcall(function() return pss:GetRadarPossible() end)
		local ok2, ra = pcall(function() return pss:GetRadarActual() end)
		if ok1 and ok2 and rp and ra then
			local totalHolds = rp:GetValue("RadarCategory_Holds") + rp:GetValue("RadarCategory_Rolls")
			local holdsHit   = ra:GetValue("RadarCategory_Holds") + ra:GetValue("RadarCategory_Rolls")
			holdsMissed = totalHolds - holdsHit
			local totalMines  = rp:GetValue("RadarCategory_Mines")
			local minesAvoided = ra:GetValue("RadarCategory_Mines")
			minesHit = totalMines - minesAvoided
		end
	end

	return {
		dvt         = offsetVec,
		totalTaps   = totalTaps,
		holdsMissed = holdsMissed,
		minesHit    = minesHit,
	}
end

-- Use the global getRescoredWife3Judge(version=3, judgeScale, rst) from _fallback/Scripts/10 Scores.lua
-- Returns wife% [0-100] rescored to the given judge, or falls back to the stored score.
local function getRescoredPercent(j)
	local rst = getRescoreElements()
	if not rst then
		local score = getCurrentScore()
		return score and (score:GetWifeScore() * 100) or 0
	end
	return getRescoredWife3Judge(3, j, rst)
end

local function getRescoredGrade(j)
	local rst = getRescoreElements()
	if not rst then
		local score = getCurrentScore()
		return score and score:GetWifeGrade() or "Grade_Failed"
	end
	local percent = getRescoredWife3Judge(3, j, rst) -- returns 0-100
	return GetGradeFromPercent(percent / 100)         -- expects 0-1
end

local function scaleToJudge(scale)
	scale = notShit.round(scale or ms.JudgeScalers[GetTimingDifficulty()], 2)
	local scales = ms.JudgeScalers
	local out = 4
	for k, v in pairs(scales) do
		if v == scale then
			out = k
		end
	end
	if out < 4 then out = 4 end
	if out > 9 then out = 9 end
	return out
end

local function getDisplayedJudgeLabel()
	if usingCustomWindows then
		return getCurrentCustomWindowConfigName()
	end
	local js = judge ~= 9 and judge or "ustice"
	return "Wife3 J" .. js
end

local function getCurrentRateRecordScore(score)
	if not score then return nil end
	local scoreTable = getScoresByKey(PLAYER_1)
	if not scoreTable then return nil end
	local rateTable = getRateTable(scoreTable) or {}
	local currentRateTable = rateTable[getRate(score)] or {}
	return currentRateTable[1]
end

local function getDisplayedPercentText(score, useRescored)
	if not score then return "-" end
	local percent
	if usingCustomWindows and lastSnapshot then
		percent = lastSnapshot:GetWifePercent() * 100
	elseif useRescored then
		percent = getRescoredPercent(judge)
	else
		percent = score:GetWifeScore() * 100
	end
	return string.format("%06.3f%%", percent)
end

local function getDisplayedGrade(useRescored)
	if usingCustomWindows and lastSnapshot then
		return GetGradeFromPercent(lastSnapshot:GetWifePercent())
	end
	if useRescored then
		return getRescoredGrade(judge)
	end
	local score = getCurrentScore()
	if not score then return "Grade_Failed" end
	return score:GetWifeGrade()
end

local function isLivePlay()
	local top = SCREENMAN:GetTopScreen()
	if not top or not top.GetStageStats then return false end
	local ss = top:GetStageStats()
	return ss and ss:GetLivePlay()
end

local function getRecordLabel(score)
	local recordScore = getCurrentRateRecordScore(score)
	if not recordScore then return "" end
	if isLivePlay() and recordScore == score and score == SCOREMAN:GetMostRecentScore() then
		return "New record!"
	end
	local recordPercent = recordScore:GetWifeScore() * 100
	if recordPercent > 99 then
		return string.format("Your record: %05.4f%%", recordPercent)
	end
	return string.format("Your record: %05.2f%%", recordPercent)
end

local function getClearTypeText(score)
	if not score then return "-" end
	return getClearTypeFromScore(PLAYER_1, score, 0)
end

local function getClearTypeColor(score)
	if not score then return color("#FFFFFF") end
	return getClearTypeFromScore(PLAYER_1, score, 2)
end

-- Judge-aware clear type: derives judgment counts from the rescored replay
-- instead of reading the stored (fixed) counts from the score object.
local function getRescoredClearType(j, returnType)
	local score = getCurrentScore()
	if not score then return getClearTypeFromScore(PLAYER_1, nil, returnType) end
	local rescoretable = getRescoreElements()
	if not rescoretable then return getClearTypeFromScore(PLAYER_1, score, returnType) end
	local dvt = rescoretable.dvt
	local perfcount  = getRescoredJudge(dvt, j, 2)
	local greatcount = getRescoredJudge(dvt, j, 3)
	local misscount  = getRescoredJudge(dvt, j, 4) + getRescoredJudge(dvt, j, 5) + getRescoredJudge(dvt, j, 6)
	local grade = getRescoredGrade(j)
	return getClearTypeFromValues(grade, 1, perfcount, greatcount, misscount, returnType)
end

local function getClearRecordLabel(score)
	local recordScore = getCurrentRateRecordScore(score)
	if not recordScore then return "" end
	if isLivePlay() and recordScore == score and score == SCOREMAN:GetMostRecentScore() then
		return "New record!"
	end
	return "Your record: " .. getClearTypeFromScore(PLAYER_1, recordScore, 0)
end

local function continueToSongSelect()
	local top = SCREENMAN:GetTopScreen()
	if top then
		top:Cancel()
	end
end

local function tryPlayReplay(score)
	if not score then return false end
	local top = SCREENMAN:GetTopScreen()
	if top and top.PlayReplay then
		local ok = pcall(function() top:PlayReplay(score) end)
		if ok then
			return true
		end
	end
	if top and top.GetName and top:GetName() == "ScreenEvaluation" then
		setenv("PendingReplayScoreFromEvaluation", score)
		SCREENMAN:SetNewScreen("ScreenSelectMusic")
		return true
	end
	ms.ok("Replay playback is not available from this screen.")
	return false
end

local function retryCurrentChart()
	if not isLivePlay() then return end
	SCREENMAN:SetNewScreen("ScreenGameplay")
end

local function copyTable(inTable)
	local out = {}
	for k, v in pairs(inTable or {}) do
		if type(v) == "table" then
			out[k] = copyTable(v)
		else
			out[k] = v
		end
	end
	return out
end

local evalOverlayOpen = nil
local evalGraphDropdown = nil
local evalChartActionsMode = "main"
local evalPlaylistPage = 1
local evalPlaylistPageSize = 8
local evalGraphSettings = {
	lineMode = "Combo",
	lineColor = "Clear Type",
	scaleToWorstHit = false,
	columnFilter = {},
	scale = 100,
	showTimingWindows = true,
	hoverInfo = "Cumulative",
	sliceWidth = 4,
}

local function normalizeEvalGraphSettings()
	if evalGraphSettings.lineMode == "Standard deviation" then
		evalGraphSettings.lineMode = "SD"
	end
	if evalGraphSettings.lineColor == "Lamp" then
		evalGraphSettings.lineColor = "Clear Type"
	end
	evalGraphSettings.onlyShowReleases = nil
	evalGraphSettings.lineOnTop = nil
	evalGraphSettings.scale = clamp(tonumber(evalGraphSettings.scale) or 100, 5, 100)
	evalGraphSettings.sliceWidth = clamp(math.floor(tonumber(evalGraphSettings.sliceWidth) or 4), 1, 12)
end

local function loadPersistedEvalGraphSettings()
	if not themeConfig or not themeConfig.get_data then return end
	local config = themeConfig:get_data()
	local globalConfig = config and config.global or nil
	local saved = globalConfig and globalConfig.EvalGraphSettings or nil
	if type(saved) ~= "table" then return end
	for k, v in pairs(saved) do
		if type(v) == "table" then
			evalGraphSettings[k] = copyTable(v)
		else
			evalGraphSettings[k] = v
		end
	end
	normalizeEvalGraphSettings()
end

local function persistEvalGraphSettings()
	if not themeConfig or not themeConfig.get_data then return end
	local config = themeConfig:get_data()
	config.global = config.global or {}
	config.global.EvalGraphSettings = copyTable(evalGraphSettings)
	themeConfig:set_dirty()
	themeConfig:save()
end

local function ensureColumnFilter()
	local steps = GAMESTATE:GetCurrentSteps()
	local style = GAMESTATE:GetCurrentStyle()
	local columns = 4
	if steps and steps.GetNumColumns then
		local ok, result = pcall(function() return steps:GetNumColumns() end)
		if ok and result and result > 0 then
			columns = result
		end
	elseif style and style.ColumnsPerPlayer then
		local ok, result = pcall(function() return style:ColumnsPerPlayer() end)
		if ok and result and result > 0 then
			columns = result
		end
	end
	for i = 1, columns do
		if evalGraphSettings.columnFilter[i] == nil then
			evalGraphSettings.columnFilter[i] = true
		end
	end
	for i = columns + 1, #evalGraphSettings.columnFilter do
		evalGraphSettings.columnFilter[i] = nil
	end
end

local function broadcastEvalGraphSettings()
	normalizeEvalGraphSettings()
	ensureColumnFilter()
	persistEvalGraphSettings()
	_G.ResetDayEvalGraphSettings = copyTable(evalGraphSettings)
	MESSAGEMAN:Broadcast("EvalGraphSettingsChanged", {settings = copyTable(evalGraphSettings)})
end

local function setEvalOverlayOpen(name)
	evalOverlayOpen = name
	if name ~= "graph" then
		evalGraphDropdown = nil
	end
	if name ~= "chartActions" then
		evalChartActionsMode = "main"
		evalPlaylistPage = 1
	end
	MESSAGEMAN:Broadcast("EvalOverlayStateChanged", {open = evalOverlayOpen, graphDropdown = evalGraphDropdown, chartActionsMode = evalChartActionsMode})
end

local function setEvalGraphDropdown(name)
	if evalGraphDropdown == name then
		evalGraphDropdown = nil
	else
		evalGraphDropdown = name
	end
	MESSAGEMAN:Broadcast("EvalOverlayStateChanged", {open = evalOverlayOpen, graphDropdown = evalGraphDropdown, chartActionsMode = evalChartActionsMode})
end

local function getEvalPlaylists()
	local playlists = SONGMAN:GetPlaylists() or {}
	table.sort(playlists, function(a, b)
		local aName = a and a.GetName and a:GetName() or ""
		local bName = b and b.GetName and b:GetName() or ""
		return aName:lower() < bName:lower()
	end)
	return playlists
end

local function getCurrentChartKey()
	local steps = GAMESTATE:GetCurrentSteps()
	if not steps then return nil end
	local ok, chartKey = pcall(function() return steps:GetChartKey() end)
	if ok then
		return chartKey
	end
	return nil
end

local function findPlaylistByName(name)
	if not name or name == "" then return nil end
	for _, playlist in ipairs(getEvalPlaylists()) do
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
			local ok, result = pcall(method, target, ...)
			if ok then
				return true, result, methodName
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
	local ok = false
	ok = tryCallMethod(SONGMAN, {"CreatePlaylist", "AddPlaylist", "MakePlaylist", "NewPlaylist"}, name)
	if ok then
		playlist = findPlaylistByName(name)
	end
	return playlist ~= nil, playlist
end

local function addCurrentChartToPlaylist(name)
 	local chartKey = getCurrentChartKey()
 	local song = GAMESTATE:GetCurrentSong()
 	local steps = GAMESTATE:GetCurrentSteps()
 	if not song or not steps or not chartKey then
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
 	if not ok then ok = tryCallMethod(playlist, {"AddSong"}, song, steps, rate) end
 	if not ok then ok = tryCallMethod(playlist, {"AddSong"}, song, steps) end
 	if not ok then ok = tryCallMethod(playlist, {"AddSteps"}, steps, rate) end
 	if not ok then ok = tryCallMethod(playlist, {"AddSteps"}, steps) end
 	if not ok then
 		ms.ok("Failed to add chart to '" .. name .. "'.")
 		return false
 	end
 	MESSAGEMAN:Broadcast("EvalChartActionChanged")
 	ms.ok("Added chart to '" .. name .. "'.")
 	return true
 end
 
 local function removeCurrentChartFromPlaylist(name)
 	local playlist = findPlaylistByName(name)
 	local chartKey = getCurrentChartKey()
 	if not playlist or not chartKey then return false end
 	local exists, index = playlistContainsChart(playlist, chartKey)
 	if not exists or not index then return false end
 	local ok = tryCallMethod(playlist, {"DeleteChart"}, index)
 	if ok then
 		MESSAGEMAN:Broadcast("EvalChartActionChanged")
 	end
 	return ok
 end
 
 local function isCurrentChartFavorited()
 	local song = GAMESTATE:GetCurrentSong()
 	if song and song.IsFavorited then
 		local ok, result = pcall(function() return song:IsFavorited() end)
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
 	local song = GAMESTATE:GetCurrentSong()
 	local desired = not isCurrentChartFavorited()
 	if song then
 		local ok = false
 		if desired then
 			ok = tryCallMethod(song, {"SetFavorited"}, true)
 			if not ok then ok = tryCallMethod(song, {"AddToFavorites", "Favorite", "SetFavorite"}) end
 		else
 			ok = tryCallMethod(song, {"SetFavorited"}, false)
 			if not ok then ok = tryCallMethod(song, {"RemoveFromFavorites", "Unfavorite", "SetFavorite"}, false) end
 		end
 		if ok then
 			MESSAGEMAN:Broadcast("EvalChartActionChanged")
 			ms.ok(desired and "Chart favourited." or "Chart unfavourited.")
 			return true
 		end
 	end
 	local okCreate = ensurePlaylistExists("Favorites")
 	if not okCreate then
 		ms.ok("Could not access Favorites.")
 		return false
 	end
 	if desired then
 		return addCurrentChartToPlaylist("Favorites")
 	end
 	local removed = removeCurrentChartFromPlaylist("Favorites")
 	if removed then
 		ms.ok("Chart unfavourited.")
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
 			evalChartActionsMode = "playlist"
 			MESSAGEMAN:Broadcast("EvalOverlayStateChanged", {open = evalOverlayOpen, graphDropdown = evalGraphDropdown, chartActionsMode = evalChartActionsMode})
 		end
 end)
end
 
loadPersistedEvalGraphSettings()
normalizeEvalGraphSettings()
ensureColumnFilter()
_G.ResetDayEvalGraphSettings = copyTable(evalGraphSettings)
 
t[#t + 1] = LoadFont("Common Large") .. {
	Name = "SongTitleHeader",
	InitCommand = function(self)
		self:xy(10, 10):halign(0):valign(0):zoom(0.65):diffuse(color("#FFFFFF"))
		self:maxwidth(620)
		self:settext("")
	end,
	OnCommand = function(self)
		local song = GAMESTATE:GetCurrentSong()
		if song then
			self:settext(song:GetDisplayMainTitle() .. (song:GetDisplaySubTitle() ~= "" and " - " .. song:GetDisplaySubTitle() or ""))
		end
	end,
}

t[#t + 1] = LoadFont("Common Large") .. {
	Name = "StepInfoHeader",
	InitCommand = function(self)
		self:xy(10, 36):halign(0):valign(0):zoom(0.4):maxwidth(620)
	end,
	BeginCommand = function(self)
		self:queuecommand("Set"):diffuse(color("#FFFFFF"))
	end,
	SetCommand = function(self)
		self:settext(getStepHeaderText())
	end
}

t[#t + 1] = LoadFont("Common Large") .. {
	Name = "PackCreditHeader",
	InitCommand = function(self)
		self:xy(10, 55):halign(0):valign(0):zoom(0.3):maxwidth(620)
		self:diffuse(color("#FFFFFF"))
	end,
	BeginCommand = function(self)
		self:queuecommand("Set")
	end,
	SetCommand = function(self)
		self:settext(getPackCreditText())
	end
}

t[#t + 1] = LoadFont("Common Large") .. {
	Name = "EvalClock",
	InitCommand = function(self)
		self:xy(SCREEN_WIDTH - 10, 35):halign(1):valign(0):zoom(0.30)
		self:diffuse(color("#FFFFFF"))
	end,
	UpdateCommand = function(self)
		self:settext(os.date("%m/%d/%Y %I:%M:%S %p"))
		self:sleep(1):queuecommand("Update")
	end,
	OnCommand = function(self)
		self:queuecommand("Update")
	end
}

t[#t + 1] = LoadFont("Common Large") .. {
	Name = "EvalSessionTime",
	InitCommand = function(self)
		self:xy(SCREEN_WIDTH - 10, 49):halign(1):valign(0):zoom(0.24)
		self:diffuse(color("#FFFFFF"))
	end,
	UpdateCommand = function(self)
		local profile = GetPlayerOrMachineProfile(PLAYER_1)
		local sessionSeconds = profile and profile:GetTotalSessionSeconds() or 0
		self:settextf("Current session: %s", formatSessionTime(sessionSeconds))
		self:sleep(1):queuecommand("Update")
	end,
	OnCommand = function(self)
		self:queuecommand("Update")
	end
}

t[#t + 1] = Def.ActorFrame {
	Name = "EvalTopCards",
	Def.ActorFrame {
		InitCommand = function(self)
			self:xy(SCREEN_WIDTH - 505, 75)
		end,
		Def.Quad {
			InitCommand = function(self)
				self:zoomto(100, 70):halign(0):valign(0):diffuse(color("#202020")):diffusealpha(0.88)
			end,
		},
		Def.Quad {
			InitCommand = function(self)
				self:xy(0, 46):zoomto(100, 24):halign(0):valign(0):diffuse(color("#25d0ff")):diffusealpha(0.35)
			end,
			SetCommand = function(self)
				if not usingCustomWindows then
					local grade = getDisplayedGrade(true)
					self:diffuse(getGradeColor(grade))
				end
				self:diffusealpha(0.35)
			end,
			BeginCommand = function(self) self:queuecommand("Set") end,
			ScoreChangedMessageCommand = function(self) self:queuecommand("Set") end,
			RecalculateGraphsMessageCommand = function(self, params)
				if params and params.judge then
					judge = params.judge
				end
				self:queuecommand("Set")
			end,
		},
		LoadFont("Common Large") .. {
			InitCommand = function(self)
				self:xy(50, 22):halign(0.5):valign(0.5):zoom(0.85)
				self:maxwidth(90 / 0.85)
			end,
			SetCommand = function(self)
				if usingCustomWindows then
					self:settext("")
					return
				end
				local grade = getDisplayedGrade(true)
				self:settext(getGradeStrings(grade))
				self:diffuse(getGradeColor(grade))
			end,
			BeginCommand = function(self) self:queuecommand("Set") end,
			ScoreChangedMessageCommand = function(self) self:queuecommand("Set") end,
			RecalculateGraphsMessageCommand = function(self, params)
				if params and params.judge then
					judge = params.judge
				end
				self:queuecommand("Set")
			end,
		},
	},
	Def.ActorFrame {
		InitCommand = function(self)
			self:xy(SCREEN_WIDTH - 395, 75)
		end,
		Def.Quad {
			InitCommand = function(self)
				self:zoomto(210, 70):halign(0):valign(0):diffuse(color("#202020")):diffusealpha(0.88)
			end,
		},
		Def.Quad {
			InitCommand = function(self)
				self:xy(0, 46):zoomto(210, 24):halign(0):valign(0):diffuse(color("#25d0ff")):diffusealpha(0.35)
			end,
			SetCommand = function(self)
				local grade = getDisplayedGrade(true)
				if not usingCustomWindows then
					self:diffuse(getGradeColor(grade))
				end
				self:diffusealpha(0.35)
			end,
			BeginCommand = function(self) self:queuecommand("Set") end,
			ScoreChangedMessageCommand = function(self) self:queuecommand("Set") end,
			RecalculateGraphsMessageCommand = function(self, params)
				if params and params.judge then
					judge = params.judge
				end
				self:queuecommand("Set")
			end,
			LoadedCustomWindowMessageCommand = function(self)
				usingCustomWindows = true
				lastSnapshot = REPLAYS:GetActiveReplay():GetLastReplaySnapshot()
				self:queuecommand("Set")
			end,
			UnloadedCustomWindowMessageCommand = function(self)
				usingCustomWindows = false
				self:queuecommand("Set")
			end,
		},
		LoadFont("Common Large") .. {
			InitCommand = function(self)
				self:xy(105, 22):halign(0.5):valign(0.5):zoom(0.7)
			end,
			SetCommand = function(self)
				local score = getCurrentScore()
				local grade = getDisplayedGrade(true)
				self:settext(getDisplayedPercentText(score, true))
				if not usingCustomWindows then
					self:diffuse(getGradeColor(grade))
				end
			end,
			BeginCommand = function(self) self:queuecommand("Set") end,
			ScoreChangedMessageCommand = function(self) self:queuecommand("Set") end,
			RecalculateGraphsMessageCommand = function(self, params)
				if params and params.judge then
					judge = params.judge
				end
				self:queuecommand("Set")
			end,
			LoadedCustomWindowMessageCommand = function(self)
				usingCustomWindows = true
				lastSnapshot = REPLAYS:GetActiveReplay():GetLastReplaySnapshot()
				self:queuecommand("Set")
			end,
			UnloadedCustomWindowMessageCommand = function(self)
				usingCustomWindows = false
				self:queuecommand("Set")
			end,
		},
		LoadFont("Common Large") .. {
			InitCommand = function(self)
				self:xy(105, 58):halign(0.5):valign(0.5):zoom(0.26):diffuse(color("#FFFFFF"))
				self:maxwidth(200 / 0.26)
			end,
			SetCommand = function(self)
				self:settext(getRecordLabel(getCurrentScore()))
			end,
			BeginCommand = function(self) self:queuecommand("Set") end,
			ScoreChangedMessageCommand = function(self) self:queuecommand("Set") end,
		},
	},
	Def.ActorFrame {
		InitCommand = function(self)
			self:xy(SCREEN_WIDTH - 175, 75)
		end,
		Def.Quad {
			InitCommand = function(self)
				self:zoomto(165, 70):halign(0):valign(0):diffuse(color("#202020")):diffusealpha(0.88)
			end,
		},
		Def.Quad {
			InitCommand = function(self)
				self:xy(0, 46):zoomto(165, 24):halign(0):valign(0):diffuse(color("#25d0ff")):diffusealpha(0.35)
			end,
			SetCommand = function(self)
				if not usingCustomWindows then
					self:diffuse(getRescoredClearType(judge, 2))
				end
				self:diffusealpha(0.35)
			end,
			BeginCommand = function(self) self:queuecommand("Set") end,
			ScoreChangedMessageCommand = function(self) self:queuecommand("Set") end,
			RecalculateGraphsMessageCommand = function(self, params)
				if params and params.judge then
					judge = params.judge
				end
				self:queuecommand("Set")
			end,
		},
		LoadFont("Common Large") .. {
			InitCommand = function(self)
				self:xy(82.5, 22):halign(0.5):valign(0.5):zoom(0.7)
				self:maxwidth(160 / 0.7)
			end,
			SetCommand = function(self)
				self:settext(getRescoredClearType(judge, 0))
				if not usingCustomWindows then
					self:diffuse(getRescoredClearType(judge, 2))
				end
			end,
			BeginCommand = function(self) self:queuecommand("Set") end,
			ScoreChangedMessageCommand = function(self) self:queuecommand("Set") end,
			RecalculateGraphsMessageCommand = function(self, params)
				if params and params.judge then
					judge = params.judge
				end
				self:queuecommand("Set")
			end,
		},
		LoadFont("Common Large") .. {
			InitCommand = function(self)
				self:xy(82.5, 58):halign(0.5):valign(0.5):zoom(0.26):diffuse(color("#FFFFFF"))
				self:maxwidth(160 / 0.26)
			end,
			SetCommand = function(self)
				self:settext(getClearRecordLabel(getCurrentScore()))
			end,
			BeginCommand = function(self) self:queuecommand("Set") end,
			ScoreChangedMessageCommand = function(self) self:queuecommand("Set") end,
		},
	},
}

local plotStart = 355
local plotWidth = SCREEN_WIDTH - 370
local gap = 6
local bw = (plotWidth - (gap * 3)) / 4
local graphLineModes = {"None", "Combo", "Mean", "SD", "Accuracy", "MA", "PA"}
local graphLineColors = {"White", "Clear Type", "Grade"}
local graphHoverModes = {"Cumulative", "Slice"}

local interludeIconTargetSize = 48

local function normalizeInterludeIcon(self, visualScale)
	local width = self:GetWidth()
	local height = self:GetHeight()
	if width > 0 and height > 0 then
		self:zoom((interludeIconTargetSize / math.max(width, height)) * (visualScale or 1))
	end
end

local function setGraphSetting(key, value)
	if key == "lineMode" and value == "Standard deviation" then
		value = "SD"
	end
	if key == "lineColor" and value == "Lamp" then
		value = "Clear Type"
	end
	evalGraphSettings[key] = value
	broadcastEvalGraphSettings()
	MESSAGEMAN:Broadcast("EvalOverlayStateChanged", {open = evalOverlayOpen, graphDropdown = evalGraphDropdown, chartActionsMode = evalChartActionsMode})
end

local function toggleColumnFilter(index)
	ensureColumnFilter()
	evalGraphSettings.columnFilter[index] = not evalGraphSettings.columnFilter[index]
	local enabledCount = 0
	for _, enabled in ipairs(evalGraphSettings.columnFilter) do
		if enabled then enabledCount = enabledCount + 1 end
	end
	if enabledCount == 0 then
		evalGraphSettings.columnFilter[index] = true
	end
	broadcastEvalGraphSettings()
	MESSAGEMAN:Broadcast("EvalOverlayStateChanged", {open = evalOverlayOpen, graphDropdown = evalGraphDropdown, chartActionsMode = evalChartActionsMode})
end

local function adjustGraphNumber(key, delta, minValue, maxValue)
	setGraphSetting(key, clamp((evalGraphSettings[key] or 0) + delta, minValue, maxValue))
end

local function playlistPageCount()
	return math.max(1, math.ceil(#getEvalPlaylists() / evalPlaylistPageSize))
end

local function updatePlaylistPage(delta)
	evalPlaylistPage = clamp(evalPlaylistPage + delta, 1, playlistPageCount())
	MESSAGEMAN:Broadcast("EvalOverlayStateChanged", {open = evalOverlayOpen, graphDropdown = evalGraphDropdown, chartActionsMode = evalChartActionsMode})
end

local function overlayButton(x, label, activeName, mouseDown, icon)
	local hasIcon = icon ~= nil and icon ~= ""
	return Def.ActorFrame {
		InitCommand = function(self) self:xy(x, SCREEN_HEIGHT - 31) end,
		UIElements.QuadButton(1, 1) .. {
			InitCommand = function(self)
				self:zoomto(bw, 24):halign(0):valign(0):diffuse(color("#1c1f26")):diffusealpha(0.88)
			end,
			SetCommand = function(self)
				local active = activeName ~= nil and evalOverlayOpen == activeName
				self:diffuse(active and color("#5a4a24") or color("#1c1f26"))
				self:diffusealpha(active and 0.96 or 0.88)
			end,
			EvalOverlayStateChangedMessageCommand = function(self) self:queuecommand("Set") end,
			MouseOverCommand = function(self) self:diffusealpha(1) end,
			MouseOutCommand = function(self) self:queuecommand("Set") end,
			MouseDownCommand = mouseDown,
			LoadedCustomWindowMessageCommand = function(self)
				if label == "Custom Scoring" then
					self:diffuse(color("#1a3a1a")):diffusealpha(0.95)
				end
			end,
			UnloadedCustomWindowMessageCommand = function(self)
				if label == "Custom Scoring" then
					self:queuecommand("Set")
				end
			end,
		},
		hasIcon and Def.Sprite {
			Texture = THEME:GetPathG("", "Interlude Icons/" .. icon),
			InitCommand = function(self)
				self:xy(16, 12):halign(0.5):valign(0.5):diffuse(color("#FFFFFF"))
			end,
			OnCommand = function(self)
				normalizeInterludeIcon(self, 0.24)
			end,
			SetCommand = function(self)
				local active = activeName ~= nil and evalOverlayOpen == activeName
				self:diffuse(active and color("#f6d67a") or color("#FFFFFF"))
			end,
			EvalOverlayStateChangedMessageCommand = function(self) self:queuecommand("Set") end,
		} or nil,
		LoadFont("Common Normal") .. {
			InitCommand = function(self)
				self:xy(hasIcon and (bw / 2 + 10) or bw / 2, 12):halign(0.5):valign(0.5):zoom(0.4):settext(label)
				self:diffuse(color("#FFFFFF"))
			end,
			SetCommand = function(self)
				local active = activeName ~= nil and evalOverlayOpen == activeName
				self:diffuse(active and color("#f6d67a") or color("#FFFFFF"))
			end,
			EvalOverlayStateChangedMessageCommand = function(self) self:queuecommand("Set") end,
			LoadedCustomWindowMessageCommand = function(self)
				if label == "Custom Scoring" then
					self:diffuse(getMainColor("positive"))
				end
			end,
			UnloadedCustomWindowMessageCommand = function(self)
				if label == "Custom Scoring" then
					self:queuecommand("Set")
				end
			end,
		}
	}
end

local function tickButton(x, y, getter, onClick)
	return Def.ActorFrame {
		InitCommand = function(self) self:xy(x, y) end,
		UIElements.QuadButton(1, 1) .. {
			InitCommand = function(self) self:zoomto(20, 20):halign(0):valign(0):diffusealpha(0) end,
			MouseDownCommand = function(self, params) if params.event == "DeviceButton_left mouse button" then onClick() end end,
		},
		Def.Sprite {
			Texture = THEME:GetPathG("", "Interlude Icons/check-solid.png"),
			InitCommand = function(self)
				self:xy(10, 10):halign(0.5):valign(0.5):diffuse(color("#FFFFFF"))
			end,
			OnCommand = function(self)
				normalizeInterludeIcon(self, 0.18)
			end,
			SetCommand = function(self)
				self:visible(getter())
			end,
			EvalOverlayStateChangedMessageCommand = function(self) self:queuecommand("Set") end,
		},
		Def.Sprite {
			Texture = THEME:GetPathG("", "Interlude Icons/xmark-solid.png"),
			InitCommand = function(self)
				self:xy(10, 10):halign(0.5):valign(0.5):diffuse(color("#BBBBBB"))
			end,
			OnCommand = function(self)
				normalizeInterludeIcon(self, 0.18)
			end,
			SetCommand = function(self)
				self:visible(not getter())
			end,
			EvalOverlayStateChangedMessageCommand = function(self) self:queuecommand("Set") end,
		}
	}
end

local function dropdownFrame(x, y, width, settingKey, options)
	local frame = Def.ActorFrame {
		InitCommand = function(self) self:xy(x, y):visible(false):draworder(250) end,
		SetCommand = function(self)
			self:visible(evalGraphDropdown == settingKey)
		end,
		EvalOverlayStateChangedMessageCommand = function(self) self:queuecommand("Set") end,
	}
	for i, optionValue in ipairs(options) do
		frame[#frame + 1] = Def.ActorFrame {
			InitCommand = function(self) self:y((i - 1) * 36) end,
			UIElements.QuadButton(1, 1) .. {
				InitCommand = function(self)
					self:zoomto(width, 36):halign(0):valign(0):diffuse(color("#8b6a36")):diffusealpha(0.96)
				end,
				SetCommand = function(self)
					self:diffuse(evalGraphSettings[settingKey] == optionValue and color("#c2a579") or color("#8b6a36"))
				end,
				EvalOverlayStateChangedMessageCommand = function(self) self:queuecommand("Set") end,
				MouseDownCommand = function(self, params)
					if params.event == "DeviceButton_left mouse button" then
						setEvalGraphDropdown(nil)
						setGraphSetting(settingKey, optionValue)
					end
				end,
			},
			LoadFont("Common Large") .. {
				InitCommand = function(self)
					self:xy(12, 18):halign(0):valign(0.5):zoom(0.38):maxwidth((width - 20) / 0.38)
				end,
				SetCommand = function(self)
					self:settext(optionValue)
				end,
				EvalOverlayStateChangedMessageCommand = function(self) self:queuecommand("Set") end,
			}
		}
	end
	return frame
end

local graphOverlayWidth = 276
local graphOverlayHeight = 520
local graphOverlayLabelX = 20
local graphOverlayValueX = 154
local graphOverlayValueWidth = 112
local graphOverlayDropdownWidth = 132
local graphOverlayToggleX = 226
local graphOverlayAdjustLeftX = 210
local graphOverlayAdjustRightX = 242
local graphOverlayColumnStartX = 154
local graphOverlayColumnSpacing = 28
local graphOverlayX = 18
local graphOverlayY = 72

local function isMouseOverGraphOverlay()
	local x = INPUTFILTER:GetMouseX()
	local y = INPUTFILTER:GetMouseY()
	return x >= graphOverlayX and x <= graphOverlayX + graphOverlayWidth and y >= graphOverlayY and y <= graphOverlayY + graphOverlayHeight
end

local function evalGraphInput(event)
	if evalOverlayOpen ~= "graph" then return end
	if event.type ~= "InputEventType_FirstPress" then return end
	if not event.DeviceInput then return end
	if not isMouseOverGraphOverlay() then return end
	if event.DeviceInput.button == "DeviceButton_mousewheel up" then
		adjustGraphNumber("scale", 5, 5, 100)
		return true
	elseif event.DeviceInput.button == "DeviceButton_mousewheel down" then
		adjustGraphNumber("scale", -5, 5, 100)
		return true
	end
end

t.BeginCommand = function()
	SCREENMAN:GetTopScreen():AddInputCallback(evalGraphInput)
	_G.ResetDayEvalGraphSettings = copyTable(evalGraphSettings)
	MESSAGEMAN:Broadcast("EvalGraphSettingsChanged", {settings = copyTable(evalGraphSettings)})
end

local graphOverlay = Def.ActorFrame {
	Name = "GraphOverlay",
	InitCommand = function(self) self:xy(graphOverlayX, graphOverlayY):visible(false) end,
	SetCommand = function(self)
		self:visible(evalOverlayOpen == "graph")
	end,
	EvalOverlayStateChangedMessageCommand = function(self) self:queuecommand("Set") end,
	Def.Quad {
		InitCommand = function(self)
			self:zoomto(graphOverlayWidth, graphOverlayHeight):halign(0):valign(0):diffuse(color("#151515")):diffusealpha(0.92)
		end,
	},
	LoadFont("Common Large") .. {
		InitCommand = function(self)
			self:xy(20, 24):halign(0):valign(0.5):zoom(0.52):settext("Graph settings")
		end,
	},
	LoadFont("Common Large") .. {
		InitCommand = function(self) self:xy(graphOverlayLabelX, 68):halign(0):valign(0.5):zoom(0.38):settext("Line mode:") end,
	},
	UIElements.QuadButton(1, 1) .. {
		InitCommand = function(self) self:xy(graphOverlayValueX, 54):zoomto(graphOverlayValueWidth, 28):halign(0):valign(0):diffuse(color("#73683b")):diffusealpha(0.55) end,
	},
	LoadFont("Common Large") .. {
		InitCommand = function(self) self:xy(graphOverlayValueX + 8, 68):halign(0):valign(0.5):zoom(0.34) end,
		SetCommand = function(self) self:settext(evalGraphSettings.lineMode) end,
		EvalOverlayStateChangedMessageCommand = function(self) self:queuecommand("Set") end,
	},
	UIElements.QuadButton(1, 1) .. {
		InitCommand = function(self) self:xy(graphOverlayValueX - 6, 50):zoomto(graphOverlayValueWidth + 12, 36):halign(0):valign(0):diffusealpha(0) end,
		MouseDownCommand = function(self, params) if params.event == "DeviceButton_left mouse button" then setEvalGraphDropdown("lineMode") end end,
	},
	dropdownFrame(graphOverlayValueX, 84, graphOverlayDropdownWidth, "lineMode", graphLineModes),
	LoadFont("Common Large") .. {
		InitCommand = function(self) self:xy(graphOverlayLabelX, 102):halign(0):valign(0.5):zoom(0.38):settext("Line color:") end,
	},
	UIElements.QuadButton(1, 1) .. {
		InitCommand = function(self) self:xy(graphOverlayValueX, 88):zoomto(graphOverlayValueWidth, 28):halign(0):valign(0):diffuse(color("#73683b")):diffusealpha(0.55) end,
	},
	LoadFont("Common Large") .. {
		InitCommand = function(self) self:xy(graphOverlayValueX + 8, 102):halign(0):valign(0.5):zoom(0.34) end,
		SetCommand = function(self) self:settext(evalGraphSettings.lineColor) end,
		EvalOverlayStateChangedMessageCommand = function(self) self:queuecommand("Set") end,
	},
	UIElements.QuadButton(1, 1) .. {
		InitCommand = function(self) self:xy(graphOverlayValueX, 88):zoomto(graphOverlayValueWidth, 28):halign(0):valign(0):diffusealpha(0) end,
		MouseDownCommand = function(self, params) if params.event == "DeviceButton_left mouse button" then setEvalGraphDropdown("lineColor") end end,
	},
	dropdownFrame(graphOverlayValueX, 118, graphOverlayDropdownWidth, "lineColor", graphLineColors),
	LoadFont("Common Large") .. {
		InitCommand = function(self) self:xy(graphOverlayLabelX, 136):halign(0):valign(0.5):zoom(0.38):settext("Scale to worst hit:") end,
	},
	tickButton(graphOverlayToggleX, 122, function() return evalGraphSettings.scaleToWorstHit end, function() setGraphSetting("scaleToWorstHit", not evalGraphSettings.scaleToWorstHit) end),
	LoadFont("Common Large") .. {
		InitCommand = function(self) self:xy(graphOverlayLabelX, 170):halign(0):valign(0.5):zoom(0.38):settext("Column filter:") end,
	},
	LoadFont("Common Large") .. {
		InitCommand = function(self) self:xy(graphOverlayLabelX, 214):halign(0):valign(0.5):zoom(0.38):settext("Scale:") end,
	},
	LoadFont("Common Large") .. {
		InitCommand = function(self) self:xy(graphOverlayValueX, 214):halign(0):valign(0.5):zoom(0.38) end,
		SetCommand = function(self) self:settext(string.format("%d%%", evalGraphSettings.scale)) end,
		EvalOverlayStateChangedMessageCommand = function(self) self:queuecommand("Set") end,
	},
	UIElements.QuadButton(1, 1) .. { InitCommand = function(self) self:xy(graphOverlayAdjustLeftX, 202):zoomto(18, 18):halign(0):valign(0):diffusealpha(0) end, MouseDownCommand = function(self, params) if params.event == "DeviceButton_left mouse button" then adjustGraphNumber("scale", -5, 5, 100) end end },
	LoadFont("Common Large") .. { InitCommand = function(self) self:xy(graphOverlayAdjustLeftX + 9, 211):halign(0.5):valign(0.5):zoom(0.32):settext("-") end },
	UIElements.QuadButton(1, 1) .. { InitCommand = function(self) self:xy(graphOverlayAdjustRightX, 202):zoomto(18, 18):halign(0):valign(0):diffusealpha(0) end, MouseDownCommand = function(self, params) if params.event == "DeviceButton_left mouse button" then adjustGraphNumber("scale", 5, 5, 100) end end },
	LoadFont("Common Large") .. { InitCommand = function(self) self:xy(graphOverlayAdjustRightX + 9, 211):halign(0.5):valign(0.5):zoom(0.32):settext("+") end },
	LoadFont("Common Large") .. {
		InitCommand = function(self) self:xy(graphOverlayLabelX, 248):halign(0):valign(0.5):zoom(0.38):settext("Show timing windows:") end,
	},
	tickButton(graphOverlayToggleX, 234, function() return evalGraphSettings.showTimingWindows end, function() setGraphSetting("showTimingWindows", not evalGraphSettings.showTimingWindows) end),
	LoadFont("Common Large") .. {
		InitCommand = function(self) self:xy(graphOverlayLabelX, 292):halign(0):valign(0.5):zoom(0.38):settext("Hover info:") end,
		SetCommand = function(self) self:diffuse(evalGraphDropdown == "hoverInfo" and color("#f6d67a") or color("#FFFFFF")) end,
		EvalOverlayStateChangedMessageCommand = function(self) self:queuecommand("Set") end,
	},
	UIElements.QuadButton(1, 1) .. {
		InitCommand = function(self) self:xy(graphOverlayValueX, 278):zoomto(graphOverlayValueWidth, 28):halign(0):valign(0):diffuse(color("#73683b")):diffusealpha(0.55) end,
	},
	LoadFont("Common Large") .. {
		InitCommand = function(self) self:xy(graphOverlayValueX + 8, 292):halign(0):valign(0.5):zoom(0.34) end,
		SetCommand = function(self) self:settext(evalGraphSettings.hoverInfo) end,
		EvalOverlayStateChangedMessageCommand = function(self) self:queuecommand("Set") end,
	},
	UIElements.QuadButton(1, 1) .. {
		InitCommand = function(self) self:xy(graphOverlayValueX, 278):zoomto(graphOverlayValueWidth, 28):halign(0):valign(0):diffusealpha(0) end,
		MouseDownCommand = function(self, params) if params.event == "DeviceButton_left mouse button" then setEvalGraphDropdown("hoverInfo") end end,
	},
	dropdownFrame(graphOverlayValueX, 308, graphOverlayDropdownWidth, "hoverInfo", graphHoverModes),
	LoadFont("Common Large") .. {
		InitCommand = function(self) self:xy(graphOverlayLabelX, 336):halign(0):valign(0.5):zoom(0.38):settext("Slice width:") end,
	},
	LoadFont("Common Large") .. {
		InitCommand = function(self) self:xy(graphOverlayValueX, 336):halign(0):valign(0.5):zoom(0.38) end,
		SetCommand = function(self) self:settext(string.format("%d", evalGraphSettings.sliceWidth)) end,
		EvalOverlayStateChangedMessageCommand = function(self) self:queuecommand("Set") end,
	},
	UIElements.QuadButton(1, 1) .. { InitCommand = function(self) self:xy(graphOverlayAdjustLeftX, 324):zoomto(18, 18):halign(0):valign(0):diffusealpha(0) end, MouseDownCommand = function(self, params) if params.event == "DeviceButton_left mouse button" then adjustGraphNumber("sliceWidth", -1, 1, 12) end end },
	LoadFont("Common Large") .. { InitCommand = function(self) self:xy(graphOverlayAdjustLeftX + 9, 333):halign(0.5):valign(0.5):zoom(0.32):settext("-") end },
	UIElements.QuadButton(1, 1) .. { InitCommand = function(self) self:xy(graphOverlayAdjustRightX, 324):zoomto(18, 18):halign(0):valign(0):diffusealpha(0) end, MouseDownCommand = function(self, params) if params.event == "DeviceButton_left mouse button" then adjustGraphNumber("sliceWidth", 1, 1, 12) end end },
	LoadFont("Common Large") .. { InitCommand = function(self) self:xy(graphOverlayAdjustRightX + 9, 333):halign(0.5):valign(0.5):zoom(0.32):settext("+") end },
}

for i = 1, #evalGraphSettings.columnFilter do
	graphOverlay[#graphOverlay + 1] = Def.ActorFrame {
		InitCommand = function(self) self:xy(graphOverlayColumnStartX + ((i - 1) % 4) * graphOverlayColumnSpacing, 156 + math.floor((i - 1) / 4) * 26) end,
		UIElements.QuadButton(1, 1) .. {
			InitCommand = function(self) self:zoomto(20, 20):halign(0):valign(0):diffusealpha(0) end,
			MouseDownCommand = function(self, params) if params.event == "DeviceButton_left mouse button" then toggleColumnFilter(i) end end,
		},
		Def.Sprite {
			Texture = THEME:GetPathG("", "Interlude Icons/check-solid.png"),
			InitCommand = function(self)
				self:xy(10, 10):halign(0.5):valign(0.5):diffuse(color("#FFFFFF"))
			end,
			OnCommand = function(self)
				normalizeInterludeIcon(self, 0.18)
			end,
			SetCommand = function(self)
				ensureColumnFilter()
				self:visible(evalGraphSettings.columnFilter[i])
			end,
			EvalOverlayStateChangedMessageCommand = function(self) self:queuecommand("Set") end,
		},
		Def.Sprite {
			Texture = THEME:GetPathG("", "Interlude Icons/xmark-solid.png"),
			InitCommand = function(self)
				self:xy(10, 10):halign(0.5):valign(0.5):diffuse(color("#BBBBBB"))
			end,
			OnCommand = function(self)
				normalizeInterludeIcon(self, 0.18)
			end,
			SetCommand = function(self)
				ensureColumnFilter()
				self:visible(not evalGraphSettings.columnFilter[i])
			end,
			EvalOverlayStateChangedMessageCommand = function(self) self:queuecommand("Set") end,
		}
	}
end

local function playlistRow(index)
	return Def.ActorFrame {
		Name = "PlaylistRow" .. index,
		InitCommand = function(self) self:xy(0, -48 + (index - 1) * 24) end,
		SetCommand = function(self)
			local playlists = getEvalPlaylists()
			self.playlist = playlists[((evalPlaylistPage - 1) * evalPlaylistPageSize) + index]
			self:visible(evalChartActionsMode == "playlist" and self.playlist ~= nil)
			self:GetChild("Label"):queuecommand("Set")
		end,
		EvalOverlayStateChangedMessageCommand = function(self) self:queuecommand("Set") end,
		EvalChartActionChangedMessageCommand = function(self) self:queuecommand("Set") end,
		UIElements.QuadButton(1, 1) .. {
			InitCommand = function(self) self:zoomto(bw, 22):halign(0):valign(0):diffuse(color("#1f2833")):diffusealpha(0.94) end,
			MouseDownCommand = function(self, params)
				if params.event == "DeviceButton_left mouse button" then
					local row = self:GetParent()
					if row.playlist then
						addCurrentChartToPlaylist(row.playlist:GetName())
					end
				end
			end,
		},
		LoadFont("Common Large") .. {
			Name = "Label",
			InitCommand = function(self) self:xy(10, 11):halign(0):valign(0.5):zoom(0.28) end,
			SetCommand = function(self)
				local row = self:GetParent()
				local name = row.playlist and row.playlist:GetName() or ""
				local inPlaylist = row.playlist and playlistContainsChart(row.playlist, getCurrentChartKey()) or false
				self:settext(name .. (inPlaylist and " (Added)" or ""))
			end,
		}
	}
end

local chartActionsOverlay = Def.ActorFrame {
	Name = "ChartActionsOverlay",
	InitCommand = function(self) self:xy(plotStart + bw + gap, SCREEN_HEIGHT - 212):visible(false) end,
	SetCommand = function(self)
		self:visible(evalOverlayOpen == "chartActions")
	end,
	EvalOverlayStateChangedMessageCommand = function(self) self:queuecommand("Set") end,
	Def.Quad {
		InitCommand = function(self) self:zoomto(bw, 176):halign(0):valign(1):diffuse(color("#171717")):diffusealpha(0.95) end,
	},
	LoadFont("Common Large") .. {
		InitCommand = function(self) self:xy(12, -152):halign(0):valign(0.5):zoom(0.36) end,
		SetCommand = function(self) self:settext(evalChartActionsMode == "playlist" and "Add to Playlist" or "Chart actions") end,
		EvalOverlayStateChangedMessageCommand = function(self) self:queuecommand("Set") end,
	},
	Def.ActorFrame {
		SetCommand = function(self) self:visible(evalChartActionsMode == "main") end,
		EvalOverlayStateChangedMessageCommand = function(self) self:queuecommand("Set") end,
		Def.ActorFrame {
			InitCommand = function(self) self:xy(0, -120) end,
			UIElements.QuadButton(1, 1) .. {
				InitCommand = function(self) self:zoomto(bw, 44):halign(0):valign(0):diffuse(color("#1f2833")):diffusealpha(0.94) end,
				MouseDownCommand = function(self, params) if params.event == "DeviceButton_left mouse button" then evalChartActionsMode = "playlist" MESSAGEMAN:Broadcast("EvalOverlayStateChanged", {open = evalOverlayOpen, graphDropdown = evalGraphDropdown, chartActionsMode = evalChartActionsMode}) end end,
			},
			LoadFont("Common Large") .. { InitCommand = function(self) self:xy(12, 22):halign(0):valign(0.5):zoom(0.34):settext("Add to Playlist") end }
		},
		Def.ActorFrame {
			InitCommand = function(self) self:xy(0, -72) end,
			UIElements.QuadButton(1, 1) .. {
				InitCommand = function(self) self:zoomto(bw, 44):halign(0):valign(0):diffuse(color("#1f2833")):diffusealpha(0.94) end,
				MouseDownCommand = function(self, params) if params.event == "DeviceButton_left mouse button" then toggleCurrentChartFavorite() end end,
			},
			LoadFont("Common Large") .. {
				InitCommand = function(self) self:xy(12, 22):halign(0):valign(0.5):zoom(0.34) end,
				SetCommand = function(self) self:settext(isCurrentChartFavorited() and "Unfavourite chart" or "Favourite chart") end,
				EvalChartActionChangedMessageCommand = function(self) self:queuecommand("Set") end,
				EvalOverlayStateChangedMessageCommand = function(self) self:queuecommand("Set") end,
			}
		}
	},
	Def.ActorFrame {
		SetCommand = function(self) self:visible(evalChartActionsMode == "playlist") end,
		EvalOverlayStateChangedMessageCommand = function(self) self:queuecommand("Set") end,
		UIElements.QuadButton(1, 1) .. {
			InitCommand = function(self) self:xy(0, -144):zoomto(48, 22):halign(0):valign(0):diffuse(color("#2a3340")):diffusealpha(0.94) end,
			MouseDownCommand = function(self, params) if params.event == "DeviceButton_left mouse button" then evalChartActionsMode = "main" MESSAGEMAN:Broadcast("EvalOverlayStateChanged", {open = evalOverlayOpen, graphDropdown = evalGraphDropdown, chartActionsMode = evalChartActionsMode}) end end,
		},
		LoadFont("Common Large") .. { InitCommand = function(self) self:xy(24, -133):halign(0.5):valign(0.5):zoom(0.26):settext("Back") end },
		UIElements.QuadButton(1, 1) .. {
			InitCommand = function(self) self:xy(0, -120):zoomto(bw, 22):halign(0):valign(0):diffuse(color("#2a3340")):diffusealpha(0.94) end,
			MouseDownCommand = function(self, params) if params.event == "DeviceButton_left mouse button" then createPlaylistAndAddCurrentChart() end end,
		},
		LoadFont("Common Large") .. { InitCommand = function(self) self:xy(12, -109):halign(0):valign(0.5):zoom(0.26):settext("New playlist") end },
		UIElements.QuadButton(1, 1) .. {
			InitCommand = function(self) self:xy(0, -92):zoomto(48, 18):halign(0):valign(0):diffuse(color("#2a3340")):diffusealpha(0.94) end,
			MouseDownCommand = function(self, params) if params.event == "DeviceButton_left mouse button" then updatePlaylistPage(-1) end end,
		},
		LoadFont("Common Large") .. { InitCommand = function(self) self:xy(24, -83):halign(0.5):valign(0.5):zoom(0.22):settext("Prev") end },
		UIElements.QuadButton(1, 1) .. {
			InitCommand = function(self) self:xy(bw - 48, -92):zoomto(48, 18):halign(0):valign(0):diffuse(color("#2a3340")):diffusealpha(0.94) end,
			MouseDownCommand = function(self, params) if params.event == "DeviceButton_left mouse button" then updatePlaylistPage(1) end end,
		},
		LoadFont("Common Large") .. { InitCommand = function(self) self:xy(bw - 24, -83):halign(0.5):valign(0.5):zoom(0.22):settext("Next") end },
		LoadFont("Common Large") .. {
			InitCommand = function(self) self:xy(bw / 2, -83):halign(0.5):valign(0.5):zoom(0.22) end,
			SetCommand = function(self) self:settext(string.format("%d / %d", evalPlaylistPage, playlistPageCount())) end,
			EvalOverlayStateChangedMessageCommand = function(self) self:queuecommand("Set") end,
			EvalChartActionChangedMessageCommand = function(self) self:queuecommand("Set") end,
		},
	}
}

for i = 1, evalPlaylistPageSize do
	chartActionsOverlay[#chartActionsOverlay + 1] = Def.ActorFrame {
		InitCommand = function(self) self:xy(0, -12) end,
		playlistRow(i),
	}
end

t[#t + 1] = Def.ActorFrame {
	Name = "EvalFooterActions",
	overlayButton(plotStart, "Graph settings", "graph", function(self, params)
		if params.event == "DeviceButton_left mouse button" then
			setEvalOverlayOpen(evalOverlayOpen == "graph" and nil or "graph")
		end
	end, "chart-bar-solid.png"),
	overlayButton(plotStart + bw + gap, "Chart actions", "chartActions", function(self, params)
		if params.event == "DeviceButton_left mouse button" then
			setEvalOverlayOpen(evalOverlayOpen == "chartActions" and nil or "chartActions")
		end
	end),
	-- Button 3: Watch replay
	overlayButton(plotStart + (bw + gap) * 2, "Watch replay", nil, function(self, params)
		if params.event == "DeviceButton_left mouse button" then
			local hs = getCurrentScore()
			if hs then
				if hs:HasReplayData() then
					tryPlayReplay(hs)
				elseif hs:GetReplay() ~= nil then
					DLMAN:RequestOnlineScoreReplayData(
						hs,
						function()
							local replay = hs:GetReplay()
							if replay and replay:HasReplayData() then
								tryPlayReplay(hs)
							else
								ms.ok("No replay data available.")
							end
						end
					)
				else
					ms.ok("No replay data found for this score.")
				end
			end
		end
	end),
	-- Button 4: Custom Scoring Toggle
	overlayButton(plotStart + (bw + gap) * 3, "Custom Scoring", nil, function(self, params)
		if params.event == "DeviceButton_left mouse button" then
			MESSAGEMAN:Broadcast("ToggleCustomWindows")
		end
	end),
	Def.ActorFrame {
		InitCommand = function(self) self:xy(SCREEN_WIDTH / 2, SCREEN_HEIGHT / 2):visible(false) end,
		SetCommand = function(self) self:visible(evalOverlayOpen ~= nil) end,
		EvalOverlayStateChangedMessageCommand = function(self) self:queuecommand("Set") end,
		Def.Quad {
			InitCommand = function(self)
				self:zoomto(SCREEN_WIDTH, SCREEN_HEIGHT):halign(0.5):valign(0.5):diffuse(color("#000000")):diffusealpha(0.58)
			end,
		},
		UIElements.QuadButton(1, 1) .. {
			InitCommand = function(self)
				self:zoomto(SCREEN_WIDTH, SCREEN_HEIGHT):halign(0.5):valign(0.5):diffusealpha(0)
			end,
			MouseDownCommand = function(self, params)
				if params.event == "DeviceButton_left mouse button" then
					setEvalOverlayOpen(nil)
				end
			end,
		}
	},
	graphOverlay,
	chartActionsOverlay,
	-- Retry (Live Play only)
	Def.ActorFrame {
		InitCommand = function(self) self:xy(SCREEN_WIDTH - 301, 349) end,
		BeginCommand = function(self) self:visible(isLivePlay()) end,
		UIElements.QuadButton(1, 1) .. {
			InitCommand = function(self)
				self:zoomto(132, 24):halign(0):valign(0):diffuse(color("#285b7c")):diffusealpha(0.92)
			end,
			MouseOverCommand = function(self) self:diffusealpha(1) end,
			MouseOutCommand = function(self) self:diffusealpha(0.92) end,
			MouseDownCommand = function(self, params)
				if params.event == "DeviceButton_left mouse button" then
					retryCurrentChart()
				end
			end,
		},
		LoadFont("Common Normal") .. {
			InitCommand = function(self)
				self:xy(66, 12):halign(0.5):valign(0.5):zoom(0.45):settext("Retry")
				self:diffuse(color("#FFFFFF"))
			end,
		}
	},
	-- Continue (Live Play only)
	Def.ActorFrame {
		InitCommand = function(self) self:xy(SCREEN_WIDTH - 157, 349) end,
		BeginCommand = function(self) self:visible(isLivePlay()) end,
		UIElements.QuadButton(1, 1) .. {
			InitCommand = function(self)
				self:zoomto(142, 24):halign(0):valign(0):diffuse(color("#285b7c")):diffusealpha(0.92)
			end,
			MouseOverCommand = function(self) self:diffusealpha(1) end,
			MouseOutCommand = function(self) self:diffusealpha(0.92) end,
			MouseDownCommand = function(self, params)
				if params.event == "DeviceButton_left mouse button" then
					continueToSongSelect()
				end
			end,
		},
		LoadFont("Common Normal") .. {
			InitCommand = function(self)
				self:xy(71, 12):halign(0.5):valign(0.5):zoom(0.45):settext("Continue")
				self:diffuse(color("#FFFFFF"))
			end,
		}
	},
}

t[#t + 1] = LoadActor("../_PlayerInfo")
t[#t + 1] = LoadActor("../_cursor")

return t
