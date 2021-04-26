dofile(minetest.get_modpath("hidroplane") .. DIR_DELIM .. "hidroplane_global_definitions.lua")

function hidroplane.get_hipotenuse_value(point1, point2)
    return math.sqrt((point1.x - point2.x) ^ 2 + (point1.y - point2.y) ^ 2 + (point1.z - point2.z) ^ 2)
end

function hidroplane.dot(v1,v2)
	return v1.x*v2.x+v1.y*v2.y+v1.z*v2.z
end

function hidroplane.sign(n)
	return n>=0 and 1 or -1
end

function hidroplane.minmax(v,m)
	return math.min(math.abs(v),m)*hidroplane.sign(v)
end

local physics_attrs = {"jump", "speed", "gravity"}
local function apply_physics_override(player, overrides)
    if player_monoids then
        for _, attr in pairs(physics_attrs) do
            if overrides[attr] then
                player_monoids[attr]:add_change(player, overrides[attr], "hangglider:glider")
            end
        end
    else
        player:set_physics_override(overrides)
    end
end

local function remove_physics_override(player, overrides)
    for _, attr in pairs(physics_attrs) do
        if overrides[attr] then
            if core.global_exists("player_monoids") then
                player_monoids[attr]:del_change(player, "hangglider:glider")
            else
                player:set_physics_override({[attr] = 1})
            end
        end
    end
end

--lift
local function pitchroll2pitchyaw(aoa,roll)
	if roll == 0.0 then return aoa,0 end 
	-- assumed vector x=0,y=0,z=1
	local p1 = math.tan(aoa)
	local y = math.cos(roll)*p1
	local x = math.sqrt(p1^2-y^2)
	local pitch = math.atan(y)
	local yaw=math.atan(x)*math.sign(roll)
	return pitch,yaw
end

function hidroplane.getLiftAccel(self, velocity, accel, longit_speed, roll, curr_pos)
    --lift calculations
    -----------------------------------------------------------
    local max_height = 15000
    
    local retval = accel
    if longit_speed > 1 then
        local angle_of_attack = math.rad(self._angle_of_attack + hidroplane.wing_angle_of_attack)
        local lift = 12
        --local acc = 0.8
        local daoa = deg(angle_of_attack)

    	--local curr_pos = self.object:get_pos()
        local curr_percent_height = (100 - ((curr_pos.y * 100) / max_height))/100 --to decrease the lift coefficient at hight altitudes

	    local rotation=self.object:get_rotation()
	    local vrot = mobkit.dir_to_rot(velocity,rotation)
	    
	    hpitch,hyaw = pitchroll2pitchyaw(angle_of_attack,roll)

	    local hrot = {x=vrot.x+hpitch,y=vrot.y-hyaw,z=roll}
	    local hdir = mobkit.rot_to_dir(hrot) --(hrot)
	    local cross = vector.cross(velocity,hdir)
	    local lift_dir = vector.normalize(vector.cross(cross,hdir))	

        local lift_coefficient = (0.24*abs(daoa)*(1/(0.025*daoa+3))^4*math.sign(angle_of_attack))
        local lift_val = (lift*(vector.length(velocity)^2)*lift_coefficient)*curr_percent_height
        --minetest.chat_send_all('lift: '.. lift_val)

        local lift_acc = vector.multiply(lift_dir,lift_val)
        --lift_acc=vector.add(vector.multiply(minetest.yaw_to_dir(rotation.y),acc),lift_acc)

        retval = vector.add(retval,lift_acc)
    end
    -----------------------------------------------------------
    -- end lift
    return retval
end


function hidroplane.get_gauge_angle(value, initial_angle)
    initial_angle = initial_angle or 90
    local angle = value * 18
    angle = angle - initial_angle
    angle = angle * -1
	return angle
end

-- attach player
function hidroplane.attach(self, player)
    local name = player:get_player_name()
    self.driver_name = name

    -- attach the driver
    player:set_attach(self.pilot_seat_base, "", {x = 0, y = 0, z = 0}, {x = 0, y = 0, z = 0})
    player:set_eye_offset({x = 0, y = -4, z = 2}, {x = 0, y = 1, z = -30})
    player_api.player_attached[name] = true
    -- make the driver sit
    minetest.after(0.2, function()
        local player = minetest.get_player_by_name(name)
        if player then
	        player_api.set_animation(player, "sit")
            --apply_physics_override(player, {speed=0,gravity=0,jump=0})
        end
    end)
