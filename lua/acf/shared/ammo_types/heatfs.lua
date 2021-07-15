local Ammo = ACF.RegisterAmmoType("HEATFS", "HEAT")

function Ammo:OnLoaded()
	Ammo.BaseClass.OnLoaded(self)

	self.Name		 = "High Explosive Anti-Tank Fin Stabilized"
	self.Description = "An improved HEAT round with better standoff and explosive power."
	self.Blacklist = ACF.GetWeaponBlacklist({
		SB = true,
	})
end

function Ammo:UpdateRoundData(ToolData, Data, GUIData)
	GUIData = GUIData or Data

	ACF.UpdateRoundSpecs(ToolData, Data, GUIData)

	local CapLength       = GUIData.MinProjLength * 0.5
	local BodyLength      = Data.ProjLength - CapLength
	local FreeVol, FreeLength, FreeRadius = ACF.RoundShellCapacity(Data.PropMass, Data.ProjArea, Data.Caliber, BodyLength)
	local Standoff        = (CapLength + FreeLength * ToolData.StandoffRatio) * 1e-2 -- cm to m
	FreeVol               = FreeVol * (1 - ToolData.StandoffRatio)
	FreeLength            = FreeLength * (1 - ToolData.StandoffRatio)
	local ChargeDiameter  = 2 * FreeRadius
	local MinConeAng      = math.deg(math.atan(FreeRadius / FreeLength))
	local LinerAngle      = math.Clamp(ToolData.LinerAngle, MinConeAng, 90) -- Cone angle is angle between cone walls, not between a wall and the center line
	local LinerMass, ConeVol, ConeLength = self:ConeCalc(LinerAngle, FreeRadius)

	-- Charge length increases jet velocity, but with diminishing returns. All explosive sorrounding the cone has 100% effectiveness,
	--  but the explosive behind it sees it reduced. Most papers put the maximum useful head length (explosive length behind the
	--  cone) at around 1.5-1.8 times the charge's diameter. Past that, adding more explosive won't do much.
	local RearFillLen  = FreeLength - ConeLength  -- Length of explosive behind the liner
	local Exponential  = math.exp(2 * RearFillLen / (ChargeDiameter * ACF.MaxChargeHeadLen))
	local EquivFillLen = ChargeDiameter * ACF.MaxChargeHeadLen * ((Exponential - 1) / (Exponential + 1)) -- Equivalent length of explosive
	local FrontFillVol = FreeVol * ConeLength / FreeLength - ConeVol -- Volume of explosive sorounding the liner
	local RearFillVol  = FreeVol * RearFillLen / FreeLength -- Volume behind the liner
	local EquivFillVol = FreeVol * EquivFillLen / FreeLength + FrontFillVol -- Equivalent total explosive volume
	local FillerEnergy = EquivFillVol * ACF.OctolDensity * 1e3 * ACF.TNTPower * ACF.OctolEquivalent
	local FillerVol    = FrontFillVol + RearFillVol
	local FillerMass   = FillerVol * ACF.OctolDensity

	-- At lower cone angles, the explosive crushes the cone inward, expelling a jet. The steeper the cone, the faster the jet, but the less mass expelled
	local MinVelMult = (0.98 - 0.6) * LinerAngle / 90 + 0.6
	local JetMass    = LinerMass * ((1 - 0.8)* LinerAngle / 90  + 0.8)
	local JetAvgVel  = (2 * FillerEnergy / JetMass) ^ 0.5  -- Average velocity of the copper jet
	local JetMinVel  = JetAvgVel * MinVelMult              -- Minimum velocity of the jet (the rear)
	-- Calculates the maximum velocity, considering the velocity distribution is linear from the rear to the tip (integrated this by hand, pain :) )
	local JetMaxVel  = 0.5 * (3 ^ 0.5 * (8 * FillerEnergy - JetMass * JetMinVel ^ 2) ^ 0.5 / JetMass ^ 0.5 - JetMinVel) -- Maximum velocity of the jet (the tip)

	-- Both the "magic numbers" are unitless, tuning constants that were used to fit the breakup time to real world values, I suggest they not be messed with
	local BreakupTime    = 1.6e-6 * (5e9 * JetMass / (JetMaxVel - JetMinVel)) ^ 0.3333  -- Jet breakup time in seconds
	local BreakupDist    = JetMaxVel * BreakupTime

	GUIData.MinConeAng = MinConeAng

	Data.ConeAng        = LinerAngle
	Data.MinConeAng     = MinConeAng
	Data.FillerMass     = FillerMass
	local NonCasingVol  = ACF.RoundShellCapacity(Data.PropMass, Data.ProjArea, Data.Caliber, Data.ProjLength)
	Data.CasingMass		= (GUIData.ProjVolume - NonCasingVol) * ACF.SteelDensity
	Data.ProjMass       = Data.FillerMass + Data.CasingMass + LinerMass
	Data.MuzzleVel      = ACF.MuzzleVelocity(Data.PropMass, Data.ProjMass, Data.Efficiency)
	Data.BoomFillerMass	= Data.FillerMass * ACF.HEATBoomConvert * ACF.OctolEquivalent -- In TNT equivalent
	Data.LinerMass      = LinerMass
	Data.JetMass        = JetMass
	Data.JetMinVel      = JetMinVel
	Data.JetMaxVel      = JetMaxVel
	Data.BreakupTime    = BreakupTime
	Data.Standoff       = Standoff
	Data.BreakupDist    = BreakupDist
	Data.DragCoef		= Data.ProjArea * 0.0001 / Data.ProjMass
	Data.CartMass		= Data.PropMass + Data.ProjMass

	hook.Run("ACF_UpdateRoundData", self, ToolData, Data, GUIData)

	for K, V in pairs(self:GetDisplayData(Data)) do
		GUIData[K] = V
	end
end

if SERVER then
	function Ammo:Network(Entity, BulletData)
		Ammo.BaseClass.Network(self, Entity, BulletData)

		Entity:SetNW2String("AmmoType", "HEATFS")
	end
else

end
