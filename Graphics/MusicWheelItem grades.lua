-- ClearType helpers ────────────────────────────────────────────────────────
local ctNames     = {"MFC","WF","SDP","PFC","BF","SDG","FC","MF","SDCB","Clear","Failed","Invalid","No Play","-"}
local ctColorKeys = {"MFC","WF","SDP","PFC","BF","SDG","FC","MF","SDCB","Clear","Failed","Invalid","NoPlay","None"}

local function ctColor(idx)
	local key = ctColorKeys[idx] or "None"
	local ok, c = pcall(function() return color(colorConfig:get_data().clearType[key]) end)
	return ok and c or color("#888888")
end

local function getClearType(score, ret)
	if not score then return nil end
	local w2  = score:GetTapNoteScore("TapNoteScore_W2")  or 0
	local w3  = score:GetTapNoteScore("TapNoteScore_W3")  or 0
	local w4  = score:GetTapNoteScore("TapNoteScore_W4")  or 0
	local w5  = score:GetTapNoteScore("TapNoteScore_W5")  or 0
	local mis = score:GetTapNoteScore("TapNoteScore_Miss") or 0
	local grade = score:GetWifeGrade()

	if grade == "Grade_Failed" or grade == "Grade_None" then
		local lv = 11
		if ret == 0 then return ctNames[lv] elseif ret == 2 then return ctColor(lv) end
		return lv
	end

	local cb = mis + w5 + w4
	local lv
	if     cb > 0  then lv = cb == 1 and 8 or (cb < 10 and 9 or 10)
	elseif w3 > 0  then lv = w3 == 1 and 5 or (w3 < 10 and 6 or 7)
	elseif w2 > 0  then lv = w2 == 1 and 2 or (w2 < 10 and 3 or 4)
	else               lv = 1
	end
	if ret == 0 then return ctNames[lv] elseif ret == 2 then return ctColor(lv) end
	return lv
end

local function getScoreClosestToRate(song, targetRateValue)
	if not song then return nil, nil end
	local allSteps = song:GetAllSteps()
	if not allSteps then return nil, nil end

	local bestScore = nil
	local bestRateStr = nil
	local minRateDiff = math.huge
	local bestWifeScore = -1

	for _, steps in ipairs(allSteps) do
		local ok, ck = pcall(function() return steps:GetChartKey() end)
		if ok and ck and ck ~= "" then
			local byRate = SCOREMAN:GetScoresByKey(ck)
			if byRate then
				for rateStr, scoresAtRate in pairs(byRate) do
					-- Parse rate "1.1x" -> 1.1
					local rStrNum = string.match(rateStr, "^([%d%.]+)")
					local rVal = rStrNum and tonumber(rStrNum) or 1.0
					
					local diff = math.abs(rVal - targetRateValue)
					
					local ok2, slist = pcall(function() return scoresAtRate:GetScores() end)
					if ok2 and slist then
						for _, s in ipairs(slist) do
							local wscore = s:GetWifeScore()
							
							-- If rate is strictly closer to target
							if diff < minRateDiff - 0.001 then
								minRateDiff = diff
								bestScore = s
								bestRateStr = rateStr
								bestWifeScore = wscore
							-- If rate is equally close, prefer higher score
							elseif math.abs(diff - minRateDiff) <= 0.001 then
								if wscore > bestWifeScore then
									bestScore = s
									bestRateStr = rateStr
									bestWifeScore = wscore
								end
							end
						end
					end
				end
			end
		end
	end
	return bestScore, bestRateStr
end

local function getWheelSetting(key, defaultValue)
	if getMusicWheelDisplaySetting then
		local value = getMusicWheelDisplaySetting(key)
		if value ~= nil then
			return value
		end
	end
	return defaultValue
end

local function formatWifePercent(score)
	if not score then return "" end
	local percent = (score:GetWifeScore() or 0) * 100
	return string.format(percent >= 99.7 and "%05.4f%%" or "%05.2f%%", percent)
end

local function formatRelativeScoreTime(score)
	if not score or not score.GetDate then return "" end
	local dateStr = score:GetDate()
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
	end
	return math.floor(diff/31536000) .. "y ago"
end

local function formatRateAndTimestamp(data)
	local text = (data.score and data.rate) and ("(" .. data.rate .. ")") or ""
	if data.showPBTimestamps and data.score then
		local relativeTime = formatRelativeScoreTime(data.score)
		if relativeTime ~= "" then
			if text ~= "" then
				text = text .. " • " .. relativeTime
			else
				text = relativeTime
			end
		end
	end
	return text
end

-- Layout properties
local boxW   = 50
local boxH   = 31
local boxGap = 2
local gradeX =  boxW + boxGap
local clearX =  boxGap/2