end

-- attach passenger
function hidroplane.attach_pax(self, player)
    local name = player:get_player_name()
    self._passenger = name

    -- attach the driver
    player:set_attach(self.passenger_seat_base, "", {x = 0, y = 0, z = 0}, {x = 0, y = 0, z = 0})
    player:set_eye_offset({x = 0, y = -2.5, z = 2}, {x = 0, y = 3, z = -30})
    player_api.player_attached[name] = true
    -- make the driver sit
    minetest.after(0.2, function()
        local player = minetest.get_player_by_name(name)
        if player then
	        player_api.set_animation(player, "sit")
            --apply_physics_override(player, {speed=0,gravity=0,jump=0})
        end
    end)
end

function hidroplane.dettachPlayer(self, player)
    local name = self.driver_name
    hidroplane.setText(self)

    self._engine_running = false

    -- driver clicked the object => driver gets off the vehicle
    self.driver_name = nil
    -- sound and animation
    if self.sound_handle then
        minetest.sound_stop(self.sound_handle)
        self.sound_handle = nil
    end
    
    self.engine:set_animation_frame_speed(0)

    -- detach the player
    player:set_detach()
    player_api.player_attached[name] = nil
    player:set_eye_offset({x=0,y=0,z=0},{x=0,y=0,z=0})
    player_api.set_animation(player, "stand")
    self.driver = nil
    --remove_physics_override(player, {speed=1,gravity=1,jump=1})
end

function hidroplane.dettach_pax(self, player)
    local name = self._passenger

    -- passenger clicked the object => driver gets off the vehicle
    self._passenger = nil

    -- detach the player
    player:set_detach()
    player_api.player_attached[name] = nil
    player_api.set_animation(player, "stand")
    player:set_eye_offset({x=0,y=0,z=0},{x=0,y=0,z=0})
    --remove_physics_override(player, {speed=1,gravity=1,jump=1})
end

function hidroplane.checkAttach(self, player)
    if player then
        local player_attach = player:get_attach()
        if player_attach then
            if player_attach == self.pilot_seat_base then
                return true
            end
        end
    end
    return false
end

--painting
function hidroplane.paint(self, object, colstr, search_string)
    if colstr then
        self._color = colstr
        local entity = object:get_luaentity()
        local l_textures = entity.initial_properties.textures
        for _, texture in ipairs(l_textures) do
            local i,indx = texture:find(search_string)
            if indx then
                l_textures[_] = search_string .."^[multiply:".. colstr
            end
        end
        object:set_properties({textures=l_textures})
    end
end

