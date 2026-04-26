local AvatarX = SCREEN_WIDTH - 180
local AvatarY = 17
local profileDropdownDrawOrder = 10000
-- Old avatar actor frame.. renamed since much more will be placed here (hopefully?)
local t =
	Def.ActorFrame {
	Name = "PlayerAvatar",
	BeginCommand = function(self)
		self:draworder(profileDropdownDrawOrder)
		self:SortByDrawOrder()
	end,
}

local username = ""
local profile

local profileName = THEME:GetString("GeneralInfo", "NoProfile")
local playCount = 0
local playTime = 0
local noteCount = 0
local numfaves = 0
local playerRating = 0
local uploadbarwidth = 100
local uploadbarheight = 10
local profileMenuOpen = false
local profileMenuWidth = 150
local profileMenuItemHeight = 32
local loginButtonWidth = 125
local loginButtonHeight = 26
local translated_info

local ButtonColor = getMainColor("positive")
local nonButtonColor = ColorMultiplier(getMainColor("positive"), 1.25)
--------UNCOMMENT THIS NEXT LINE IF YOU WANT THE OLD LOOK--------
--nonButtonColor = getMainColor("positive")

local setnewdisplayname = function(answer)
	if answer ~= "" then
		profile:RenameProfile(answer)
		profileName = answer
		MESSAGEMAN:Broadcast("ProfileRenamed", {doot = answer})
	end
end

local function highlightIfOver(self)
	if isOver(self) then
		local topname = SCREENMAN:GetTopScreen():GetName()
		if topname ~= "ScreenEvaluationNormal" and topname ~= "ScreenNetEvaluation" then
			self:diffusealpha(0.6)
		end
	else
		self:diffusealpha(1)
	end
end

local function pointInRect(x, y, left, top, width, height)
	return x >= left and x <= left + width and y >= top and y <= top + height
end

local function isOverLoginButton(mouseX, mouseY)
	return pointInRect(mouseX, mouseY, AvatarX + 22, AvatarY - (loginButtonHeight / 2), loginButtonWidth, loginButtonHeight)
end

local function isOverProfileMenu(mouseX, mouseY)
	return pointInRect(mouseX, mouseY, AvatarX + 22, AvatarY + 18, profileMenuWidth, profileMenuItemHeight * 3)
end

local function setProfileMenuOpen(active)
	profileMenuOpen = active and DLMAN:IsLoggedIn() or false
	MESSAGEMAN:Broadcast("ProfileMenuStateChanged")
end

local function isTitleScreen()
	local top = SCREENMAN and SCREENMAN.GetTopScreen and SCREENMAN:GetTopScreen() or nil
	return top and top.GetName and top:GetName() == "ScreenTitleMenu"
end

local function isEvaluationScreen()
	local top = SCREENMAN and SCREENMAN.GetTopScreen and SCREENMAN:GetTopScreen() or nil
	if not top or not top.GetName then return false end
	local name = top:GetName()
	return name == "ScreenEvaluation" or name == "ScreenEvaluationNormal" or name == "ScreenNetEvaluation"
end

local function performLogout(self)
	if DLMAN:IsLoggedIn() then
		local slot = pn_to_profile_slot and pn_to_profile_slot(PLAYER_1) or nil
		local profile = PROFILEMAN and PROFILEMAN.GetProfile and PROFILEMAN:GetProfile(PLAYER_1) or nil
		local hasLocalProfile = profile and profile.GetDisplayName and profile:GetDisplayName() ~= ""
		if slot and hasLocalProfile then
			playerConfig:get_data(slot).UserName = ""
			playerConfig:get_data(slot).PasswordToken = ""
			playerConfig:set_dirty(slot)
			playerConfig:save(slot)
		end
		DLMAN:Logout()
	end
	setProfileMenuOpen(false)
	self:settext(translated_info["NotLoggedIn"])
end

