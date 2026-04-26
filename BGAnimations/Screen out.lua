-- Expanding triangle transition (out) - triangle expands to cover screen
local t = Def.ActorFrame {}

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
		self:sleep(0.05):linear(0.25):zoom(SCREEN_WIDTH + SCREEN_HEIGHT)
	end
}

return t
