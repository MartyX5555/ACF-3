local cat = ((ACF.CustomToolCategory and ACF.CustomToolCategory:GetBool()) and "ACF" or "Construction")
TOOL.Category = cat
TOOL.Name = "#Tool.acfsound.name"
TOOL.Command = nil
TOOL.ConfigName = ""
TOOL.ClientConVar["pitch"] = "1"

if CLIENT then

	TOOL.Information = {

		{ name = "left", icon = "gui/lmb.png" },
		{ name = "right", icon = "gui/rmb.png" },
		{ name = "reload", icon = "gui/r.png" },

	}

	language.Add("Tool.acfsound.name", "ACF Sound Replacer")
	language.Add("Tool.acfsound.desc", "Change sound of the ACF entities.")

	language.Add( "Tool.acfsound.left", "Apply the new sound. You can use empty sounds too." )
	language.Add( "Tool.acfsound.right", "Copy the sound." )
	language.Add( "Tool.acfsound.reload", "Reset to default sound." )

end

ACF.SoundToolSupport = ACF.SoundToolSupport or {}

local Sounds   = ACF.SoundToolSupport
local Messages = ACF.Utilities.Messages

Sounds.acf_gun = {
	GetSound = function(ent)
		return {
			Sound = ent.SoundPath
		}
	end,
	SetSound = function(ent, soundData)
		ent.SoundPath = soundData.Sound
		ent:SetNWString("Sound", soundData.Sound)
	end,
	ResetSound = function(ent)
		ent.SoundPath = ent.DefaultSound
		ent:SetNWString("Sound", ent.DefaultSound)
	end
}

Sounds.acf_engine = {
	GetSound = function(ent)
		return {
			Sound = ent.SoundPath,
			Pitch = ent.SoundPitch
		}
	end,
	SetSound = function(ent, soundData)
		local Sound     = soundData.Sound:Trim():lower()
		local Extension = string.GetExtensionFromFilename(Sound)

		if (Sound ~= "" and not Extension) or not file.Exists("sound/" .. Sound, "GAME") then
			local Owner = ent:GetPlayer()

			return Messages.SendChat(Owner, "Error", "Couldn't change engine sound, does not exist on server: ", Sound)
		end

		ent.SoundPath = Sound
		ent.SoundPitch = soundData.Pitch

		ent:UpdateSound()
	end,
	ResetSound = function(ent)
		ent.SoundPath  = ent.DefaultSound
		ent.SoundPitch = 1

		ent:UpdateSound()
	end
}

Sounds.acf_gearbox = {
	GetSound = function(ent)
		return { Sound = ent.SoundPath }
	end,
	SetSound = function(ent, soundData)
		ent.SoundPath = soundData.Sound
	end,
	ResetSound = function(ent)
		ent.SoundPath = ent.DefaultSound
	end
}

Sounds.acf_piledriver = {
	GetSound = function(ent)
		return { Sound = ent.SoundPath or "" }
	end,
	SetSound = function(ent, soundData)
		ent.SoundPath = soundData.Sound
	end,
	ResetSound = function(ent)
		ent.SoundPath = nil
	end
}

local function ReplaceSound(_, Entity, Data)
	if not IsValid(Entity) then return end

	local Support = Sounds[Entity:GetClass()]
	local Sound, Pitch = unpack(Data)

	if not Support then return end

	Support.SetSound(Entity, {
		Sound = Sound,
		Pitch = Pitch or 1,
	})

	duplicator.StoreEntityModifier(Entity, "acf_replacesound", { Sound, Pitch or 1 })
end

duplicator.RegisterEntityModifier("acf_replacesound", ReplaceSound)

local function IsReallyValid(trace, ply)
	if not trace.Entity:IsValid() then return false end
	if trace.Entity:IsPlayer() then return false end
	if SERVER and not trace.Entity:GetPhysicsObject():IsValid() then return false end
	local class = trace.Entity:GetClass()

	if not ACF.SoundToolSupport[class] then
		if string.StartWith(class, "acf_") then
			ACF.SendNotify(ply, false, class .. " is not supported by the sound tool!")
		else
			ACF.SendNotify(ply, false, "Only ACF entities are supported by the ACF sound tool!")
		end

		return false
	end

	return true
end

function TOOL:LeftClick(trace)
	if CLIENT then return true end
	if not IsReallyValid(trace, self:GetOwner()) then return false end
	local sound = self:GetOwner():GetInfo("wire_soundemitter_sound")
	local pitch = self:GetOwner():GetInfo("acfsound_pitch")
	ReplaceSound(self:GetOwner(), trace.Entity, {sound, pitch})

	return true
end

function TOOL:RightClick(trace)
	if CLIENT then return true end
	if not IsReallyValid(trace, self:GetOwner()) then return false end
	local class = trace.Entity:GetClass()
	local support = ACF.SoundToolSupport[class]
	if not support then return false end
	local soundData = support.GetSound(trace.Entity)
	self:GetOwner():ConCommand("wire_soundemitter_sound " .. soundData.Sound)

	if soundData.Pitch then
		self:GetOwner():ConCommand("acfsound_pitch " .. soundData.Pitch)
	end

	return true
end