-- destroy the boat
function hidroplane.destroy(self)
    if self.sound_handle then
        minetest.sound_stop(self.sound_handle)
        self.sound_handle = nil
    end

    if self._passenger then
        -- detach the passenger
        local passenger = minetest.get_player_by_name(self._passenger)
        if passenger then 
            passenger:set_detach()
            passenger:set_eye_offset({x = 0, y = 0, z = 0}, {x = 0, y = 0, z = 0})
            player_api.player_attached[self._passenger] = nil
            -- player should stand again
            player_api.set_animation(passenger, "stand")
        end
        self._passenger = nil
    end

    if self.driver_name then
        -- detach the driver
        local player = minetest.get_player_by_name(self.driver_name)
        player:set_detach()
        player:set_eye_offset({x = 0, y = 0, z = 0}, {x = 0, y = 0, z = 0})
        player_api.player_attached[self.driver_name] = nil
        -- player should stand again
        player_api.set_animation(player, "stand")
        self.driver_name = nil
    end

    local pos = self.object:get_pos()
    if self.fuel_gauge then self.fuel_gauge:remove() end
    if self.power_gauge then self.power_gauge:remove() end
    if self.climb_gauge then self.climb_gauge:remove() end
    if self.speed_gauge then self.speed_gauge:remove() end
    if self.engine then self.engine:remove() end
    --if self.wheel then self.wheel:remove() end
    if self.pilot_seat_base then self.pilot_seat_base:remove() end
    if self.passenger_seat_base then self.passenger_seat_base:remove() end

    if self.wheels then self.wheels:remove() end
    if self.f_wheels then self.f_wheels:remove() end

    if self.elevator then self.elevator:remove() end
    if self.rudder then self.rudder:remove() end
    if self.right_aileron then self.right_aileron:remove() end
    if self.left_aileron then self.left_aileron:remove() end

    self.object:remove()

    pos.y=pos.y+2
    minetest.add_item({x=pos.x+math.random()-0.5,y=pos.y,z=pos.z+math.random()-0.5},'hidroplane:wings')

    for i=1,5 do
	    minetest.add_item({x=pos.x+math.random()-0.5,y=pos.y,z=pos.z+math.random()-0.5},'default:tin_ingot')
    end

    for i=1,6 do
	    minetest.add_item({x=pos.x+math.random()-0.5,y=pos.y,z=pos.z+math.random()-0.5},'default:steel_ingot')
    end

    for i=1,2 do
	    minetest.add_item({x=pos.x+math.random()-0.5,y=pos.y,z=pos.z+math.random()-0.5},'wool:white')
    end

    for i=1,6 do
	    minetest.add_item({x=pos.x+math.random()-0.5,y=pos.y,z=pos.z+math.random()-0.5},'default:mese_crystal')
        minetest.add_item({x=pos.x+math.random()-0.5,y=pos.y,z=pos.z+math.random()-0.5},'default:diamond')
    end

    --minetest.add_item({x=pos.x+math.random()-0.5,y=pos.y,z=pos.z+math.random()-0.5},'hidroplane:hidro')
end

function hidroplane.check_node_below(obj)
    local pos_below = obj:get_pos()
    if pos_below then
        pos_below.y = pos_below.y - 2.5
        local node_below = minetest.get_node(pos_below).name
        local nodedef = minetest.registered_nodes[node_below]
        local touching_ground = not nodedef or -- unknown nodes are solid
		        nodedef.walkable or false
        local liquid_below = not touching_ground and nodedef.liquidtype ~= "none"
        return touching_ground, liquid_below
    end
    return nil, nil
end

function hidroplane.setText(self)
    local properties = self.object:get_properties()
    local formatted = string.format(
       "%.2f", self.hp_max
    )
    if properties then
        properties.infotext = "Nice hydroplane of " .. self.owner .. ". Current hp: " .. formatted
        self.object:set_properties(properties)
    end
end

function hidroplane.testImpact(self, velocity, position)
    collision = false
    if self._last_vel == nil then return end
    local impact = abs(hidroplane.get_hipotenuse_value(velocity, self._last_vel))
    --minetest.chat_send_all('impact: '.. impact .. ' - hp: ' .. self.hp_max)
    if impact > 2 then
        --minetest.chat_send_all('impact: '.. impact .. ' - hp: ' .. self.hp_max)
        local p = position --self.object:get_pos()
		local nodeu = mobkit.nodeatpos(mobkit.pos_shift(p,{y=1}))
		local noded = mobkit.nodeatpos(mobkit.pos_shift(p,{y=-1}))
        local nodel = mobkit.nodeatpos(mobkit.pos_shift(p,{x=-1}))
        local noder = mobkit.nodeatpos(mobkit.pos_shift(p,{x=1}))
        local nodef = mobkit.nodeatpos(mobkit.pos_shift(p,{z=1}))
        local nodeb = mobkit.nodeatpos(mobkit.pos_shift(p,{z=-1}))
		if (nodeu and nodeu.drawtype ~= 'airlike') or
            (noded and noded.drawtype ~= 'airlike') or
            (nodef and nodef.drawtype ~= 'airlike') or 
            (nodeb and nodeb.drawtype ~= 'airlike') or 
            (noder and noder.drawtype ~= 'airlike') or 
            (nodel and nodel.drawtype ~= 'airlike') then
			collision = true
		end
        local test = "nao"
        if collision then test = "sim" end
        --minetest.chat_send_all('- impact: '.. impact .. ' - draw: ' .. noded.drawtype .. ' - col: ' .. test)
        --[[if collision then 
            minetest.chat_send_all('- impact: '.. impact .. ' - hp: ' .. self.hp_max)
        end]]--
    end
    if collision then
        local damage = impact / 2
        self.hp_max = self.hp_max - damage --subtract the impact value directly to hp meter
        local curr_pos = self.object:get_pos()

        minetest.sound_play("hidroplane_collision", {
            --to_player = self.driver_name,
            object = self.object,
            max_hear_distance = 15,
            gain = 1.0,
            fade = 0.0,
            pitch = 1.0,
        }, true)

        if self.driver_name then
            local player_name = self.driver_name
            hidroplane.setText(self)

            --minetest.chat_send_all('damage: '.. damage .. ' - hp: ' .. self.hp_max)
            if self.hp_max < 0 then --if acumulated damage is greater than 50, adieu
                hidroplane.destroy(self)   
            end

            local player = minetest.get_player_by_name(player_name)
            if player then
		        if player:get_hp() > 0 then
			        player:set_hp(player:get_hp()-(damage/2))
		        end
            end
            if self._passenger ~= nil then
                local passenger = minetest.get_player_by_name(self._passenger)
                if passenger then
		            if passenger:get_hp() > 0 then
			            passenger:set_hp(passenger:get_hp()-(damage/2))
		            end
                end
            end
        end

    end
