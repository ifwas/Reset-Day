local defaultConfig = {
	global = {
		TipType = 1, -- 1 = Hide,2=tips 3= random quotes phrases,
		RateSort = true,
		HelpMenu = false,
		MeasureLines = false,
		ProgressBar = 1, -- 0 = bottom, 1 = top
		ShowVisualizer = true,
		InstantSearch = true, -- true = search per press, false = search on enter button
		IgnoreTabInput = 1, -- 1 = dont ignore, 2 = ignore only in search, 3 = always
		JudgmentTween = false,
		ComboTween = false,
		CenteredCombo = false,
		FadeNoteFieldInSyncMachine = true,
		ShowPlayerOptionsHint = false,
		ShowBanners = true, -- false to turn off banners everywhere
		LastSongChartKey = "",
		LastSampleMusicPosition = 0,
		MusicWheelDisplaySettings = {
			OnlyShowGrades = true,
			ShowPBTimestamps = true,
			ShowNativeMetadata = true,
		},
	},
	NPSDisplay = {
		MaxWindow = 2,
		MinWindow = 1 -- unused.
	},
}

themeConfig = create_setting("themeConfig", "themeConfig.lua", defaultConfig, -1)
themeConfig:load()

function JudgementTweensEnabled()
	return themeConfig:get_data().global.JudgmentTween
end
function ComboTweensEnabled()
	return themeConfig:get_data().global.ComboTween
end
function CenteredComboEnabled()
	return themeConfig:get_data().global.CenteredCombo
end
function BannersEnabled()
	return themeConfig:get_data().global.ShowBanners
end

function getMusicWheelDisplaySettings()
	local globalConfig = themeConfig:get_data().global
	globalConfig.MusicWheelDisplaySettings = globalConfig.MusicWheelDisplaySettings or {}
	local settings = globalConfig.MusicWheelDisplaySettings
	if settings.OnlyShowGrades == nil then settings.OnlyShowGrades = true end
	if settings.ShowPBTimestamps == nil then settings.ShowPBTimestamps = true end
	if settings.ShowNativeMetadata == nil then
		local ok, pref = pcall(function() return PREFSMAN:GetPreference("ShowNativeLanguage") end)
		settings.ShowNativeMetadata = ok and pref or true
	end
	return settings
end

function getMusicWheelDisplaySetting(key)
	local settings = getMusicWheelDisplaySettings()
	return settings[key]
end

function setMusicWheelDisplaySetting(key, value)
	local settings = getMusicWheelDisplaySettings()
	if settings[key] == value then return false end
	settings[key] = value
	themeConfig:set_dirty()
	themeConfig:save()
	if key == "ShowNativeMetadata" then
		pcall(function() PREFSMAN:SetPreference("ShowNativeLanguage", value) end)
		pcall(function() PREFSMAN:SavePreferences() end)
		MESSAGEMAN:Broadcast("DisplayLanguageChanged")
	end
	MESSAGEMAN:Broadcast("MusicWheelDisplaySettingsChanged", {key = key, value = value})
	return true
end