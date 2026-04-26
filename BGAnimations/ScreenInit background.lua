local t = Def.ActorFrame {}

t[#t + 1] =
	Def.Quad {
	InitCommand = function(self)
		self:xy(0, 0):halign(0):valign(0):zoomto(SCREEN_WIDTH, SCREEN_HEIGHT):diffuse(color("#111111")):diffusealpha(0):linear(
			1
		):diffusealpha(1):sleep(1.75):linear(2):diffusealpha(0)
	end
}

t[#t + 1] =
	Def.ActorFrame {
	InitCommand = function(self)
		self:Center()
	end,
	LeftClickMessageCommand = function(self)
		SCREENMAN:GetTopScreen():StartTransitioningScreen("SM_GoToNextScreen")
	end,
	LoadFont("Common Normal") ..
		{
			Text = "Loading",
			InitCommand = function(self)
				self:y(-150):zoom(0.9)
			end,
			OnCommand = function(self)
				self:diffusealpha(0):sleep(0.5):linear(0.5):diffusealpha(1):sleep(1.75):linear(0.7):diffusealpha(0)
			end
		},
	LoadActor(THEME:GetPathG("", "logo")) .. {
		InitCommand = function(self)
			self:y(76):zoomto(220, 220)
		end,
		OnCommand = function(self)
			self:diffusealpha(0):sleep(0.5):linear(0.5):diffusealpha(1):smooth(1):y(0)
		end,
		OffCommand = function(self)
			self:stoptweening():diffusealpha(1):smooth(0.7):xy(150 - SCREEN_CENTER_X, 0)
		end
	}
}

return t