end

function hidroplane.checkattachBug(self)
    -- for some engine error the player can be detached from the submarine, so lets set him attached again
    local can_stop = true
    if self.owner and self.driver_name then
        -- attach the driver again
        local player = minetest.get_player_by_name(self.owner)
        if player then
		    if player:get_hp() > 0 then
                hidroplane.attach(self, player)
                can_stop = false
            else
                hidroplane.dettachPlayer(self, player)
		    end
        end
    end

    if can_stop then
        --detach player
        if self.sound_handle ~= nil then
            minetest.sound_stop(self.sound_handle)
            self.sound_handle = nil
        end
    end
end

function hidroplane.check_is_under_water(obj)
	local pos_up = obj:get_pos()
	pos_up.y = pos_up.y + 0.1
	local node_up = minetest.get_node(pos_up).name
	local nodedef = minetest.registered_nodes[node_up]
	local liquid_up = nodedef.liquidtype ~= "none"
	return liquid_up
end

function hidroplane.lang_gear_operate(self, curr_pos)
    local pos = curr_pos
    pos.y = pos.y - 4
    local ray = minetest.raycast(curr_pos, pos, true, true)
    local thing = ray:next()
    if thing == nil then
        self._land_retracted = true
        --retracts landing gear
        self.wheels:set_attach(self.object,'',{x=0,y=2.5,z=0},{x=0,y=0,z=0})
        self.f_wheels:set_attach(self.object,'',{x=0,y=-14.2,z=13.5},{x=0,y=0,z=0})
    else
        while thing do
	        if thing.type == "node" then
			    local node_name = minetest.get_node(thing.under).name
			    local drawtype = minetest.registered_nodes[node_name]["drawtype"]
			    if drawtype == 'liquid' or drawtype == 'airlike' then
                    self._land_retracted = true
                    --retracts landing gear
                    self.wheels:set_attach(self.object,'',{x=0,y=2.5,z=0},{x=0,y=0,z=0})
                    self.f_wheels:set_attach(self.object,'',{x=0,y=-14.2,z=13.5},{x=0,y=0,z=0})
                else
                    self._land_retracted = false
                    --extends landing gear
                    self.wheels:set_attach(self.object,'',{x=0,y=0,z=0},{x=0,y=0,z=0})
                    self.f_wheels:set_attach(self.object,'',{x=0,y=-14.2,z=13.5},{x=29.4,y=0,z=0})
                end
            end
            thing = ray:next()
        end
    end
end