translated_info = {
	ProfileNew = THEME:GetString("ProfileChanges", "ProfileNew"),
	NameChange = THEME:GetString("ProfileChanges", "ProfileNameChange"),
	ClickLogin = THEME:GetString("GeneralInfo", "ClickToLogin"),
	ClickLogout = THEME:GetString("GeneralInfo", "ClickToLogout"),
	NotLoggedIn = THEME:GetString("GeneralInfo", "NotLoggedIn"),
	LoggedInAs = THEME:GetString("GeneralInfo", "LoggedInAs.."),
	LoginFailed = THEME:GetString("GeneralInfo", "LoginFailed"),
	LoginSuccess = THEME:GetString("GeneralInfo", "LoginSuccess"),
	LoginCanceled = THEME:GetString("GeneralInfo", "LoginCanceled"),
	Password = THEME:GetString("GeneralInfo","Password"),
	Username = THEME:GetString("GeneralInfo","Email"),
	Plays = THEME:GetString("GeneralInfo", "ProfilePlays"),
	PlaysThisSession = THEME:GetString("GeneralInfo", "PlaysThisSession"),
	TapsHit = THEME:GetString("GeneralInfo", "ProfileTapsHit"),
	Playtime = THEME:GetString("GeneralInfo", "ProfilePlaytime"),
	Judge = THEME:GetString("GeneralInfo", "ProfileJudge"),
	RefreshSongs = THEME:GetString("GeneralInfo", "DifferentialReloadTrigger"),
	SongsLoaded = THEME:GetString("GeneralInfo", "ProfileSongsLoaded"),
	SessionTime = THEME:GetString("GeneralInfo", "SessionTime"),
	GroupsLoaded = THEME:GetString("GeneralInfo", "GroupsLoaded"),
}

local function UpdateTime(self)
	-- Function disabled, the time is rendered elsewhere

end

-- handle logging in exactly like Til Death
local function loginStep1(self)
	local redir = SCREENMAN:get_input_redirected(PLAYER_1)
	local function off()
		if redir then
			SCREENMAN:set_input_redirected(PLAYER_1, false)
		end
	end
	local function on()
		if redir then
			SCREENMAN:set_input_redirected(PLAYER_1, true)
		end
	end
	off()

	username = ""

	easyInputStringOKCancel(
		translated_info["Username"]..":", 255, true,
		function(answer)
			username = answer
			if answer:gsub("^%s*(.-)%s*$", "%1") ~= "" then
				self:sleep(0.04):queuecommand("LoginStep2")
			else
				ms.ok(translated_info["LoginCanceled"])
				on()
			end
		end,
		function()
			ms.ok(translated_info["LoginCanceled"])
			on()
		end
	)
end

local function loginStep2()
	local password = ""
	easyInputStringOKCancel(
		translated_info["Password"]..":", 255, true,
		function(answer)
			password = answer
			if answer:gsub("^%s*(.-)%s*$", "%1") ~= "" then
				DLMAN:Login(username, password)
			else
				ms.ok(translated_info["LoginCanceled"])
			end
		end,
		function()
			ms.ok(translated_info["LoginCanceled"])
		end
	)
end



t[#t + 1] = Def.Actor {
	BeginCommand = function(self)
		self:queuecommand("Set")
	end,
	SetCommand = function(self)
		profile = GetPlayerOrMachineProfile(PLAYER_1)
		profileName = profile:GetDisplayName()
		playCount = SCOREMAN:GetTotalNumberOfScores()
		playTime = profile:GetTotalSessionSeconds()
		noteCount = profile:GetTotalTapsAndHolds()
		playerRating = profile:GetPlayerRating()
	end,
	PlayerRatingUpdatedMessageCommand = function(self)
		playerRating = profile:GetPlayerRating()
		self:GetParent():GetDescendant("AvatarPlayerNumber_P1", "Name"):playcommand("Set")
	end
}

