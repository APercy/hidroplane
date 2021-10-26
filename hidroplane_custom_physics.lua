
local min = math.min
local abs = math.abs
--local deg = math.deg

function hidroplane.physics(self)
    local friction = 0.99
	local vel=self.object:get_velocity()
	
	-- bounciness
	if self.springiness and self.springiness > 0 then
		local vnew = vector.new(vel)
		
		if not self.collided then						-- ugly workaround for inconsistent collisions
			for _,k in ipairs({'y','z','x'}) do
				if vel[k]==0 and abs(self.lastvelocity[k])> 0.1 then
					vnew[k]=-self.lastvelocity[k]*self.springiness
				end
			end
		end
		
		if not vector.equals(vel,vnew) then
			self.collided = true
		else
			if self.collided then
				vnew = vector.new(self.lastvelocity)
			end
			self.collided = false
		end
		
		self.object:set_velocity(vnew)
	end
	
	--buoyancy
	local surface = nil
	local surfnodename = nil
	local spos = mobkit.get_stand_pos(self)
	spos.y = spos.y+0.01
	-- get surface height
	local snodepos = mobkit.get_node_pos(spos)
	local surfnode = mobkit.nodeatpos(spos)
	while surfnode and (surfnode.drawtype == 'liquid' or surfnode.drawtype == 'flowingliquid') do
		surfnodename = surfnode.name
		surface = snodepos.y +0.5
		if surface > spos.y+self.height then break end
		snodepos.y = snodepos.y+1
		surfnode = mobkit.nodeatpos(snodepos)
	end

    local new_velocity = nil
	self.isinliquid = surfnodename
	if surface then				-- standing in liquid
		self.isinliquid = true
        local height = self.height
		local submergence = min(surface-spos.y,height)/height
--		local balance = self.buoyancy*self.height
		local buoyacc = mobkit.gravity*(self.buoyancy-submergence)
		--[[mobkit.set_acceleration(self.object,
			{x=-vel.x*self.water_drag,y=buoyacc-vel.y*abs(vel.y)*0.4,z=-vel.z*self.water_drag})]]--
        local accell = {x=-vel.x*self.water_drag,y=buoyacc-vel.y*abs(vel.y)*0.2,z=-vel.z*self.water_drag}
        local v_accell = {x=-0,y=buoyacc-vel.y*abs(vel.y)*0.4,z=0}
        mobkit.set_acceleration(self.object,v_accell)
        new_velocity = vector.add(vel, vector.multiply(accell, self.dtime/8))
        --self.object:set_velocity(new_velocity)
        
	else
        mobkit.set_acceleration(self.object,{x=0,y=0,z=0})
		self.isinliquid = false
        new_velocity = vector.add(vel, {x=0,y=mobkit.gravity * self.dtime,z=0})
        --self.object:set_velocity(new_velocity)
	end

    new_velocity = vector.add(new_velocity, vector.multiply(self._last_accell, self.dtime))
		-- dumb friction
	if self.isonground and not self.isinliquid then
		self.object:set_velocity({x=new_velocity.x*friction,
								y=new_velocity.y,
								z=new_velocity.z*friction})
    else
        self.object:set_velocity(new_velocity)
	end

end
