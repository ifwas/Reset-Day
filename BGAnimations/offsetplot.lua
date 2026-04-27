-- updated to handle both immediate evaluation when pulling data from pss (doesnt require invoking calls to loadreplay data) and scoretab plot construction (does) -mina

local judges = {"marv", "perf", "great", "good", "boo", "miss"}
local tst = ms.JudgeScalers
local judge = GetTimingDifficulty()
local tso = tst[judge]
local loadingScreen = Var("LoadingScreen") or ""
local useEvaluationLayout = loadingScreen == "ScreenEvaluation" or loadingScreen == "ScreenEvaluationNormal" or loadingScreen == "ScreenNetEvaluation"

local plotWidth, plotHeight = useEvaluationLayout and (SCREEN_WIDTH - 370) or 400, useEvaluationLayout and 130 or 120
local plotX, plotY = useEvaluationLayout and (355 + plotWidth / 2) or (SCREEN_WIDTH - 5 - plotWidth / 2), useEvaluationLayout and (SCREEN_HEIGHT - 62 - plotHeight / 2) or (SCREEN_HEIGHT - 59.5 - plotHeight / 2)
local dotDims, plotMargin = 2, 4
local maxOffset = math.max(180, 180 * tso)
local baralpha = 0.2
local bgalpha = useEvaluationLayout and 1 or 0.8
local textzoom = useEvaluationLayout and 0.42 or 0.35
local forcedWindow = false

local translated_info = {
	Left = THEME:GetString("OffsetPlot", "ExplainLeft"),
	Middle = THEME:GetString("OffsetPlot", "ExplainMiddle"),
	Right = THEME:GetString("OffsetPlot", "ExplainRight"),
	Down = THEME:GetString("OffsetPlot", "ExplainDown"),
	Early = THEME:GetString("OffsetPlot", "Early"),
	Late = THEME:GetString("OffsetPlot", "Late"),
	SD = THEME:GetString("ScreenEvaluation", "StandardDev"),
	Mean = THEME:GetString("ScreenEvaluation", "Mean"),
	UsingReprioritized = THEME:GetString("OffsetPlot", "UsingReprioritized"),
	TapNoteScore_W1 = getJudgeStrings("TapNoteScore_W1"),
	TapNoteScore_W2 = getJudgeStrings("TapNoteScore_W2"),
	TapNoteScore_W3 = getJudgeStrings("TapNoteScore_W3"),
	TapNoteScore_W4 = getJudgeStrings("TapNoteScore_W4"),
	TapNoteScore_W5 = getJudgeStrings("TapNoteScore_W5"),
	TapNoteScore_Miss = getJudgeStrings("TapNoteScore_Miss"),
}

-- initialize tables we need for replay data here, we don't know where we'll be loading from yet
local dvt = {}
local nrt = {}
local ctt = {}
local ntt = {}
local wuab = {}
local finalSecond = GAMESTATE:GetCurrentSteps():GetLastSecond()
local td = GAMESTATE:GetCurrentSteps():GetTimingData()
local oddColumns = false
local middleColumn = 1.5 -- middle column for 4k but accounting for trackvector indexing at 0

local handspecific = false
local left = false
local down = false
local up = false
local right = false
local middle = false
local usingCustomWindows = false
local plotScore = SCOREMAN:GetMostRecentScore() or SCOREMAN:GetTempReplayScore()
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

local function mergeEvalGraphSettings(source)
	if type(source) ~= "table" then return end
	for k, v in pairs(source) do
		if type(v) == "table" then
			evalGraphSettings[k] = copyTable(v)
		else
			evalGraphSettings[k] = v
		end
	end
end

local function loadPersistedEvalGraphSettings()
	if not themeConfig or not themeConfig.get_data then return end
	local config = themeConfig:get_data()
	local globalConfig = config and config.global or nil
	mergeEvalGraphSettings(globalConfig and globalConfig.EvalGraphSettings or nil)
end

local function persistEvalGraphSettings()
	if not themeConfig or not themeConfig.get_data then return end
	local config = themeConfig:get_data()
	config.global = config.global or {}
	config.global.EvalGraphSettings = copyTable(evalGraphSettings)
	themeConfig:set_dirty()
	themeConfig:save()
end

local function getWorstHitOffset()
	local worst = 0
	for i = 1, #dvt do
		if ntt[i] ~= "TapNoteType_Mine" then
			worst = math.max(worst, math.abs(dvt[i] or 0))
		end
	end
	return worst
end

