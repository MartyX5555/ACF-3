-- Local Vars -----------------------------------
local ACF     = ACF
local HookRun = hook.Run

do -- KE Shove
	local Clock = ACF.Utilities.Clock

	function ACF.KEShove(Target, Pos, Vec, KE)
		if not IsValid(Target) then return end

		if HookRun("ACF_KEShove", Target, Pos, Vec, KE) == false then return end

		local Ancestor = ACF_GetAncestor(Target)
		local Phys = Ancestor:GetPhysicsObject()

		if IsValid(Phys) then
			if not Ancestor.acflastupdatemass or Ancestor.acflastupdatemass + 2 < Clock.CurTime then
				ACF_CalcMassRatio(Ancestor)
			end

			local Ratio = Ancestor.acfphystotal / Ancestor.acftotal
			local LocalPos = Ancestor:WorldToLocal(Pos) * Ratio

			Phys:ApplyForceOffset(Vec:GetNormalized() * KE * Ratio, Ancestor:LocalToWorld(LocalPos))
		end
	end
end

do -- Explosions ----------------------------
	local TraceData = { start = true, endpos = true, mask = MASK_SOLID, filter = false }
	local Bullet = {
		IsFrag   = true, -- We need to let people know this isn't a regular bullet somehow
		Owner    = true,
		Gun      = true,
		Caliber  = true,
		Diameter = true,
		ProjArea = true,
		ProjMass = true,
		Flight   = true,
		Speed    = true,
	}

	function Bullet:GetPenetration()
		return ACF.Penetration(self.Speed, self.ProjMass, self.Diameter * 10)
	end

	local function GetRandomPos(Entity, IsChar)
		if IsChar then
			local Mins, Maxs = Entity:OBBMins() * 0.65, Entity:OBBMaxs() * 0.65 -- Scale down the "hitbox" since most of the character is in the middle
			local Rand		 = Vector(math.Rand(Mins[1], Maxs[1]), math.Rand(Mins[2], Maxs[2]), math.Rand(Mins[3], Maxs[3]))

			return Entity:LocalToWorld(Rand)
		else
			local Mesh = Entity:GetPhysicsObject():GetMesh()

			if not Mesh then -- Is Make-Sphericaled
				local Mins, Maxs = Entity:OBBMins(), Entity:OBBMaxs()
				local Rand		 = Vector(math.Rand(Mins[1], Maxs[1]), math.Rand(Mins[2], Maxs[2]), math.Rand(Mins[3], Maxs[3]))

				return Entity:LocalToWorld(Rand:GetNormalized() * math.Rand(1, Entity:BoundingRadius() * 0.5)) -- Attempt to a random point in the sphere
			else
				local Rand = math.random(3, #Mesh / 3) * 3
				local P    = Vector(0, 0, 0)

				for I = Rand - 2, Rand do P = P + Mesh[I].pos end

				return Entity:LocalToWorld(P / 3) -- Attempt to hit a point on a face of the mesh
			end
		end
	end

	-- TODO: Separate this function into multiple chunks, it's absolutely unreadable.
	function ACF.HE(Origin, FillerMass, FragMass, Inflictor, Filter, Gun)
		debugoverlay.Cross(Origin, 15, 15, Color( 255, 255, 255 ), true)
		Filter = Filter or {}

		local Power 	 = FillerMass * ACF.HEPower --Power in KiloJoules of the filler mass of TNT
		local Radius 	 = FillerMass ^ 0.33 * 8 * 39.37 -- Scaling law found on the net, based on 1PSI overpressure from 1 kg of TNT at 15m
		local MaxSphere  = 4 * 3.1415 * (Radius * 2.54) ^ 2 --Surface Area of the sphere at maximum radius
		local Amp 		 = math.min(Power / 2000, 50)
		local Fragments  = math.max(math.floor((FillerMass / FragMass) * ACF.HEFrag), 2)
		local FragWeight = FragMass / Fragments
		local BaseFragV  = (Power * 50000 / FragWeight / Fragments) ^ 0.5
		local Damaged	 = {}
		local Ents 		 = ents.FindInSphere(Origin, Radius)
		local Loop 		 = true -- Find more props to damage whenever a prop dies

		TraceData.filter = Filter
		TraceData.start  = Origin

		util.ScreenShake(Origin, Amp, Amp, Amp / 15, Radius * 10)

		-- We only need to set these once
		Bullet.Owner = Inflictor
		Bullet.Gun   = Gun

		while Loop and Power > 0 do
			Loop = false

			local PowerSpent = 0
			local Damage 	 = {}

			for K, Ent in ipairs(Ents) do -- Find entities to deal damage to
				if not ACF.Check(Ent) then -- Entity is not valid to ACF

					Ents[K] = nil -- Remove from list
					Filter[#Filter + 1] = Ent -- Filter from traces

					continue
				end

				if Damage[Ent] then continue end -- A trace sent towards another prop already hit this one instead, no need to check if we can see it

				if Ent.Exploding then -- Detonate explody things immediately if they're already cooking off
					Ents[K] = nil
					Filter[#Filter + 1] = Ent

					--Ent:Detonate()
					continue
				end

				local IsChar = Ent:IsPlayer() or Ent:IsNPC()
				if IsChar and Ent:Health() <= 0 then
					Ents[K] = nil
					Filter[#Filter + 1] = Ent -- Shouldn't need to filter a dead player but we'll do it just in case

					continue
				end

				local Target = GetRandomPos(Ent, IsChar) -- Try to hit a random spot on the entity
				local Displ	 = Target - Origin

				TraceData.endpos = Origin + Displ:GetNormalized() * (Displ:Length() + 24)

				local TraceRes = ACF.TraceF(TraceData)

				if TraceRes.HitNonWorld then
					Ent = TraceRes.Entity

					if ACF.Check(Ent) then
						if not Ent.Exploding and not Damage[Ent] and not Damaged[Ent] then -- Hit an entity that we haven't already damaged yet (Note: Damaged != Damage)
							local Mul = IsChar and 0.65 or 1 -- Scale down boxes for players/NPCs because the bounding box is way bigger than they actually are

							debugoverlay.Line(Origin, TraceRes.HitPos, 30, Color(0, 255, 0), true) -- Green line for a hit trace
							debugoverlay.BoxAngles(Ent:GetPos(), Ent:OBBMins() * Mul, Ent:OBBMaxs() * Mul, Ent:GetAngles(), 30, Color(255, 0, 0, 1))

							local Pos		= Ent:GetPos()
							local Distance	= Origin:Distance(Pos)
							local Sphere 	= math.max(4 * 3.1415 * (Distance * 2.54) ^ 2, 1) -- Surface Area of the sphere at the range of that prop
							local Area 		= math.min(Ent.ACF.Area / Sphere, 0.5) * MaxSphere -- Project the Area of the prop to the Area of the shadow it projects at the explosion max radius

							Damage[Ent] = {
								Dist  = Distance,
								Displ = Pos - Origin,
								Vec   = (Pos - Origin):GetNormalized(),
								Area  = Area,
								Index = K,
								Trace = TraceRes,
							}

							Ents[K] = nil -- Removed from future damage searches (but may still block LOS)
						end
					else -- If check on new ent fails
						--debugoverlay.Line(Origin, TraceRes.HitPos, 30, Color(255, 0, 0)) -- Red line for a invalid ent

						Ents[K] = nil -- Remove from list
						Filter[#Filter + 1] = Ent -- Filter from traces
					end
				else
					-- Not removed from future damage sweeps so as to provide multiple chances to be hit
					debugoverlay.Line(Origin, TraceRes.HitPos, 30, Color(0, 0, 255)) -- Blue line for a miss
				end
			end

			-- TODO: Add proper fragment support
			-- NOTE: Fragments are flying at several km/s
			for Ent, Table in pairs(Damage) do -- Deal damage to the entities we found
				local AreaFraction 	= Table.Area / MaxSphere
				local PowerFraction = Power * AreaFraction -- How much of the total power goes to that prop
				local Caliber       = math.Rand(0.5, 1) -- Random fragment caliber
				local ProjArea      = math.pi * (Caliber * 0.5) ^ 2
				local FragHit 		= math.floor(Fragments * AreaFraction)
				local FragRes

				Bullet.Caliber  = Caliber
				Bullet.Diameter = Caliber
				Bullet.ProjArea = ProjArea * FragHit
				Bullet.ProjMass = FragWeight * FragHit
				Bullet.Flight   = Table.Displ
				Bullet.Speed    = Bullet.Flight:Length() / ACF.Scale * 0.0254

				local BlastRes = ACF.Damage(Bullet, Table.Trace)
				local Losses   = BlastRes.Loss * 0.5

				if FragHit > 0 then
					local DragCoef = ProjArea * 0.0002 / Bullet.ProjMass

					Bullet.ProjArea = ProjArea
					Bullet.Speed    = ACF.GetRangedSpeed(BaseFragV * 0.0254, DragCoef, Table.Dist) -- NOTE: Assuming BaseFragV is on in/s

					FragRes = ACF.Damage(Bullet, Table.Trace)
					Losses 	= Losses + FragRes.Loss * 0.5
				end

				if BlastRes.Kill or (FragRes and FragRes.Kill) then -- We killed something
					Filter[#Filter + 1] = Ent -- Filter out the dead prop
					Ents[Table.Index]   = nil -- Don't bother looking for it in the future

					local Debris = ACF.HEKill(Ent, Table.Vec, PowerFraction, Origin) -- Make some debris

					for Fireball in pairs(Debris) do
						if IsValid(Fireball) then Filter[#Filter + 1] = Fireball end -- Filter that out too
					end

					Loop = true -- Check for new targets since something died, maybe we'll find something new
				elseif ACF.HEPush then -- Just damaged, not killed, so push on it some
					ACF.KEShove(Ent, Origin, Table.Vec, PowerFraction * 33.3) -- Assuming about 1/30th of the explosive energy goes to propelling the target prop (Power in KJ * 1000 to get J then divided by 33)
				end

				PowerSpent = PowerSpent + PowerFraction * Losses -- Removing the energy spent killing props
				Damaged[Ent] = true -- This entity can no longer recieve damage from this explosion
			end

			Power = math.max(Power - PowerSpent, 0)
		end
	end

	ACF_HE = ACF.HE
end -----------------------------------------

do -- Overpressure --------------------------
	ACF.Squishies = ACF.Squishies or {}

	local Squishies = ACF.Squishies

	-- InVehicle and GetVehicle are only for players, we have NPCs too!
	local function GetVehicle(Entity)
		if not IsValid(Entity) then return end

		local Parent = Entity:GetParent()

		if not Parent:IsVehicle() then return end

		return Parent
	end

	local function CanSee(Target, Data)
		local R = ACF.TraceF(Data)

		return R.Entity == Target or not R.Hit or R.Entity == GetVehicle(Target)
	end

	hook.Add("PlayerSpawnedNPC", "ACF Squishies", function(_, Ent)
		Squishies[Ent] = true
	end)

	hook.Add("OnNPCKilled", "ACF Squishies", function(Ent)
		Squishies[Ent] = nil
	end)

	hook.Add("PlayerSpawn", "ACF Squishies", function(Ent)
		Squishies[Ent] = true
	end)

	hook.Add("PostPlayerDeath", "ACF Squishies", function(Ent)
		Squishies[Ent] = nil
	end)

	hook.Add("EntityRemoved", "ACF Squishies", function(Ent)
		Squishies[Ent] = nil
	end)

	function ACF.Overpressure(Origin, Energy, Inflictor, Source, Forward, Angle)
		local Radius = Energy ^ 0.33 * 0.025 * 39.37 -- Radius in meters (Completely arbitrary stuff, scaled to have 120s have a radius of about 20m)
		local Data = { start = Origin, endpos = true, mask = MASK_SHOT }

		if Source then -- Filter out guns
			if Source.BarrelFilter then
				Data.filter = {}

				for K, V in pairs(Source.BarrelFilter) do Data.filter[K] = V end -- Quick copy of gun barrel filter
			else
				Data.filter = { Source }
			end
		end

		util.ScreenShake(Origin, Energy, 1, 0.25, Radius * 3 * 39.37 )

		if Forward and Angle then -- Blast direction and angle are specified
			Angle = math.rad(Angle * 0.5) -- Convert deg to rads

			for V in pairs(Squishies) do
				local Position = V:EyePos()

				if math.acos(Forward:Dot((Position - Origin):GetNormalized())) < Angle then
					local D = Position:Distance(Origin)

					if D / 39.37 <= Radius then

						Data.endpos = Position + VectorRand() * 5

						if CanSee(V, Data) then
							local Damage = Energy * 175000 * (1 / D^3)

							V:TakeDamage(Damage, Inflictor, Source)
						end
					end
				end
			end
		else -- Spherical blast
			for V in pairs(Squishies) do
				local Position = V:EyePos()

				if CanSee(Origin, V) then
					local D = Position:Distance(Origin)

					if D / 39.37 <= Radius then

						Data.endpos = Position + VectorRand() * 5

						if CanSee(V, Data) then
							local Damage = Energy * 150000 * (1 / D^3)

							V:TakeDamage(Damage, Inflictor, Source)
						end
					end
				end
			end
		end
	end
end -----------------------------------------

do -- Deal Damage ---------------------------
	local Network = ACF.Networking

	local function CalcDamage(Bullet, Trace, Volume)
		print(Bullet.Flight)
		local Angle   = ACF.GetHitAngle(Trace, Bullet.Flight)
		local Area    = Bullet.ProjArea
		local HitRes  = {}

		local Caliber        = Bullet.Diameter * 10
		local BaseArmor      = Trace.Entity.ACF.Armour
		local SlopeFactor    = BaseArmor / Caliber
		local EffectiveArmor = BaseArmor / math.abs(math.cos(math.rad(Angle)) ^ SlopeFactor)
		local MaxPenetration = Bullet:GetPenetration() --RHA Penetration

		if MaxPenetration > EffectiveArmor then
			HitRes.Damage   = isnumber(Volume) and Volume or Area -- Inflicted Damage
			HitRes.Overkill = MaxPenetration - EffectiveArmor -- Remaining penetration
			HitRes.Loss     = EffectiveArmor / MaxPenetration -- Energy loss in percents
		else
			-- Projectile did not penetrate the armor
			HitRes.Damage   = isnumber(Volume) and Volume or (MaxPenetration / EffectiveArmor) ^ 2 * Area
			HitRes.Overkill = 0
			HitRes.Loss     = 1
		end

		debugoverlay.Text(Trace.HitPos, math.Round(HitRes.Damage, 1), 5)
		return HitRes
	end

	local function SquishyDamage(Bullet, Trace, Volume)
		local Entity = Trace.Entity
		local Bone   = Trace.HitGroup
		local Armor  = Entity.ACF.Armour
		local Size   = Entity:BoundingRadius()
		local Mass   = Entity:GetPhysicsObject():GetMass()
		local HitRes = {}
		local Damage = 0

		if Bone then
			--This means we hit the head
			if Bone == 1 then
				Entity.ACF.Armour = Mass * 0.02 --Set the skull thickness as a percentage of Squishy weight, this gives us 2mm for a player, about 22mm for an Antlion Guard. Seems about right
				HitRes = CalcDamage(Bullet, Trace, Volume) --This is hard bone, so still sensitive to impact angle
				Damage = HitRes.Damage * 20

				--If we manage to penetrate the skull, then MASSIVE DAMAGE
				if HitRes.Overkill > 0 then
					Entity.ACF.Armour = Size * 0.25 * 0.01 --A quarter the bounding radius seems about right for most critters head size
					HitRes = CalcDamage(Bullet, Trace, Volume)
					Damage = Damage + HitRes.Damage * 100
				end

				Entity.ACF.Armour = Mass * 0.065 --Then to check if we can get out of the other side, 2x skull + 1x brains
				HitRes = CalcDamage(Bullet, Trace, Volume)
				Damage = Damage + HitRes.Damage * 20
			elseif Bone == 0 or Bone == 2 or Bone == 3 then
				--This means we hit the torso. We are assuming body armour/tough exoskeleton/zombie don't give fuck here, so it's tough
				Entity.ACF.Armour = Mass * 0.08 --Set the armour thickness as a percentage of Squishy weight, this gives us 8mm for a player, about 90mm for an Antlion Guard. Seems about right
				HitRes = CalcDamage(Bullet, Trace, Volume) --Armour plate,, so sensitive to impact angle
				Damage = HitRes.Damage * 5

				if HitRes.Overkill > 0 then
					Entity.ACF.Armour = Size * 0.5 * 0.02 --Half the bounding radius seems about right for most critters torso size
					HitRes = CalcDamage(Bullet, Trace, Volume)
					Damage = Damage + HitRes.Damage * 50 --If we penetrate the armour then we get into the important bits inside, so DAMAGE
				end

				Entity.ACF.Armour = Mass * 0.185 --Then to check if we can get out of the other side, 2x armour + 1x guts
				HitRes = CalcDamage(Bullet, Trace, Volume)
			elseif Bone == 4 or Bone == 5 then
				--This means we hit an arm or appendage, so ormal damage, no armour
				Entity.ACF.Armour = Size * 0.2 * 0.02 --A fitht the bounding radius seems about right for most critters appendages
				HitRes = CalcDamage(Bullet, Trace, Volume) --This is flesh, angle doesn't matter
				Damage = HitRes.Damage * 30 --Limbs are somewhat less important
			elseif Bone == 6 or Bone == 7 then
				Entity.ACF.Armour = Size * 0.2 * 0.02 --A fitht the bounding radius seems about right for most critters appendages
				HitRes = CalcDamage(Bullet, Trace, Volume) --This is flesh, angle doesn't matter
				Damage = HitRes.Damage * 30 --Limbs are somewhat less important
			elseif (Bone == 10) then
				--This means we hit a backpack or something
				Entity.ACF.Armour = Size * 0.1 * 0.02 --Arbitrary size, most of the gear carried is pretty small
				HitRes = CalcDamage(Bullet, Trace, Volume) --This is random junk, angle doesn't matter
				Damage = HitRes.Damage * 2 --Damage is going to be fright and shrapnel, nothing much
			else --Just in case we hit something not standard
				Entity.ACF.Armour = Size * 0.2 * 0.02
				HitRes = CalcDamage(Bullet, Trace, Volume)
				Damage = HitRes.Damage * 30
			end
		else --Just in case we hit something not standard
			Entity.ACF.Armour = Size * 0.2 * 0.02
			HitRes = CalcDamage(Bullet, Trace, Volume)
			Damage = HitRes.Damage * 10
		end

		Entity.ACF.Armour = Armor -- Restoring armor

		Entity:TakeDamage(Damage, Bullet.Owner, Bullet.Gun)

		HitRes.Kill = false

		return HitRes
	end

	local function VehicleDamage(Bullet, Trace, Volume)
		local HitRes = CalcDamage(Bullet, Trace, Volume)
		local Entity = Trace.Entity
		local Driver = Entity:GetDriver()

		if IsValid(Driver) then
			local NewTrace = table.Copy(Trace)
			NewTrace.Entity = Driver
			NewTrace.HitGroup = math.Rand(0, 7) -- Hit a random part of the driver
			SquishyDamage(Bullet, NewTrace) -- Deal direct damage to the driver
		end

		HitRes.Kill = false

		if HitRes.Damage >= Entity.ACF.Health then
			HitRes.Kill = true
		else
			Entity.ACF.Health = Entity.ACF.Health - HitRes.Damage
			Entity.ACF.Armour = Entity.ACF.Armour * (0.5 + Entity.ACF.Health / Entity.ACF.MaxHealth / 2) --Simulating the plate weakening after a hit
		end

		return HitRes
	end

	local function PropDamage(Bullet, Trace, Volume)
		local Entity = Trace.Entity
		local Health = Entity.ACF.Health
		local HitRes = CalcDamage(Bullet, Trace, Volume)

		HitRes.Kill = false

		if HitRes.Damage >= Health then
			HitRes.Kill = true
		else
			Entity.ACF.Health = Health - HitRes.Damage
			Entity.ACF.Armour = math.Clamp(Entity.ACF.MaxArmour * (0.5 + Entity.ACF.Health / Entity.ACF.MaxHealth / 2) ^ 1.7, Entity.ACF.MaxArmour * 0.25, Entity.ACF.MaxArmour) --Simulating the plate weakening after a hit

			Network.Broadcast("ACF_Damage", Entity)
		end

		return HitRes
	end

	ACF.PropDamage = PropDamage

	function ACF.Damage(Bullet, Trace, Volume)
		local Entity = Trace.Entity
		local Type   = ACF.Check(Entity)

		if HookRun("ACF_BulletDamage", Bullet, Trace) == false or Type == false then
			return { -- No damage
				Damage = 0,
				Overkill = 0,
				Loss = 0,
				Kill = false
			}
		end

		if Entity.ACF_OnDamage then -- Use special damage function if target entity has one
			return Entity:ACF_OnDamage(Bullet, Trace, Volume)
		elseif Type == "Prop" then
			return PropDamage(Bullet, Trace, Volume)
		elseif Type == "Vehicle" then
			return VehicleDamage(Bullet, Trace, Volume)
		elseif Type == "Squishy" then
			return SquishyDamage(Bullet, Trace, Volume)
		end
	end

	ACF_Damage = ACF.Damage

	hook.Add("ACF_OnPlayerLoaded", "ACF Render Damage", function(Player)
		for _, Entity in ipairs(ents.GetAll()) do
			local Data = Entity.ACF

			if not Data or Data.Health == Data.MaxHealth then continue end

			Network.Send("ACF_Damage", Player, Entity)
		end
	end)

	Network.CreateSender("ACF_Damage", function(Queue, Entity)
		local Value = math.Round(Entity.ACF.Health / Entity.ACF.MaxHealth, 2)

		if Value == 0 then return end
		if Value ~= Value then return end

		Queue[Entity:EntIndex()] = Value
	end)
end -----------------------------------------

do -- Remove Props ------------------------------
	util.AddNetworkString("ACF_Debris")

	local ValidDebris = ACF.ValidDebris
	local ChildDebris = ACF.ChildDebris
	local Queue       = {}

	local function SendQueue()
		for Entity, Data in pairs(Queue) do
			local JSON = util.TableToJSON(Data)

			net.Start("ACF_Debris")
				net.WriteString(JSON)
			net.SendPVS(Data.Position)

			Queue[Entity] = nil
		end
	end

	local function DebrisNetter(Entity, Normal, Power, CanGib, Ignite)
		if not ACF.GetServerBool("CreateDebris") then return end
		if Queue[Entity] then return end

		local Current = Entity:GetColor()
		local New     = Vector(Current.r, Current.g, Current.b) * math.Rand(0.3, 0.6)

		if not next(Queue) then
			timer.Create("ACF_DebrisQueue", 0, 1, SendQueue)
		end

		Queue[Entity] = {
			Position = Entity:GetPos(),
			Angles   = Entity:GetAngles(),
			Material = Entity:GetMaterial(),
			Model    = Entity:GetModel(),
			Color    = Color(New.x, New.y, New.z, Current.a),
			Normal   = Normal,
			Power    = Power,
			CanGib   = CanGib or nil,
			Ignite   = Ignite or nil,
		}
	end

	function ACF.KillChildProps(Entity, BlastPos, Energy)
		local Explosives = {}
		local Children 	 = ACF_GetAllChildren(Entity)
		local Count		 = 0

		-- do an initial processing pass on children, separating out explodey things to handle last
		for Ent in pairs(Children) do
			Ent.ACF_Killed = true -- mark that it's already processed

			if not ValidDebris[Ent:GetClass()] then
				Children[Ent] = nil -- ignoring stuff like holos, wiremod components, etc.
			else
				Ent:SetParent()

				if Ent.IsExplosive and not Ent.Exploding then
					Explosives[Ent] = true
					Children[Ent] 	= nil
				else
					Count = Count + 1
				end
			end
		end

		-- HE kill the children of this ent, instead of disappearing them by removing parent
		if next(Children) then
			local DebrisChance 	= math.Clamp(ChildDebris / Count, 0, 1)
			local Power 		= Energy / math.min(Count,3)

			for Ent in pairs( Children ) do
				if math.random() < DebrisChance then
					ACF.HEKill(Ent, (Ent:GetPos() - BlastPos):GetNormalized(), Power)
				else
					constraint.RemoveAll(Ent)
					Ent:Remove()
				end
			end
		end

		-- explode stuff last, so we don't re-process all that junk again in a new explosion
		if next(Explosives) then
			for Ent in pairs(Explosives) do
				Ent.Inflictor = Entity.Inflictor

				Ent:Detonate()
			end
		end
	end

	function ACF.HEKill(Entity, Normal, Energy, BlastPos) -- blast pos is an optional world-pos input for flinging away children props more realistically
		-- if it hasn't been processed yet, check for children
		if not Entity.ACF_Killed then
			ACF.KillChildProps(Entity, BlastPos or Entity:GetPos(), Energy)
		end

		local Radius = Entity:BoundingRadius()
		local Debris = {}

		DebrisNetter(Entity, Normal, Energy, false, true)

		if ACF.GetServerBool("CreateFireballs") then
			local Fireballs = math.Clamp(Radius * 0.01, 1, math.max(10 * ACF.GetServerNumber("FireballMult", 1), 1))
			local Min, Max = Entity:OBBMins(), Entity:OBBMaxs()
			local Pos = Entity:GetPos()
			local Ang = Entity:GetAngles()

			for _ = 1, Fireballs do -- should we base this on prop volume?
				local Fireball = ents.Create("acf_debris")

				if not IsValid(Fireball) then break end -- we probably hit edict limit, stop looping

				local Lifetime = math.Rand(5, 15)
				local Offset   = ACF.RandomVector(Min, Max)

				Offset:Rotate(Ang)

				Fireball:SetPos(Pos + Offset)
				Fireball:Spawn()
				Fireball:Ignite(Lifetime)

				timer.Simple(Lifetime, function()
					if not IsValid(Fireball) then return end

					Fireball:Remove()
				end)

				local Phys = Fireball:GetPhysicsObject()

				if IsValid(Phys) then
					Phys:ApplyForceOffset(Normal * Energy / Fireballs, Fireball:GetPos() + VectorRand())
				end

				Debris[Fireball] = true
			end
		end

		constraint.RemoveAll(Entity)
		Entity:Remove()

		return Debris
	end

	function ACF.APKill(Entity, Normal, Power)
		ACF.KillChildProps(Entity, Entity:GetPos(), Power) -- kill the children of this ent, instead of disappearing them from removing parent

		DebrisNetter(Entity, Normal, Power, true, false)

		constraint.RemoveAll(Entity)
		Entity:Remove()
	end

	ACF_KillChildProps = ACF.KillChildProps
	ACF_HEKill = ACF.HEKill
	ACF_APKill = ACF.APKill
end

do -- ACF.HE
	local DEBUG_TIME  = 30
	local DEBUG_RED   = Color(255, 0, 0, 15)
	local DEBUG_GREEN = Color(0, 255, 0)

	local min   = math.min
	local max   = math.max
	local floor = math.floor
	local round = math.Round

	local function isValidTarget(ent)
		if not IsValid(ent) then return false end
		if ent.Exploding then return false end
		if not ACF.Check(ent) then return false end
		if (ent:IsPlayer() or ent:IsNPC()) and ent:Health() <= 0 then return false end

		return true
	end

	local function getRandomPos(Entity)
		if IsChar then
			local Mins, Maxs = Entity:OBBMins() * 0.65, Entity:OBBMaxs() * 0.65 -- Scale down the "hitbox" since most of the character is in the middle
			local Rand		 = Vector(math.Rand(Mins[1], Maxs[1]), math.Rand(Mins[2], Maxs[2]), math.Rand(Mins[3], Maxs[3]))

			return Entity:LocalToWorld(Rand)
		else
			local Mesh = Entity:GetPhysicsObject():GetMesh()

			if not Mesh then -- Is Make-Sphericaled
				local Mins, Maxs = Entity:OBBMins(), Entity:OBBMaxs()
				local Rand		 = Vector(math.Rand(Mins[1], Maxs[1]), math.Rand(Mins[2], Maxs[2]), math.Rand(Mins[3], Maxs[3]))

				return Entity:LocalToWorld(Rand:GetNormalized() * math.Rand(1, Entity:BoundingRadius() * 0.5)) -- Attempt to a random point in the sphere
			else
				local Rand = math.random(3, #Mesh / 3) * 3
				local P    = Vector(0, 0, 0)

				for I = Rand - 2, Rand do P = P + Mesh[I].pos end

				return Entity:LocalToWorld(P / 3) -- Attempt to hit a point on a face of the mesh
			end
		end
	end

	local trace     = ACF.Trace
	local traceRes  = {}
	local traceData = {mask = MASK_SOLID, output = traceRes}

	local function doTrace(originalTarget)
		trace(traceData)

		if traceRes.HitNonWorld then
			if traceRes.Entity ~= originalTarget and not isValidTarget(traceRes.Entity) then
				traceData.filter[#traceData.filter + 1] = trace.Entity

				return doTrace()
			end

			return traceRes.Entity
		end
	end

	local findInSphere = ents.FindInSphere
	local doDamage     = ACF.Damage
	local doShove      = ACF.KEShove
	local doAPKill     = ACF.APKill
	local doHEKill     = ACF.HEKill
	local fakeBullet   = {
		IsFrag   = true,
		Owner    = true,
		Gun      = true,
		Caliber  = true,
		Diameter = true,
		ProjArea = true,
		ProjMass = true,
		Flight   = true,
		Speed    = true,
		DragCoef = true,
		GetPenetration = function(self) return self.penetration end
	}

	function ACF.HE(origin, explosiveMass, fragMass, inflictor, filter, gun)
		print(origin, inflictor, filter, gun)

		local totalPower = explosiveMass * ACF.HEPower -- KJ

		local blastRatio       = explosiveMass / fragMass
		local blastRadius      = explosiveMass ^ 0.33 * 8 * 39.37 -- in
		local blastSurfaceArea = 4 * 3.1415 * blastRadius ^ 2 -- in^2
		local blastPower       = totalPower * blastRatio -- KJ

		local fragCount   = max(floor(blastRatio * ACF.HEFrag), 2) -- minimum of 2 fragments
		local fragPower   = totalPower - blastPower -- KJ
		local fragMass    = fragMass / fragCount -- kg
		local fragSpeed   = (2 * (fragPower * 1000 / fragCount) * fragMass) ^ 0.5 -- m/s
		local fragVolume  = fragMass / 0.00794 -- g/mm^3
		local fragCaliber = (6 * fragVolume / 3.1415) ^ (1/3) -- (3 * fragVolume / 4 * 3.1415) * 1/3 -- mm
		local fragArea    = 1/4 * 3.1415 * fragCaliber^2
		local fragPen     = ACF.Penetration(fragSpeed, fragMass, fragCaliber) -- mm
		local fragDrag    = fragArea * 0.0002 / fragMass

		fakeBullet.Owner    = inflictor or gun
		fakeBullet.Caliber  = fragCaliber
		fakeBullet.Diameter = fragCaliber -- this might not be correct
		fakeBullet.ProjArea = fragArea
		fakeBullet.ProjMass = fragMass
		fakeBullet.Speed    = fragSpeed / 39.37 -- m/s
		fakeBullet.DragCoef = fragDrag

		local filter       = filter or {}
		local filterCount  = #filter

		traceData.start  = origin
		traceData.filter = filter

		local bogies              = findInSphere(origin, blastRadius)
		local bogieCount          = #bogies
		local damaged             = {} -- entities that have been damaged and cannot be damaged again
		local penetratedSomething = true

		do -- debug prints
			print("HE")
			print("  Total Power: " .. round(totalPower / 1000, 1) .. " MJ")
			--print("  Blast Ratio: " .. round(blastRatio, 2))
			print("  Blast Radius: " .. round(blastRadius / 39.37) .. " m")
			print("  Blast Energy: " .. round(blastPower, 1) .. " KJ")
			--print("  Blast Surface Area: " .. round(blastSurfaceArea) .. " in^2")
			print("")
			print("  Frag Energy: " .. round(fragPower, 1) .. " KJ")
			print("  Frag Count: " .. fragCount)
			--print("  Frag Mass: " .. round(fragMass * 1000, 2) .. " g")
			--print("  Frag Speed: " .. round(fragSpeed) .. " m/s")
			--print("  Frag Volume: " .. round(fragVolume, 2) .. " mm^3")
			--print("  Frag Caliber: " .. round(fragCaliber, 2) .. " mm")
			print("  Frag Penetration: " .. round(fragPen, 2) .. " mm")

			debugoverlay.Sphere(origin, blastRadius, DEBUG_TIME, Color(255, 255, 255, 5))
		end

		while penetratedSomething do
			penetratedSomething = false

			for index, bogie in pairs(bogies) do
				if not isValidTarget(bogie) then
					bogies[index]       = nil
					filterCount         = filterCount + 1
					filter[filterCount] = bogie

					continue
				end

				-- Trace towards the bogie
				-- We'll target any entity that the trace hits so long as it's a valid target and has not been damaged already
				traceData.endpos = getRandomPos(bogie, bogie:IsPlayer() or bogie:IsNPC())

				local ent = doTrace(bogie)

				if ent and not damaged[ent] then
					debugoverlay.Line(origin, traceRes.HitPos, DEBUG_TIME, Color(255, 255, 255, 5))
					print("Target: " .. tostring(ent))

					damaged[ent] = true

					if ent == bogie then bogies[index] = nil end

					-- Project the targets shadow onto the blast sphere
					local targetPos     = ent:GetPos()
					local displacement  = targetPos - origin
					local distance      = displacement:Length()
					local sphereAtRange = 4 * 3.1415 * distance^2
					local shadowArea    = ent.ACF.Area / sphereAtRange * blastSurfaceArea

					-- How much power goes to the target
					local areaFraction   = min(shadowArea / blastSurfaceArea, 0.5)
					local powerDelivered = blastPower * areaFraction

					-- Fragmentation damage
					local fragHits = round(fragCount * areaFraction)
					local fragRes

					if fragHits > 0 then
						print("    Frags hitting " .. fragHits)
						--print("    Sphere at range: " .. round(sphereAtRange))
						--print("    Area Fraction: " .. round(areaFraction, 2))
						--print("    Power delivered: " .. round(powerDelivered, 2))
						print("")

						fakeBullet.ProjArea    = fragArea * fragHits
						fakeBullet.Mass        = fragMass * fragHits
						fakeBullet.Flight      = displacement:GetNormalized() * fragSpeed
						fakeBullet.penetration = fragPen * (1 - (distance / blastRadius) ^ 2)

						fragRes = doDamage(fakeBullet, traceRes)

						--Print(fragRes)
					end

					-- Blast damage
					local blastRes

					-- target has not been killed by frag damage and we are delivering at least 0.5 KJ to the target
					-- ~0.5 KJ is a world-class punch or handgun shot
					if not (fragRes and fragRes.Kill) and powerDelivered > 0.5 then
						fakeBullet.ProjArea = ent.ACF.Area
					end

					-- Push on it
					doShove(ent, origin, displacement, powerDelivered)

					-- Handle killed or penetrated targets
					local targetKilled     = blastRes and blastRes.Kill or fragRes and fragRes.Kill
					local targetPenetrated = blastRes and blastRes.Overkill > 0 or fragRes and fragRes.Overkill > 0

					if targetKilled or targetPenetrated then
						print("    Target " .. (targetKilled and "killed" or "penetrated"))
						debugoverlay.BoxAngles(ent:GetPos(), nt:OBBMins(), ent:OBBMaxs(), ent:GetAngles(), DEBUG_TIME, DEBUG_RED)

						penetratedSomething = true
						filterCount         = filterCount + 1
						filter[filterCount] = ent

						if targetKilled then
							if fragRes and fragRes.Kill then
								doAPKill(ent, displacement, powerDelivered)
							else
								local debris = doHEKill(ent, displacement, powerDelivered, origin)

								for fireball in pairs(debris) do
									filterCount         = filterCount + 1
									filter[filterCount] = fireball
								end
							end
						end
					end
				end
			end
		end

		local effect = EffectData()
			effect:SetOrigin(origin)
			effect:SetNormal(Vector(0, 0, 1))
			effect:SetScale(blastRadius)
			effect:SetRadius(blastRadius)

		util.Effect("ACF_Explosion", effect)
	end

	local rounds = {
		["M107 155mm HE"] = {
			mass = 43.2, -- kg
			filler = 6.86, -- tnt
		},
		--[[["40mm L/60 Bofors HE-T"] = {
			mass = 0.93,
			filler = 0.092,
		},
		["M67 Hand Grenade"] = {
			mass = 0.4,
			filler = 0.18,
		}]]--
	}

	function ACF.testHE()
		for name, data in pairs(rounds) do
			print("Testing " .. name)
			ACF.HE(eye().HitPos, data.filler, data.mass - data.filler, me(), {me()}, me())
		end
	end
end