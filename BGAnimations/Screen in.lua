-- Expanding triangle transition (in) - triangle shrinks to reveal new screen
return Def.ActorMultiVertex {
	InitCommand = function(self)
		local size = SCREEN_WIDTH + SCREEN_HEIGHT
		self:SetVertices({
			{{0, -size, 0}, color("0,0,0,1")},      -- top point
			{{-size, size, 0}, color("0,0,0,1")},   -- bottom left
			{{size, size, 0}, color("0,0,0,1")}     -- bottom right
		})
		self:SetDrawState {Mode = "DrawMode_Triangles"}
		self:xy(SCREEN_CENTER_X, SCREEN_CENTER_Y)
	end,
	OnCommand = function(self)
		self:sleep(0.05):linear(0.25):zoom(0)
	end
}