local function refreshEvalGraphSettings()
	loadPersistedEvalGraphSettings()
	mergeEvalGraphSettings(_G.ResetDayEvalGraphSettings or {})
	if evalGraphSettings.lineMode == "Standard deviation" then
		evalGraphSettings.lineMode = "SD"
	end
	if evalGraphSettings.lineColor == "Lamp" then
		evalGraphSettings.lineColor = "Clear Type"
	end
	evalGraphSettings.onlyShowReleases = nil
	evalGraphSettings.lineOnTop = nil
	evalGraphSettings.scale = clamp(tonumber(evalGraphSettings.scale) or 100, 5, 100)
	local columns = GAMESTATE:GetCurrentStyle() and GAMESTATE:GetCurrentStyle():ColumnsPerPlayer() or 4
	for i = 1, columns do
		if evalGraphSettings.columnFilter[i] == nil then
			evalGraphSettings.columnFilter[i] = true
		end
	end
	if evalGraphSettings.scaleToWorstHit then
		maxOffset = math.max(1, getWorstHitOffset())
	else
		maxOffset = math.max(180, 180 * tso) * math.max(0.05, (evalGraphSettings.scale or 100) / 100)
	end
end

local offsetPlotActor

local function broadcastEvalGraphSettings()
	_G.ResetDayEvalGraphSettings = copyTable(evalGraphSettings)
	refreshEvalGraphSettings()
	persistEvalGraphSettings()
	_G.ResetDayEvalGraphSettings = copyTable(evalGraphSettings)
	MESSAGEMAN:Broadcast("EvalGraphSettingsChanged", {settings = copyTable(evalGraphSettings)})
end

local function offsetPlotInput(event)
	if not useEvaluationLayout then return false end
	if not offsetPlotActor then return false end
	if event.type ~= "InputEventType_FirstPress" then return false end
	if not event.DeviceInput then return false end
	local bg = offsetPlotActor:GetChild("BGQuad")
	if not bg or not isOver(bg) then return false end
	if event.DeviceInput.button == "DeviceButton_mousewheel up" then
		evalGraphSettings.scale = clamp((tonumber(evalGraphSettings.scale) or 100) + 5, 5, 100)
		broadcastEvalGraphSettings()
		return true
	elseif event.DeviceInput.button == "DeviceButton_mousewheel down" then
		evalGraphSettings.scale = clamp((tonumber(evalGraphSettings.scale) or 100) - 5, 5, 100)
		broadcastEvalGraphSettings()
		return true
	end
	return false
end

local function shouldDrawPoint(index)
	if ntt[index] == "TapNoteType_Mine" then return false end
	if ctt[index] ~= nil and evalGraphSettings.columnFilter[ctt[index] + 1] == false then return false end
	return true
end

local function lineToYNormalized(value, low, high)
	if high <= low then return 0 end
	local normalized = clamp((value - low) / (high - low), 0, 1)
	return (plotHeight / 2) - (normalized * plotHeight)
end

local function tableColor(c)
	local out = {1, 1, 1, 1}
	if type(c) == "table" then
		out[1] = c[1] or out[1]
		out[2] = c[2] or out[2]
		out[3] = c[3] or out[3]
		out[4] = c[4] or out[4]
	end
	return out
end

local function getJudgeBucketForOffset(offset)
	local scale = tst[judge]
	if usingCustomWindows then
		local window = getCurrentCustomWindowConfigJudgmentWindowTable()
		if math.abs(offset) <= window.TapNoteScore_W1 then return 1 end
		if math.abs(offset) <= window.TapNoteScore_W2 then return 2 end
		if math.abs(offset) <= window.TapNoteScore_W3 then return 3 end
		if math.abs(offset) <= window.TapNoteScore_W4 then return 4 end
		if math.abs(offset) <= window.TapNoteScore_W5 then return 5 end
		return 6
	end
	if math.abs(offset) <= 22.5 * scale then return 1 end
	if math.abs(offset) <= 45 * scale then return 2 end
	if math.abs(offset) <= 90 * scale then return 3 end
	if math.abs(offset) <= 135 * scale then return 4 end
	if math.abs(offset) <= 180 * scale then return 5 end
	return 6
end

local function getWife3PercentForOffsets(offsets, totalTaps)
	if type(getRescoredWife3Judge) ~= "function" then return nil end
	return getRescoredWife3Judge(3, judge, {
		dvt = offsets,
		totalTaps = totalTaps or #offsets,
		holdsMissed = 0,
		minesHit = 0,
	})
end

