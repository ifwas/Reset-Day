local t = Def.ActorFrame {}

local translated_info = {
	PressStart = THEME:GetString("ScreenSelectMusic","PressStartForOptions"),
	EnteringOptions = THEME:GetString("ScreenSelectMusic","EnteringOptions"),
}

-- Expanding triangle transition
t[#t + 1] = Def.ActorMultiVertex {
	InitCommand = function(self)
		self:SetVertices({
			{{0, -1, 0}, color("0,0,0,1")},    -- top point
			{{-1, 1, 0}, color("0,0,0,1")},   -- bottom left
			{{1, 1, 0}, color("0,0,0,1")}     -- bottom right
		})
		self:SetDrawState {Mode = "DrawMode_Triangles"}
		self:xy(SCREEN_CENTER_X, SCREEN_CENTER_Y):zoom(0)
	end,
	OnCommand = function(self)
		self:sleep(0.1):linear(0.1):zoom(SCREEN_WIDTH + SCREEN_HEIGHT)
	end
}

-- skip showing the prompt (disabled)
return t