function hidroplane.flightstep(self)
    local player = nil
    if self.driver_name then player = minetest.get_player_by_name(self.driver_name) end
    local passenger = nil
    if self._passenger then passenger = minetest.get_player_by_name(self._passenger) end

    local accel_y = self.object:get_acceleration().y
    local rotation = self.object:get_rotation()
    local yaw = rotation.y
	local newyaw=yaw
    local pitch = rotation.x
    local newpitch = pitch
	local roll = rotation.z
	local newroll=roll

    local velocity = self.object:get_velocity()
    local hull_direction = mobkit.rot_to_dir(rotation) --minetest.yaw_to_dir(yaw)
    local nhdir = {x=hull_direction.z,y=0,z=-hull_direction.x}		-- lateral unit vector

    local longit_speed = vector.dot(velocity,hull_direction)
    self._longit_speed = longit_speed
    local longit_drag = vector.multiply(hull_direction,longit_speed*longit_speed*HIDROPLANE_LONGIT_DRAG_FACTOR*-1*hidroplane.sign(longit_speed))
	local later_speed = hidroplane.dot(velocity,nhdir)
    --minetest.chat_send_all('later_speed: '.. later_speed)
	local later_drag = vector.multiply(nhdir,later_speed*later_speed*HIDROPLANE_LATER_DRAG_FACTOR*-1*hidroplane.sign(later_speed))
    local accel = vector.add(longit_drag,later_drag)
    local stop = false

    local curr_pos = self.object:get_pos()
    self.object:set_pos(curr_pos)

    local node_bellow = mobkit.nodeatpos(mobkit.pos_shift(curr_pos,{y=-3}))
    local is_flying = true
    if node_bellow and node_bellow.drawtype ~= 'airlike' then is_flying = false end
    --if is_flying then minetest.chat_send_all('is flying') end

    local is_attached = hidroplane.checkAttach(self, player)

    --ajustar angulo de ataque
    local percentage = math.abs(((longit_speed * 100)/(hidroplane.min_speed + 5))/100)
    if percentage > 1.5 then percentage = 1.5 end
    self._angle_of_attack = self._angle_of_attack - ((self._elevator_angle / 20)*percentage)
    if self._angle_of_attack < -3 then
        self._angle_of_attack = -1
        self._elevator_angle = self._elevator_angle - 0.1
    end --limiting the negative angle]]--
    if self._angle_of_attack > 20 then
        self._angle_of_attack = 20
        self._elevator_angle = self._elevator_angle + 0.1
    end --limiting the very high climb angle due to strange behavior]]--

    -- pitch
    local speed_factor = 0
    if longit_speed > hidroplane.min_speed then speed_factor = (velocity.y * math.rad(2)) end
    newpitch = math.rad(self._angle_of_attack) + speed_factor

    -- adjust pitch at ground
    if is_flying == false then --isn't flying?
        if math.abs(longit_speed) < hidroplane.min_speed - 2 then
            local percentage = ((longit_speed * 100)/hidroplane.min_speed)/100
            if newpitch ~= 0 then
                newpitch = newpitch * percentage
            end
        end

        --animate wheels
        if self._land_retracted == false then
            self.f_wheels:set_animation_frame_speed(longit_speed * 10)
            self.wheels:set_animation_frame_speed(longit_speed * 10)
        else
            self.f_wheels:set_animation_frame_speed(0)
            self.wheels:set_animation_frame_speed(0)
        end
    else
        --stop wheels
        self.f_wheels:set_animation_frame_speed(0)
        self.wheels:set_animation_frame_speed(0)
    end
    
    -- new yaw
	if math.abs(self._rudder_angle)>5 then 
        local turn_rate = math.rad(18)
		newyaw = yaw + self.dtime*(1 - 1 / (math.abs(longit_speed) + 1)) * self._rudder_angle / 30 * turn_rate * hidroplane.sign(longit_speed)
	end

    --roll adjust
    ---------------------------------
    --if longit_speed > 0 then
	    local sdir = minetest.yaw_to_dir(newyaw)
	    local snormal = {x=sdir.z,y=0,z=-sdir.x}	-- rightside, dot is negative
	    local prsr = hidroplane.dot(snormal,nhdir)
        local rollfactor = -90
        local roll_rate = math.rad(25)
        newroll = (prsr*math.rad(rollfactor))*(later_speed) * roll_rate * hidroplane.sign(longit_speed)
        --minetest.chat_send_all('newroll: '.. newroll)
    --[[else
        local delta = 0.01
        local dest = 0
        newroll = math.min(math.abs(dest-(newroll+delta)), math.abs(dest-(newroll-delta)))*math.abs(newroll)/newroll*math.abs(delta)/delta+dest
    end]]--
    ---------------------------------
    -- end roll

    --accell calculation
    --control
	if not is_attached then
        -- for some engine error the player can be detached from the machine, so lets set him attached again
        hidroplane.checkattachBug(self)
    else
        accel, stop = hidroplane.control(self, self.dtime, hull_direction, longit_speed, longit_drag, later_speed, later_drag, accel, player, is_flying)
	end
    --end accell

    if accel == nil then accel = {x=0,y=0,z=0} end

    --lift calculation
    accel.y = accel_y

	if self.isinliquid then
        local bob = hidroplane.minmax(hidroplane.dot(accel,hull_direction),0.4)	-- vertical bobbing
        accel.y = accel.y + bob
        newpitch = newpitch + (velocity.y * math.rad(6))
    end

    local new_accel = accel
    if longit_speed > 2 then
        new_accel = hidroplane.getLiftAccel(self, velocity, new_accel, longit_speed, roll, curr_pos)
    end
    -- end lift

    if stop ~= true then
        self.object:set_acceleration(new_accel)
    elseif stop == false then
        self.object:set_velocity({x=0,y=0,z=0})
    end

    --self.object:get_luaentity() --hack way to fix jitter on climb

    --adjust climb indicator
    local climb_rate = velocity.y * 1.5
    if climb_rate > 5 then climb_rate = 5 end
    if climb_rate < -5 then
        climb_rate = -5
    end

    --is an stall, force a recover
    if self._angle_of_attack > 5 and climb_rate < -3 then
        self._elevator_angle = 0
        self._angle_of_attack = -1
        newpitch = math.rad(self._angle_of_attack)
    end

    --minetest.chat_send_all('rate '.. climb_rate)
    local climb_angle = hidroplane.get_gauge_angle(climb_rate)
    self.climb_gauge:set_attach(self.object,'',HIDROPLANE_GAUGE_CLIMBER_POSITION,{x=0,y=0,z=climb_angle})

    local indicated_speed = longit_speed
    if indicated_speed < 0 then indicated_speed = 0 end
    local speed_angle = hidroplane.get_gauge_angle(indicated_speed, -45)
    self.speed_gauge:set_attach(self.object,'',HIDROPLANE_GAUGE_SPEED_POSITION,{x=0,y=0,z=speed_angle})

    --adjust power indicator
    local power_indicator_angle = hidroplane.get_gauge_angle(self._power_lever/10)
    self.power_gauge:set_attach(self.object,'',HIDROPLANE_GAUGE_POWER_POSITION,{x=0,y=0,z=power_indicator_angle})

    --apply rotations
	if newyaw~=yaw or newpitch~=pitch or newroll~=roll then
        self.object:set_rotation({x=newpitch,y=newyaw,z=newroll})
    end

    --adjust elevator pitch (3d model)
    self.elevator:set_attach(self.object,'',{x=0,y=4,z=-35.5},{x=-self._elevator_angle,y=0,z=0})
    --adjust rudder
    self.rudder:set_attach(self.object,'',{x=0,y=0.12,z=-36.85},{x=0,y=self._rudder_angle,z=0})
    --adjust ailerons
    self.right_aileron:set_attach(self.object,'',{x=0,y=8.08,z=-7},{x=-self._rudder_angle,y=0,z=0})
    self.left_aileron:set_attach(self.object,'',{x=0,y=8.08,z=-7},{x=self._rudder_angle,y=0,z=0})

    -- calculate energy consumption --
    hidroplane.consumptionCalc(self, accel)

    --automatically set landgear
    hidroplane.lang_gear_operate(self, curr_pos)

    --test collision
    hidroplane.testImpact(self, velocity, curr_pos)

    --saves last velocity for collision detection (abrupt stop)
    self._last_vel = self.object:get_velocity()
end