function TOOL:Reload(trace)
	if CLIENT then return true end
	if not IsReallyValid(trace, self:GetOwner()) then return false end
	local class = trace.Entity:GetClass()
	local support = ACF.SoundToolSupport[class]
	if not support then return false end
	support.ResetSound(trace.Entity)

	return true
end

if CLIENT then

	function TOOL.BuildCPanel(panel)
		local wide = panel:GetWide()

		local Desc = panel:Help( "Replace default sounds of certain ACF entities with this tool.\n" )
		Desc:SetFont("ACF_Control")

		local SoundNameText = vgui.Create("DTextEntry", ValuePanel)
		SoundNameText:SetText("")
		SoundNameText:SetWide(wide - 20)
		SoundNameText:SetTall(20)
		SoundNameText:SetMultiline(false)
		SoundNameText:SetConVar("wire_soundemitter_sound")
		SoundNameText:SetVisible(true)
		SoundNameText:Dock(LEFT)
		panel:AddItem(SoundNameText)

		local SoundBrowserButton = vgui.Create("DButton")
		SoundBrowserButton:SetText("Open Sound Browser")
		SoundBrowserButton:SetFont("ACF_Control")
		SoundBrowserButton:SetWide(wide)
		SoundBrowserButton:SetTall(20)
		SoundBrowserButton:SetVisible(true)
		SoundBrowserButton:SetIcon( "icon16/application_view_list.png" )
		SoundBrowserButton.DoClick = function()
			RunConsoleCommand("wire_sound_browser_open", SoundNameText:GetValue(), "1")
		end
		panel:AddItem(SoundBrowserButton)

		local SoundPre = vgui.Create("DPanel")
		SoundPre:SetWide(wide)
		SoundPre:SetTall(20)
		SoundPre:SetVisible(true)

		local SoundPrePlay = vgui.Create("DButton", SoundPre)
		SoundPrePlay:SetText("Play")
		SoundPrePlay:SetFont("ACF_Control")
		SoundPrePlay:SetVisible(true)
		SoundPrePlay:SetIcon( "icon16/sound.png" )
		SoundPrePlay.DoClick = function()
			RunConsoleCommand("play",SoundNameText:GetValue())
		end

		local SoundPreStop = vgui.Create("DButton", SoundPre)
		SoundPreStop:SetText("Stop")
		SoundPreStop:SetFont("ACF_Control")
		SoundPreStop:SetVisible(true)
		SoundPreStop:SetIcon( "icon16/sound_mute.png" )
		SoundPreStop.DoClick = function()
			RunConsoleCommand("play", "common/NULL.WAV") --Playing a silent sound will mute the preview but not the sound emitters.
		end
		panel:AddItem(SoundPre)

		-- Set the Play/Stop button positions here
		SoundPre:InvalidateLayout(true)
		SoundPre.PerformLayout = function()
			local HWide = SoundPre:GetWide() / 2
			local Tall = SoundPre:GetTall()
			SoundPrePlay:SetSize(HWide, Tall)
			SoundPrePlay:Dock(LEFT)

			SoundPreStop:SetSize(Tall, Tall)
			SoundPreStop:Dock(FILL)
		end

		local CopyButton = vgui.Create("DButton")
		CopyButton:SetText("Copy to clipboard")
		CopyButton:SetFont("ACF_Control")
		CopyButton:SetWide(wide)
		CopyButton:SetTall(20)
		CopyButton:SetIcon( "icon16/page_copy.png" )
		CopyButton:SetVisible(true)
		CopyButton.DoClick = function()
			SetClipboardText( SoundNameText:GetValue())
		end
		panel:AddItem(CopyButton)

		local ClearButton = vgui.Create("DButton")
		ClearButton:SetText("Clear Sound")
		ClearButton:SetFont("ACF_Control")
		ClearButton:SetWide(wide)
		ClearButton:SetTall(20)
		ClearButton:SetIcon( "icon16/cancel.png" )
		ClearButton:SetVisible(true)
		ClearButton.DoClick = function()
			SoundNameText:SetValue("")
			RunConsoleCommand("wire_soundemitter_sound", "")
		end
		panel:AddItem(ClearButton)

		panel:NumSlider( "Pitch", "acfsound_pitch", 0.1, 2.55, 2 )

		panel:ControlHelp( "Adjust the pitch of the sound. Currently supports engines only." )
	end

	--[[
		This is another dirty hack that prevents the sound emitter tool from automatically equipping when a sound is selected in the sound browser.
		However, this hack only applies if the currently equipped tool is the sound replacer and you're trying to switch to the wire sound tool.
		Additionally, if you're using a weapon instead of a tool and you choose a sound while the sound replacer menu is displayed, you will be redirected to it.

		The sound emitter will be equipped normally when switching to any other tool at the time of the change.
	]]

	spawnmenu.ActivateToolLegacy = spawnmenu.ActivateToolLegacy or spawnmenu.ActivateTool

	function spawnmenu.ActivateTool( tool, bool_menu, ... )

		local CurTool = LocalPlayer():GetTool()

		if CurTool and CurTool.Mode then

			local CurMode = isstring(CurTool.Mode) and CurTool.Mode or ""

			if tool == "wire_soundemitter" and CurMode == "acfsound" then
				tool = CurMode
			end

		end

		spawnmenu.ActivateToolLegacy( tool, bool_menu, ... )
	end

end