t[#t + 1] = Def.ActorFrame {
	Name = "Avatar" .. PLAYER_1,
	BeginCommand = function(self)
		self:draworder(profileDropdownDrawOrder - 20)
		self:queuecommand("Set")
	end,
	SetCommand = function(self)
		if isTitleScreen() then
			self:visible(true)
		elseif profile == nil then
			self:visible(false)
		else
			self:visible(true)
		end
	end,
	UIElements.SpriteButton(1, 1, nil) .. {
		Name = "Image",
		InitCommand = function(self)
			self:visible(false):halign(0):valign(0.5):xy(AvatarX, AvatarY)
		end,
		BeginCommand = function(self)
			self:queuecommand("ModifyAvatar")
		end,
		ModifyAvatarCommand = function(self)
			self:finishtweening()
			self:Load(getAvatarPath(PLAYER_1))
			self:zoomto(50, 50)
		end,
		MouseDownCommand = function(self, params)
			if params.event == "DeviceButton_left mouse button" and not SCREENMAN:get_input_redirected(PLAYER_1) then
				local top = SCREENMAN:GetTopScreen()
				SCREENMAN:SetNewScreen("ScreenAssetSettings")
			end
		end
	},
	UIElements.TextToolTip(1, 1, "Common Normal") .. {
		Name = "Name",
		InitCommand = function(self)
			self:halign(1) -- Right align to point at the button
			self:xy(AvatarX + 15, AvatarY)
			self:zoom(0.45)
			self:maxwidth(capWideScale(200,300))
			self:diffuse(ButtonColor)
		end,
		SetCommand = function(self)
			if isTitleScreen() then
				self:settext("")
				self:visible(false)
				return
			end
			self:visible(true)
			self:settextf("%s (%5.2f)", profileName, playerRating)
		end,
		MouseDownCommand = function(self, params)
			if params.event == "DeviceButton_left mouse button" and not SCREENMAN:get_input_redirected(PLAYER_1) then
				easyInputStringWithFunction(translated_info["NameChange"], 64, false, setnewdisplayname)
			end
		end,
		ProfileRenamedMessageCommand = function(self, params)
			self:settextf("%s (%5.2f)", params.doot, playerRating)
		end,
		MouseOverCommand = function(self)
			highlightIfOver(self)
		end,
		MouseOutCommand = function(self)
			highlightIfOver(self)
		end,
	},
	Def.ActorFrame {
		Name = "LoginButtonFrame",
		InitCommand = function(self)
			self:xy(AvatarX + 22, AvatarY):draworder(profileDropdownDrawOrder)
		end,
		BeginCommand = function(self)
			SCREENMAN:GetTopScreen():AddInputCallback(function(event)
				if not profileMenuOpen then return end
				if event.type ~= "InputEventType_FirstPress" then return end
				local deviceButton = event.DeviceInput and event.DeviceInput.button or ""
				if event.button == "Back" or deviceButton == "DeviceButton_right mouse button" then
					setProfileMenuOpen(false)
					return true
				end
				if deviceButton == "DeviceButton_left mouse button" then
					local mouseX = INPUTFILTER:GetMouseX()
					local mouseY = INPUTFILTER:GetMouseY()
					if not isOverLoginButton(mouseX, mouseY) and not isOverProfileMenu(mouseX, mouseY) then
						setProfileMenuOpen(false)
					end
				end
			end)
			self:queuecommand("UpdateLoginStatus")
		end,
		UpdateLoginStatusCommand = function(self)
			-- Background now always uses the dynamic accent color as requested
			-- The diffuse is handled by the BGSprite actor directly via messages
			-- but we ensure the alpha is consistent here.
			self:GetChild("BGSprite"):diffusealpha(0.8)
			self:GetChild("ProfileMenu"):queuecommand("Set")
		end,
		DLMANLoginMessageCommand = function(self) self:queuecommand("UpdateLoginStatus") end,
		DLMANLogoutMessageCommand = function(self)
			setProfileMenuOpen(false)
			self:queuecommand("UpdateLoginStatus")
		end,
		ProfileMenuStateChangedMessageCommand = function(self)
			self:GetChild("ProfileMenu"):queuecommand("Set")
		end,

		Def.Quad {
			Name = "BGSprite",
			InitCommand = function(self)
				self:zoomto(loginButtonWidth, loginButtonHeight):halign(0):valign(0.5):xy(0, 0):diffuse(getMainColor("highlight")):diffusealpha(0.8)
			end,
			SetDynamicAccentColorMessageCommand = function(self, params)
				if isEvaluationScreen() then
					self:finishtweening():linear(0.2):diffuse(getMainColor("highlight")):diffusealpha(0.8)
				else
					self:finishtweening():linear(0.2):diffuse(params.color):diffusealpha(0.8)
				end
			end
		},
		Def.Sprite {
			Name = "GlobeIcon",
			Texture = THEME:GetPathG("", "Interlude Icons/globe-solid.png"),
			InitCommand = function(self)
				self:xy(16, 0):halign(0.5):valign(0.5):diffuse(color("#22CC66"))
			end,
			OnCommand = function(self)
				local width = self:GetWidth()
				local height = self:GetHeight()
				if width > 0 and height > 0 then
					self:zoom((48 / math.max(width, height)) * 0.4)
				end
			end,
		},
		UIElements.TextToolTip(1, 1, "Common Normal") .. {
			Name = "loginlogout",
			InitCommand = function(self)
				self:xy(71, 0):halign(0.5):zoom(0.40):diffuse(color("#22CC66")) -- Green at all times
			end,
			BeginCommand = function(self)
				self:queuecommand("Set")
			end,
			SetCommand = function(self)
				if DLMAN:IsLoggedIn() then
					self:queuecommand("Login")
				else
					self:queuecommand("LogOut")
				end
			end,
			LogOutMessageCommand = function(self)
				performLogout(self)
			end,
		LoginMessageCommand = function(self)
			if not SCREENMAN:GetTopScreen() then return end
			local top = SCREENMAN:GetTopScreen():GetName()
			if not DLMAN:IsLoggedIn() then return end
			local slot = pn_to_profile_slot and pn_to_profile_slot(PLAYER_1) or nil
			local profile = PROFILEMAN and PROFILEMAN.GetProfile and PROFILEMAN:GetProfile(PLAYER_1) or nil
			local hasLocalProfile = profile and profile.GetDisplayName and profile:GetDisplayName() ~= ""
			if slot and hasLocalProfile then
				playerConfig:get_data(slot).UserName = DLMAN:GetUsername()
				playerConfig:get_data(slot).PasswordToken = DLMAN:GetToken()
				playerConfig:set_dirty(slot)
				playerConfig:save(slot)
			end
			
			self:settextf(
				"%s (%5.2f)",
				DLMAN:GetUsername(),
				DLMAN:GetSkillsetRating("Overall")
			)
		end,
		MouseDownCommand = function(self, params)
			if params.event == "DeviceButton_left mouse button" and not SCREENMAN:get_input_redirected(PLAYER_1) then
				if DLMAN:IsLoggedIn() then
					setProfileMenuOpen(not profileMenuOpen)
				else
					setProfileMenuOpen(false)
					loginStep1(self)
				end
			elseif params.event == "DeviceButton_right mouse button" and not SCREENMAN:get_input_redirected(PLAYER_1) then
				if DLMAN:IsLoggedIn() then
					setProfileMenuOpen(false)
					self:queuecommand("LogOut")
				end
			end
		end,
		OnlineUpdateMessageCommand = function(self)
			self:queuecommand("Set")
		end,
		MouseOverCommand = function(self)
			highlightIfOver(self)
		end,
		MouseOutCommand = function(self)
			highlightIfOver(self)
		end,
		LoginFailedMessageCommand = function(self, params)
			ms.ok(translated_info["LoginFailed"] .. " -- " .. params.why)
		end,
		LoginHotkeyPressedMessageCommand = function(self)
			if DLMAN:IsLoggedIn() then
				setProfileMenuOpen(false)
				self:queuecommand("LogOut")
			else
				loginStep1(self)
			end
		end,
		LoginStep2Command = function(self)
			loginStep2()
		end
		},
		Def.ActorFrame {
			Name = "ProfileMenu",
			InitCommand = function(self)
				self:xy(0, 18):draworder(profileDropdownDrawOrder + 20)
			end,
			SetCommand = function(self)
				self:visible(profileMenuOpen and DLMAN:IsLoggedIn())
			end,
			DLMANLoginMessageCommand = function(self)
				self:queuecommand("Set")
			end,
			DLMANLogoutMessageCommand = function(self)
				self:queuecommand("Set")
			end,
			ProfileMenuStateChangedMessageCommand = function(self)
				self:queuecommand("Set")
			end,
			Def.Quad {
				InitCommand = function(self)
					self:halign(0):valign(0):zoomto(profileMenuWidth, profileMenuItemHeight * 3):diffuse(color("#000000")):diffusealpha(0.75)
				end
			},
			Def.Quad {
				InitCommand = function(self)
					self:halign(0):valign(0):zoomto(profileMenuWidth, profileMenuItemHeight * 3):diffuse(getMainColor("highlight")):diffusealpha(0.35)
				end,
				SetDynamicAccentColorMessageCommand = function(self, params)
					if isEvaluationScreen() then
						self:finishtweening():linear(0.2):diffuse(getMainColor("highlight")):diffusealpha(0.35)
					else
						self:finishtweening():linear(0.2):diffuse(params.color):diffusealpha(0.35)
					end
				end
			},
			(function()
				local function menuItem(index, label, action)
					return Def.ActorFrame {
						InitCommand = function(self)
							self:y((index - 1) * profileMenuItemHeight)
						end,
						UIElements.QuadButton(1, 1) .. {
							InitCommand = function(self)
								self:halign(0):valign(0):zoomto(profileMenuWidth, profileMenuItemHeight):diffuse(color("#000000")):diffusealpha(0)
							end,
							MouseOverCommand = function(self)
								self:diffuse(getMainColor("highlight")):diffusealpha(0.35)
							end,
							MouseOutCommand = function(self)
								self:diffuse(color("#000000")):diffusealpha(0)
							end,
							MouseDownCommand = function(self, params)
								if params.event == "DeviceButton_left mouse button" then
									setProfileMenuOpen(false)
									action(self)
								end
							end
						},
						LoadFont("Common Normal") .. {
							InitCommand = function(self)
								self:xy(12, profileMenuItemHeight / 2):halign(0):zoom(0.45):settext(label)
							end
						}
					}
				end
				local menu = Def.ActorFrame {}
				menu[#menu + 1] = menuItem(1, "Multiplayer", function()
					SCREENMAN:SetNewScreen(Branch.MultiScreen())
				end)
				menu[#menu + 1] = menuItem(2, "Profile", function()
					DLMAN:ShowUserPage(DLMAN:GetUsername())
				end)
				menu[#menu + 1] = menuItem(3, "Log out", function(self)
					self:GetParent():GetParent():GetParent():GetParent():GetChild("loginlogout"):queuecommand("LogOut")
				end)
				return menu
			end)()
		},
	},
}





local function UpdateAvatar(self)
	if getAvatarUpdateStatus() then
		self:GetChild("Avatar" .. PLAYER_1):GetChild("Image"):queuecommand("ModifyAvatar")
		setAvatarUpdateStatus(PLAYER_1, false)
	end
end


t.InitCommand = function(self)
	self:SetUpdateFunction(UpdateAvatar)
end

return t