local function getLineColorAtState(running)
	if evalGraphSettings.lineColor == "White" then
		return {1, 1, 1, 1}
	end
	if evalGraphSettings.lineColor == "Grade" then
		local wifePercent = getWife3PercentForOffsets(running.offsets or {}, running.count)
		local percent = wifePercent and (wifePercent / 100) or 0
		return tableColor(getGradeColor(GetGradeFromPercent(percent)))
	end
	local wifePercent = getWife3PercentForOffsets(running.offsets or {}, running.count)
	local grade = GetGradeFromPercent(math.max(0, math.min(1, (wifePercent or 0) / 100)))
	local misscount = math.max(0, running.count - running.w1 - running.w2 - running.w3)
	return tableColor(getClearTypeFromValues(grade, 1, running.w2, running.w3, misscount, 2))
end

local function getSliceSummary(row, width)
	local halfWidth = math.max(1, width or 1) * 48
	local minRow = row - halfWidth
	local maxRow = row + halfWidth
	local judgments = {W1 = 0, W2 = 0, W3 = 0, W4 = 0, W5 = 0, Miss = 0}
	local total = 0
	local sum = 0
	local sumSquares = 0
	for i = 1, #nrt do
		if nrt[i] and nrt[i] >= minRow and nrt[i] <= maxRow and shouldDrawPoint(i) then
			total = total + 1
			local offset = dvt[i] or 0
			sum = sum + offset
			sumSquares = sumSquares + (offset * offset)
			local judgeBucket = getJudgeBucketForOffset(offset)
			if judgeBucket == 1 then judgments.W1 = judgments.W1 + 1
			elseif judgeBucket == 2 then judgments.W2 = judgments.W2 + 1
			elseif judgeBucket == 3 then judgments.W3 = judgments.W3 + 1
			elseif judgeBucket == 4 then judgments.W4 = judgments.W4 + 1
			elseif judgeBucket == 5 then judgments.W5 = judgments.W5 + 1
			else judgments.Miss = judgments.Miss + 1 end
		end
	end
	local mean = total > 0 and (sum / total) or 0
	local variance = total > 0 and math.max(0, (sumSquares / total) - (mean * mean)) or 0
	local sd = math.sqrt(variance)
	local sliceOffsets = {}
	for i = 1, #nrt do
		if nrt[i] and nrt[i] >= minRow and nrt[i] <= maxRow and shouldDrawPoint(i) then
			sliceOffsets[#sliceOffsets + 1] = dvt[i] or 0
		end
	end
	local accuracy = total > 0 and (getWife3PercentForOffsets(sliceOffsets, total) or 0) or 0
	return {
		judgments = judgments,
		mean = mean,
		sd = sd,
		accuracy = accuracy,
		total = total,
		minRow = minRow,
		maxRow = maxRow,
	}
end

local function rowToX(row)
	if finalSecond == 0 then return 0 end
	local elapsed = td:GetElapsedTimeFromNoteRow(row)
	return elapsed / finalSecond * plotWidth - plotWidth / 2
end

local function fitX(x) -- Scale time values to fit within plot width.
	if finalSecond == 0 then
		return 0
	end
	return x / finalSecond * plotWidth - plotWidth / 2
end

local function fitY(y) -- Scale offset values to fit within plot height
	return -1 * y / maxOffset * plotHeight / 2
end

local function HighlightUpdaterThing(self)
	self:GetChild("BGQuad"):queuecommand("Highlight")
end

-- we removed j1-3 so uhhh this stops things lazily
local function clampJudge()
	if judge < 4 then judge = 4 end
	if judge > 9 then judge = 9 end
end
clampJudge()

local function scaleToJudge(scale)
	scale = notShit.round(scale, 2)
	local scales = ms.JudgeScalers
	local out = 4
	for k,v in pairs(scales) do
		if v == scale then
			out = k
		end
	end
	return out
end

-- convert a plot x position to a noterow
local function convertXToRow(x)
	local output = x + plotWidth/2
	output = output / plotWidth

	if output < 0 then output = 0 end
	if output > 1 then output = 1 end

	-- the 48 here is how many noterows there are per beat
	-- this is a const defined in the game
	-- and i sure hope it doesnt ever change
	local td = GAMESTATE:GetCurrentSteps():GetTimingData()
	local row = td:GetBeatFromElapsedTime(output * finalSecond) * 48

	return row
end

local o = Def.ActorFrame {
	Name = "OffsetPlot",
	BeginCommand = function(self)
		offsetPlotActor = self
		SCREENMAN:GetTopScreen():AddInputCallback(offsetPlotInput)
	end,
	OnCommand = function(self)
		refreshEvalGraphSettings()
		self:xy(plotX, plotY)
		-- being explicit about the logic since atm these are the only 2 cases we handle
		local name = SCREENMAN:GetTopScreen():GetName()
		if name == "ScreenNetEvaluation" then -- moving away from grabbing anything in pss, dont want to mess with net stuff atm
			if not forcedWindow then
				judge = scaleToJudge(SCREENMAN:GetTopScreen():GetReplayJudge())
				clampJudge()
				tso = tst[judge]
			end
			local allowHovering = not SCREENMAN:GetTopScreen():ScoreUsedInvalidModifier()
			if allowHovering then
				self:SetUpdateFunction(HighlightUpdaterThing)
			end
			local pss = STATSMAN:GetCurStageStats():GetPlayerStageStats()
			dvt = pss:GetOffsetVector()
			nrt = pss:GetNoteRowVector()
			ctt = pss:GetTrackVector() -- column information for each offset
			ntt = pss:GetTapNoteTypeVector() -- notetype information (we use this to handle mine hits differently- currently that means not displaying them)
		else -- should be default behavior
			if name == "ScreenScoreTabOffsetPlot" then
				local score = getScoreForPlot()
				plotScore = score
				plotWidth, plotHeight = SCREEN_WIDTH, SCREEN_WIDTH * 0.3
				self:xy(SCREEN_CENTER_X, SCREEN_CENTER_Y)
				textzoom = 0.5
				bgalpha = 1
				if score ~= nil then
					if score:HasReplayData() then
						local replay = score:GetReplay()
						dvt = replay:GetOffsetVector()
						nrt = replay:GetNoteRowVector()
						ctt = replay:GetTrackVector()
						ntt = replay:GetTapNoteTypeVector()
					end
				end
			else
				local allowHovering = not SCREENMAN:GetTopScreen():ScoreUsedInvalidModifier()
				if allowHovering then
					self:SetUpdateFunction(HighlightUpdaterThing)
				end
			end
		end

		-- missing noterows. this happens with many online replays.
		-- we can approximate, but i dont want to do that right now.
		if nrt == nil then
			return
		end

		oddColumns = GAMESTATE:GetCurrentStyle():ColumnsPerPlayer() % 2 ~= 0 -- hopefully the style is consistently set here
		middleColumn = (GAMESTATE:GetCurrentStyle():ColumnsPerPlayer()-1) / 2.0

		-- Convert noterows to timestamps and plot dots (this is important it determines plot x values!!!)
		wuab = {}
		for i = 1, #nrt do
			wuab[i] = td:GetElapsedTimeFromNoteRow(nrt[i])
		end

		refreshEvalGraphSettings()
		MESSAGEMAN:Broadcast("JudgeDisplayChanged") -- prim really handled all this much more elegantly
	end,
	SetFromDisplayMessageCommand = function(self, params)
		if params.score then
			self:playcommand("SetFromScore", params)
		end
	end,
	SetFromScoreCommand = function(self, params)
		if params.score then
			local score = params.score
			plotScore = score

			if score:HasReplayData() then
				local replay = score:GetReplay()
				dvt = replay:GetOffsetVector()
				nrt = replay:GetNoteRowVector()
				ctt = replay:GetTrackVector()
				ntt = replay:GetTapNoteTypeVector()
			else
				dvt = {}
				nrt = {}
				ctt = {}
				ntt = {}
			end

			wuab = {}
			for i = 1, #nrt do
				wuab[i] = td:GetElapsedTimeFromNoteRow(nrt[i])
			end

			refreshEvalGraphSettings()
			MESSAGEMAN:Broadcast("JudgeDisplayChanged")
		end
	end,
	LoadedCustomWindowMessageCommand = function(self)
		usingCustomWindows = true
		local replay = REPLAYS:GetActiveReplay()
		wuab = {}
		dvt = replay:GetOffsetVector()
		nrt = replay:GetNoteRowVector()
		ctt = replay:GetTrackVector()
		ntt = replay:GetTapNoteTypeVector()
		for i = 1, #nrt do
			wuab [i] = td:GetElapsedTimeFromNoteRow(nrt[i])
		end

		refreshEvalGraphSettings()
		MESSAGEMAN:Broadcast("JudgeDisplayChanged")
	end,
	UnloadedCustomWindowMessageCommand = function(self)
		usingCustomWindows = false
		refreshEvalGraphSettings()
		MESSAGEMAN:Broadcast("JudgeDisplayChanged")
	end,
	EvalGraphSettingsChangedMessageCommand = function(self, params)
		mergeEvalGraphSettings(params and params.settings or nil)
		refreshEvalGraphSettings()
		MESSAGEMAN:Broadcast("JudgeDisplayChanged")
	end,
	CodeMessageCommand = function(self, params)
		if usingCustomWindows then return end

		if params.Name == "PrevJudge" and judge > 1 then
			judge = judge - 1
			clampJudge()
			tso = tst[judge]
		elseif params.Name == "NextJudge" and judge < 9 then
			judge = judge + 1
			clampJudge()
			tso = tst[judge]
		end
		if params.Name == "ToggleHands" and #ctt > 0 then --super ghetto toggle -mina
			if not handspecific then -- moving from none to left
				handspecific = true
				left = true
			elseif handspecific and left then
				down = true
				left = false
			elseif handspecific and down then
				down = false
				up = true
			elseif handspecific and up then
				up = false
				right = true
			elseif handspecific and right then -- moving from right to none
				right = false
				handspecific = false
			end
			MESSAGEMAN:Broadcast("JudgeDisplayChanged")
		end
		if params.Name == "ResetJudge" then
			judge = GetTimingDifficulty()
			clampJudge()
			tso = tst[GetTimingDifficulty()]
		end
		if params.Name ~= "ResetJudge" and params.Name ~= "PrevJudge" and params.Name ~= "NextJudge" and params.Name ~= "ToggleHands" then return end
		refreshEvalGraphSettings()
		MESSAGEMAN:Broadcast("JudgeDisplayChanged")
	end,
	ForceWindowMessageCommand = function(self, params)
		judge = params.judge
		clampJudge()
		tso = tst[judge]
		refreshEvalGraphSettings()
		forcedWindow = true
	end,
	UpdateNetEvalStatsMessageCommand = function(self) -- i haven't updated or tested neteval during last round of work -mina
		local s = SCREENMAN:GetTopScreen():GetHighScore()
		if s then
			plotScore = s
			local replay = plotScore:GetReplay()
			dvt = replay:GetOffsetVector()
			nrt = replay:GetNoteRowVector()
			ctt = replay:GetTrackVector()
			wuab = {}
			for i = 1, #nrt do
				wuab[i] = td:GetElapsedTimeFromNoteRow(nrt[i])
			end
		end
		refreshEvalGraphSettings()
		MESSAGEMAN:Broadcast("JudgeDisplayChanged")
	end
}
-- Background
o[#o + 1] = Def.Quad {
	Name = "BGQuad",
	JudgeDisplayChangedMessageCommand = function(self)
		self:zoomto(plotWidth + plotMargin, plotHeight + plotMargin)
		self:diffuse(color("0,0,0,1"))
		self:diffusealpha(bgalpha)
	end,
	HighlightCommand = function(self)
		local bar = self:GetParent():GetChild("PosBar")
		local txt = self:GetParent():GetChild("PosText")
		local bg = self:GetParent():GetChild("PosBG")
		if isOver(self) then
			local xpos = INPUTFILTER:GetMouseX() - self:GetParent():GetX()
			bar:visible(true)
			txt:visible(true)
			bg:visible(true)
			txt:x(xpos - 2)
			local row = convertXToRow(xpos)
			local timebro = td:GetElapsedTimeFromNoteRow(row) / getCurRateValue()
			if evalGraphSettings.hoverInfo == "Slice" then
				local slice = getSliceSummary(row, evalGraphSettings.sliceWidth)
				local minX = rowToX(slice.minRow)
				local maxX = rowToX(slice.maxRow)
				local sliceWidth = math.max(2, math.abs(maxX - minX))
				bar:x((minX + maxX) / 2)
				bar:zoomto(sliceWidth, plotHeight + plotMargin)
				txt:settextf("Slice (%d)\n%s: %d\n%s: %d\n%s: %d\n%s: %d\n%s: %d\n%s: %d\n%s: %0.2fms\n%s: %0.2fms\nAccuracy: %0.2f%%\n%s: %0.2fs",
					slice.total,
					translated_info["TapNoteScore_W1"], slice.judgments["W1"],
					translated_info["TapNoteScore_W2"], slice.judgments["W2"],
					translated_info["TapNoteScore_W3"], slice.judgments["W3"],
					translated_info["TapNoteScore_W4"], slice.judgments["W4"],
					translated_info["TapNoteScore_W5"], slice.judgments["W5"],
					translated_info["TapNoteScore_Miss"], slice.judgments["Miss"],
					translated_info["SD"], slice.sd,
					translated_info["Mean"], slice.mean,
					slice.accuracy,
					"Time", timebro
				)
			else
				bar:x(xpos)
				bar:zoomto(2, plotHeight + plotMargin)
				local replay = REPLAYS:GetActiveReplay()
				local snapshot = replay and replay:GetReplaySnapshotForNoterow(row)
				local judgments = snapshot and snapshot:GetJudgments() or {W1 = 0, W2 = 0, W3 = 0, W4 = 0, W5 = 0, Miss = 0}
				local wifescore = snapshot and (snapshot:GetWifePercent() * 100) or 0
				local mean = snapshot and snapshot:GetMean() or 0
				local sd = snapshot and snapshot:GetStandardDeviation() or 0
				txt:settextf("%0.2f%%\n%s: %d\n%s: %d\n%s: %d\n%s: %d\n%s: %d\n%s: %d\n%s: %0.2fms\n%s: %0.2fms\n%s: %0.2fs",
					wifescore,
					translated_info["TapNoteScore_W1"], judgments["W1"],
					translated_info["TapNoteScore_W2"], judgments["W2"],
					translated_info["TapNoteScore_W3"], judgments["W3"],
					translated_info["TapNoteScore_W4"], judgments["W4"],
					translated_info["TapNoteScore_W5"], judgments["W5"],
					translated_info["TapNoteScore_Miss"], judgments["Miss"],
					translated_info["SD"], sd,
					translated_info["Mean"], mean,
					"Time", timebro
				)
			end
			bg:x(bar:GetX())
			bg:zoomto(txt:GetZoomedWidth() + 4, txt:GetZoomedHeight() + 4)
		else
			bar:visible(false)
			txt:visible(false)
			bg:visible(false)
		end
	end
}
o[#o + 1] = Def.Quad {
	Name = "BorderTop",
	JudgeDisplayChangedMessageCommand = function(self)
		self:xy(0, -plotHeight / 2 - plotMargin / 2):zoomto(plotWidth + plotMargin + 2, 2):diffuse(color("#FFFFFF"))
	end
}
o[#o + 1] = Def.Quad {
	Name = "BorderBottom",
	JudgeDisplayChangedMessageCommand = function(self)
		self:xy(0, plotHeight / 2 + plotMargin / 2):zoomto(plotWidth + plotMargin + 2, 2):diffuse(color("#FFFFFF"))
	end
}
o[#o + 1] = Def.Quad {
	Name = "BorderLeft",
	JudgeDisplayChangedMessageCommand = function(self)
		self:xy(-plotWidth / 2 - plotMargin / 2, 0):zoomto(2, plotHeight + plotMargin + 2):diffuse(color("#FFFFFF"))
	end
}
o[#o + 1] = Def.Quad {
	Name = "BorderRight",
	JudgeDisplayChangedMessageCommand = function(self)
		self:xy(plotWidth / 2 + plotMargin / 2, 0):zoomto(2, plotHeight + plotMargin + 2):diffuse(color("#FFFFFF"))
	end
}
o[#o+1] = Def.ActorFrame {
	InitCommand = function(self)
		self:visible(false)
	end,
	JudgeDisplayChangedMessageCommand = function(self)
		self:visible(usingCustomWindows and currentCustomWindowConfigUsesOldestNoteFirst())
	end,
	Def.Quad {
		InitCommand = function(self)
			self:zoomto(plotWidth/2,15)
			self:xy(-plotWidth/2 - plotMargin/2, -plotHeight/2 - plotMargin/2)
			self:halign(0):valign(1)
			self:diffuse(color("0.05,0.05,0.05,0.05"))
			self:diffusealpha(bgalpha)
		end,
	},
	LoadFont("Common Normal") .. {
		InitCommand = function(self)
			self:xy(-plotWidth/4 - plotMargin/2, -plotHeight/2 - plotMargin/2 - 15/2)
			self:zoom(0.4)
			self:settext(translated_info["UsingReprioritized"])
		end,
	},
}
-- Center Bar
o[#o + 1] = Def.Quad {
	JudgeDisplayChangedMessageCommand = function(self)
		self:zoomto(plotWidth + plotMargin, 1):diffuse(byJudgment("TapNoteScore_W1")):diffusealpha(baralpha)
	end
}
local fantabars = {22.5, 45, 90, 135}
local bantafars = {"TapNoteScore_W2", "TapNoteScore_W3", "TapNoteScore_W4", "TapNoteScore_W5"}
local santabarf = {"TapNoteScore_W1", "TapNoteScore_W2", "TapNoteScore_W3", "TapNoteScore_W4"} -- ugh
for i = 1, #fantabars do
	o[#o + 1] = Def.Quad {
		JudgeDisplayChangedMessageCommand = function(self)
			self:visible(evalGraphSettings.showTimingWindows)
			self:zoomto(plotWidth + plotMargin, 1):diffuse(byJudgment(bantafars[i])):diffusealpha(baralpha)
			local fit = tso * fantabars[i]
			if usingCustomWindows then
				fit = getCustomWindowConfigJudgmentWindow(santabarf[i])
			end
			self:finishtweening()
			self:smooth(0.1)
			self:y(fitY(fit))
		end
	}
	o[#o + 1] = Def.Quad {
		JudgeDisplayChangedMessageCommand = function(self)
			self:visible(evalGraphSettings.showTimingWindows)
			self:zoomto(plotWidth + plotMargin, 1):diffuse(byJudgment(bantafars[i])):diffusealpha(baralpha)
			local fit = tso * fantabars[i]
			if usingCustomWindows then
				fit = getCustomWindowConfigJudgmentWindow(santabarf[i])
			end
			self:finishtweening()
			self:smooth(0.1)
			self:y(fitY(-fit))
		 end
}
end

-- Bar for current mouse position on graph
o[#o + 1] = Def.Quad {
	Name = "PosBar",
	InitCommand = function(self)
		self:visible(false)
		self:zoomto(2, plotHeight + plotMargin):diffuse(color("0.5,0.5,0.5,1"))
	end,
	JudgeDisplayChangedMessageCommand = function(self)
		self:zoomto(2, plotHeight + plotMargin)
	end
}

local dotWidth = dotDims / 2
local function setOffsetVerts(vt, x, y, c)
	vt[#vt + 1] = {{x - dotWidth, y + dotWidth, 0}, c}
	vt[#vt + 1] = {{x + dotWidth, y + dotWidth, 0}, c}
	vt[#vt + 1] = {{x + dotWidth, y - dotWidth, 0}, c}
	vt[#vt + 1] = {{x - dotWidth, y - dotWidth, 0}, c}
end
o[#o + 1] = Def.ActorMultiVertex {
	JudgeDisplayChangedMessageCommand = function(self)
		local verts = {}
		for i = 1, #dvt do
			if shouldDrawPoint(i) then
				local x = fitX(wuab[i])
				local y = fitY(dvt[i])
				local fit = math.max(183, 183 * tso)

				local cullur = offsetToJudgeColor(dvt[i], tst[judge])
				if usingCustomWindows then
					cullur = customOffsetToJudgeColor(dvt[i], getCurrentCustomWindowConfigJudgmentWindowTable())
				end
				cullur[4] = 1
				local cullurFaded = {}

				if math.abs(y) > plotHeight / 2 then
					y = fitY(fit)
				end

				if handspecific then
					for ind, c in pairs(cullur) do
						cullurFaded[ind] = c
					end
					cullurFaded[4] = 0.28
				end

				if handspecific and left then
					if ctt[i] == 0 then
						setOffsetVerts(verts, x, y, cullur)
					else
						setOffsetVerts(verts, x, y, cullurFaded)
					end
				elseif handspecific and down then
					if ctt[i] == 1 then
						setOffsetVerts(verts, x, y, cullur)
					else
						setOffsetVerts(verts, x, y, cullurFaded)
					end
				elseif handspecific and up then
					if ctt[i] == 2 then
						setOffsetVerts(verts, x, y, cullur)
					else
						setOffsetVerts(verts, x, y, cullurFaded)
					end
				elseif handspecific and right then
					if ctt[i] == 3 then
						setOffsetVerts(verts, x, y, cullur)
					else
						setOffsetVerts(verts, x, y, cullurFaded)
					end
				else
					setOffsetVerts(verts, x, y, cullur)
				end
			end
		end
		self:SetVertices(verts)
		self:SetDrawState {Mode = "DrawMode_Quads", First = 1, Num = #verts}
	end
}

local function getLineModeValue(index, running)
	local bucket = getJudgeBucketForOffset(dvt[index] or 0)
	running.count = running.count + 1
	running.sumOffset = running.sumOffset + (dvt[index] or 0)
	running.sumSquares = running.sumSquares + ((dvt[index] or 0) * (dvt[index] or 0))
	running.offsets[#running.offsets + 1] = dvt[index] or 0
	if bucket == 1 then running.w1 = running.w1 + 1 end
	if bucket == 2 then running.w2 = running.w2 + 1 end
	if bucket == 3 then running.w3 = running.w3 + 1 end
	if bucket <= 3 then running.combo = running.combo + 1 else running.combo = 0 end
	if evalGraphSettings.lineMode == "Combo" then return running.combo end
	if evalGraphSettings.lineMode == "Mean" then return running.sumOffset / math.max(1, running.count) end
	if evalGraphSettings.lineMode == "SD" or evalGraphSettings.lineMode == "Standard deviation" then
		local mean = running.sumOffset / math.max(1, running.count)
		return math.sqrt(math.max(0, (running.sumSquares / math.max(1, running.count)) - (mean * mean)))
	end
	if evalGraphSettings.lineMode == "Accuracy" then return getWife3PercentForOffsets(running.offsets, running.count) or 0 end
	if evalGraphSettings.lineMode == "MA" then return running.w2 == 0 and running.w1 or (running.w1 / running.w2) end
	if evalGraphSettings.lineMode == "PA" then return running.w3 == 0 and running.w2 or (running.w2 / running.w3) end
	return nil
end

local function buildLineVertices()
	if evalGraphSettings.lineMode == "None" then return {} end
	local running = {count = 0, combo = 0, sumOffset = 0, sumSquares = 0, w1 = 0, w2 = 0, w3 = 0, offsets = {}}
	local points = {}
	local minValue, maxValue = nil, nil
	for i = 1, #dvt do
		if shouldDrawPoint(i) then
			local value = getLineModeValue(i, running)
			if value ~= nil then
				points[#points + 1] = {x = fitX(wuab[i]), raw = value, color = getLineColorAtState(running)}
				minValue = minValue and math.min(minValue, value) or value
				maxValue = maxValue and math.max(maxValue, value) or value
			end
		end
	end
	if #points == 0 then return {} end
	if evalGraphSettings.lineMode == "Mean" then
		minValue = -maxOffset
		maxValue = maxOffset
	end
	if minValue == maxValue then
		minValue = minValue - 1
		maxValue = maxValue + 1
		end
	local verts = {}
	for i = 1, #points do
		local y = evalGraphSettings.lineMode == "Mean" and fitY(points[i].raw) or lineToYNormalized(points[i].raw, minValue, maxValue)
		verts[#verts + 1] = {{points[i].x, y, 0}, points[i].color or {1, 1, 1, 1}}
	end
	return verts
end

o[#o + 1] = Def.ActorMultiVertex {
	Name = "TrendLine",
	JudgeDisplayChangedMessageCommand = function(self)
		local verts = buildLineVertices()
		self:SetVertices(verts)
		self:SetDrawState {Mode = "DrawMode_LineStrip", First = 1, Num = #verts}
		self:draworder(105)
	end,
	InitCommand = function(self)
		self:visible(true)
	end
}


-- filter
o[#o + 1] = LoadFont("Common Normal") .. {
	JudgeDisplayChangedMessageCommand = function(self)
		self:xy(0, plotHeight / 2 - 2):zoom(textzoom):halign(0.5):valign(1)
		if #ntt > 0 then
			if handspecific then
				if left then
					self:settext("left")
				elseif down then
					self:settext("down")
				elseif up then
					self:settext("up")
				elseif right then
					self:settext("right")
				end
			else
				self:settext(translated_info["Down"])
			end
		else
			self:settext("")
		end
	end
}

-- Early/Late markers
o[#o + 1] = LoadFont("Common Normal") .. {
	JudgeDisplayChangedMessageCommand = function(self)
		self:xy(-plotWidth / 2, -plotHeight / 2 + 2):zoom(textzoom):halign(0):valign(0):settextf("%s (+%ims)", translated_info["Late"], maxOffset)
	end
}
o[#o + 1] = LoadFont("Common Normal") .. {
	JudgeDisplayChangedMessageCommand = function(self)
		self:xy(-plotWidth / 2, plotHeight / 2 - 2):zoom(textzoom):halign(0):valign(1):settextf("%s (-%ims)", translated_info["Early"], maxOffset)
	end
}

-- Background for judgments at mouse position
o[#o + 1] = Def.Quad {
	Name = "PosBG",
	InitCommand = function(self)
		self:valign(1):halign(1):zoomto(30,30):diffuse(color(".1,.1,.1,.45")):y(-plotHeight / 2 - plotMargin)
		self:visible(false)
	end
}

-- Text for judgments at mouse position
o[#o + 1] = LoadFont("Common Normal") .. {
	Name = "PosText",
	InitCommand = function(self)
		self:x(8):valign(1):halign(1):zoom(0.4):y(-plotHeight / 2 - plotMargin - 2)
	end
}

-- Text for current judge window
-- Only for SelectMusic (not Eval)
o[#o + 1] = LoadFont("Common Normal") .. {
	Name = "JudgeText",
	InitCommand = function(self)
		self:valign(0):halign(0):zoom(0.4)
		self:xy(-plotWidth/2, -plotHeight/2)
		self:settext("")
	end,
	OnCommand = function(self)
		local name = SCREENMAN:GetTopScreen():GetName()
		if name ~= "ScreenScoreTabOffsetPlot" then
			self:visible(false)
		end
	end,
	SetCommand = function(self)
		local jdgname = "J" .. judge
		self:settextf("%s", jdgname)
	end,
	JudgeDisplayChangedMessageCommand = function(self)
		self:playcommand("Set")
		self:xy(-plotWidth / 2 + 5, -plotHeight / 2 + 15):zoom(textzoom):halign(0):valign(0)
	end
}

return o