return Def.ActorFrame {

	InitCommand = function(self)
		self:y(0.5)
		self.slotDifficulty = "Medium"
		self.slotSong = nil
		self.slotMirror = false
		self.slotFav = false
	end,

	SetCommand = function(self, params)
		if params and params.Song then
			self.slotSong = params.Song
		else
			self.slotSong = nil
		end
		self:playcommand("RefreshUI")
	end,

	SetGradeCommand = function(self, params)
		if params then
			-- We fetch Grade directly from score later instead of params.Grade
			self.slotDifficulty = params.Difficulty or "Medium"
			self.slotMirror = params.PermaMirror
			self.slotFav = params.Favorited
		end
		self:playcommand("RefreshUI")
	end,

	MusicWheelDisplaySettingsChangedMessageCommand = function(self)
		self:playcommand("RefreshUI")
	end,

	MusicWheelDisplayRefreshMessageCommand = function(self)
		self:playcommand("RefreshUI")
	end,

	RefreshUICommand = function(self)
		local score, rate
		local targetRateValue = getCurRateValue and getCurRateValue() or 1.0
		
		if self.slotSong then
			score, rate = getScoreClosestToRate(self.slotSong, targetRateValue)
		end
		
		-- Override engine's params.Grade with the exact grade from our matching score
		local computedGrade = "Grade_None"
		if score then
			computedGrade = score:GetWifeGrade() or "Grade_None"
		end
		
		local data = {
			song  = self.slotSong,
			score = score,
			rate  = rate,
			grade = computedGrade,
			diff  = self.slotDifficulty,
			mirror = self.slotMirror,
			fav    = self.slotFav,
			showGradesOnly = getWheelSetting("OnlyShowGrades", true),
			showPBTimestamps = getWheelSetting("ShowPBTimestamps", true)
		}
		
		self:RunCommandsOnChildren(function(child)
			child:playcommand("Redraw", data)
		end)
	end,

	-- ═══ GRADE BOX (left) — shown for every song that has a grade ════════════
	Def.Quad {
		InitCommand = function(self)
			self:xy(gradeX, -2):zoomto(boxW, boxH):halign(0):valign(0.5)
			self:diffuse(color("#000000")):diffusealpha(0.6)
		end,
		RedrawCommand = function(self, data)
			if data.showGradesOnly then
				self:visible(data.grade ~= "Grade_None" and data.grade ~= "Grade_Tier17")
			else
				self:visible(data.score ~= nil)
			end
		end
	},
	LoadFont("Common Normal") .. {
		InitCommand = function(self)
			self:xy(gradeX + boxW/2, -8):zoom(0.5):halign(0.5):valign(0.5)
		end,
		RedrawCommand = function(self, data)
			if data.showGradesOnly and (data.grade == "Grade_None" or data.grade == "Grade_Tier17") then
				self:settext("")
			elseif not data.showGradesOnly and data.score then
				self:settext(formatWifePercent(data.score))
				self:diffuse(getGradeColor(data.grade))
			else
				self:settext(THEME:GetString("Grade", ToEnumShortString(data.grade)) or "")
				self:diffuse(getGradeColor(data.grade))
			end
		end
	},
	LoadFont("Common Normal") .. {
		InitCommand = function(self)
			self:xy(gradeX + boxW/2, 6):zoom(0.28):halign(0.5):valign(0.5)
			self:diffuse(color("#00ff00"))
		end,
		RedrawCommand = function(self, data)
			if data.showGradesOnly and (data.grade == "Grade_None" or data.grade == "Grade_Tier17") then
				self:settext(""); return
			end
			self:settext(formatRateAndTimestamp(data))
			self:diffuse(data.showPBTimestamps and color("#BBBBBB") or color("#00ff00"))
		end
	},

	-- ═══ CLEARTYPE BOX (right) — shown for every song that has scores ════════
	Def.Quad {
		InitCommand = function(self)
			self:xy(clearX, -2):zoomto(boxW, boxH):halign(0):valign(0.5)
			self:diffuse(color("#000000")):diffusealpha(0.6)
		end,
		RedrawCommand = function(self, data)
			self:visible(data.score ~= nil)
		end
	},
	LoadFont("Common Normal") .. {
		InitCommand = function(self)
			self:xy(clearX + boxW/2, -8):zoom(0.4):halign(0.5):valign(0.5)
		end,
		RedrawCommand = function(self, data)
			if data.score then
				self:settext(getClearType(data.score, 0))
				self:diffuse(getClearType(data.score, 2))
			else
				self:settext("")
			end
		end
	},
	LoadFont("Common Normal") .. {
		InitCommand = function(self)
			self:xy(clearX + boxW/2, 6):zoom(0.28):halign(0.5):valign(0.5)
			self:diffuse(color("#00ff00"))
		end,
		RedrawCommand = function(self, data)
			if not data.score then
				self:settext("")
				return
			end
			self:settext(formatRateAndTimestamp(data))
			self:diffuse(data.showPBTimestamps and color("#BBBBBB") or color("#00ff00"))
		end
	},

	-- ═══ INDICATORS ═════════════════════════════════════════════════════════
	Def.Quad {
		InitCommand = function(self)
			self:xy((boxW/2 * -1) + 22, -2):zoomto(3, boxH):halign(0.5):valign(0.5)
		end,
		RedrawCommand = function(self, data)
			if data.grade ~= "Grade_None" and data.grade ~= "Grade_Tier17" then
				self:diffuse(getDifficultyColor("Difficulty_" .. data.diff))
				self:diffusealpha(0.7)
			else
				self:diffusealpha(0)
			end
		end
	},
	Def.Sprite {
		InitCommand = function(self) self:xy(gradeX - 96, -12):zoomto(4, 19) end,
		RedrawCommand = function(self, data)
			if data.mirror then
				self:Load(THEME:GetPathG("", "mirror")):zoomto(14, 14):visible(true)
			else
				self:visible(false)
			end
		end
	},
	Def.Sprite {
		InitCommand = function(self) self:xy(gradeX - 96, 4):zoomto(4, 19) end,
		RedrawCommand = function(self, data)
			if data.fav then
				self:Load(THEME:GetPathG("", "favorite")):zoomto(14, 14):visible(true)
			else
				self:visible(false)
			end
		end
	}
}
