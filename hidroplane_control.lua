--global constants
hidroplane.vector_up = vector.new(0, 1, 0)
hidroplane.ideal_step = 0.02
hidroplane.rudder_limit = 30
hidroplane.elevator_limit = 40

dofile(minetest.get_modpath("hidroplane") .. DIR_DELIM .. "hidroplane_utilities.lua")

function hidroplane.check_node_below(obj)
	local pos_below = obj:get_pos()
	pos_below.y = pos_below.y - 0.1
	local node_below = minetest.get_node(pos_below).name
	local nodedef = minetest.registered_nodes[node_below]
	local touching_ground = not nodedef or -- unknown nodes are solid
			nodedef.walkable or false
	local liquid_below = not touching_ground and nodedef.liquidtype ~= "none"
	return touching_ground, liquid_below
end

function hidroplane.powerAdjust(self,dtime,factor,dir,max_power)
    local max = max_power or 100
    local add_factor = factor/2
    add_factor = add_factor * (dtime/hidroplane.ideal_step) --adjusting the command speed by dtime
    local power_index = self._power_lever

    if dir == 1 then
        if self._power_lever < max then
            self._power_lever = self._power_lever + add_factor
        end
        if self._power_lever > max then
            self._power_lever = max
        end
    end
    if dir == -1 then
        if self._power_lever > 0 then
            self._power_lever = self._power_lever - add_factor
            if self._power_lever < 0 then self._power_lever = 0 end
        end
        if self._power_lever <= 0 then
            self._power_lever = 0
        end
    end
    if power_index ~= self._power_lever then
        hidroplane.engineSoundPlay(self)
    end

end

function hidroplane.control(self, dtime, hull_direction, longit_speed, longit_drag,
                            later_speed, later_drag, accel, player, is_flying)
    if hidroplane.last_time_command > 1 then hidroplane.last_time_command = 1 end
    --if self.driver_name == nil then return end
    local retval_accel = accel

    local stop = false
    local ctrl = nil

	-- player control
	if player then
		ctrl = player:get_player_control()

        --engine and power control
        if ctrl.aux1 and hidroplane.last_time_command > 0.5 then
            hidroplane.last_time_command = 0
		    if self._engine_running then
			    self._engine_running = false
                self._autopilot = false
		        -- sound and animation
                if self.sound_handle then
                    minetest.sound_stop(self.sound_handle)
                    self.sound_handle = nil
                end
		        self.engine:set_animation_frame_speed(0)
                self._power_lever = 0 --zero power
		    elseif self._engine_running == false and self._energy > 0 then
			    self._engine_running = true
	            -- sound and animation
                hidroplane.engineSoundPlay(self)
                self.engine:set_animation_frame_speed(60)
		    end
        end

        self._acceleration = 0
        if self._engine_running then
            --engine acceleration calc
            local engineacc = (self._power_lever * hidroplane.max_engine_acc) / 100;
            self.engine:set_animation_frame_speed(60 + self._power_lever)

            local factor = 1

            --increase power lever
            if ctrl.jump then
                hidroplane.powerAdjust(self, dtime, factor, 1)
            end
            --decrease power lever
            if ctrl.sneak then
                hidroplane.powerAdjust(self, dtime, factor, -1)
                if self._power_lever <= 0 and is_flying == false then
                    --break
                    if longit_speed > 0 then
                        engineacc = -1
                        if (longit_speed + engineacc) < 0 then engineacc = longit_speed * -1 end
                    end
                    if longit_speed < 0 then
                        engineacc = 1
                        if (longit_speed + engineacc) > 0 then engineacc = longit_speed * -1 end
                    end
                    if abs(longit_speed) < 0.1 then
                        stop = true
                    end
                end
            end
            --do not exceed
            local max_speed = 6
            if longit_speed > max_speed then
                engineacc = engineacc - (longit_speed-max_speed)
                if engineacc < 0 then engineacc = 0 end
            end
            self._acceleration = engineacc
        else
	        local paddleacc = 0
	        if longit_speed < 1.0 then
                if ctrl.jump then paddleacc = 0.5 end
            end
	        if longit_speed > -1.0 then
                if ctrl.sneak then paddleacc = -0.5 end
	        end
	        self._acceleration = paddleacc
        end

        local hull_acc = vector.multiply(hull_direction,self._acceleration)
        retval_accel=vector.add(retval_accel,hull_acc)

        --pitch
        local pitch_cmd = 0
        if ctrl.up then pitch_cmd = 1 elseif ctrl.down then pitch_cmd = -1 end
        hidroplane.set_pitch(self, pitch_cmd, dtime)

		-- yaw
        local yaw_cmd = 0
        if ctrl.right then yaw_cmd = 1 elseif ctrl.left then yaw_cmd = -1 end
        hidroplane.set_yaw(self, yaw_cmd, dtime)

        --I'm desperate, center all!
        if ctrl.right and ctrl.left then
            self._elevator_angle = 0
            self._rudder_angle = 0
        end
	end

    if longit_speed > 0 then
        if ctrl then
            if ctrl.right or ctrl.left then
            else
                hidroplane.rudder_auto_correction(self, longit_speed, dtime)
            end
        else
            hidroplane.rudder_auto_correction(self, longit_speed, dtime)
        end
        hidroplane.elevator_auto_correction(self, longit_speed, dtime)
    end

    return retval_accel, stop
end

function hidroplane.set_pitch(self, dir, dtime)
    local pitch_factor = 10
	if dir == -1 then
		self._elevator_angle = math.max(self._elevator_angle-pitch_factor*dtime,-hidroplane.elevator_limit)
	elseif dir == 1 then
        if self._angle_of_attack < 0 then pitch_factor = 1 end --lets reduce the command power to avoid accidents
		self._elevator_angle = math.min(self._elevator_angle+pitch_factor*dtime,hidroplane.elevator_limit)
	end
end

function hidroplane.set_yaw(self, dir, dtime)
    local yaw_factor = 25
	if dir == 1 then
		self._rudder_angle = math.max(self._rudder_angle-(yaw_factor*dtime),-hidroplane.rudder_limit)
	elseif dir == -1 then
		self._rudder_angle = math.min(self._rudder_angle+(yaw_factor*dtime),hidroplane.rudder_limit)
	end
end

function hidroplane.rudder_auto_correction(self, longit_speed, dtime)
    local factor = 1
    if self._rudder_angle > 0 then factor = -1 end
    local correction = (hidroplane.rudder_limit*(longit_speed/1000)) * factor * (dtime/hidroplane.ideal_step)
    local before_correction = self._rudder_angle
    local new_rudder_angle = self._rudder_angle + correction
    if math.sign(before_correction) ~= math.sign(new_rudder_angle) then
        self._rudder_angle = 0
    else
        self._rudder_angle = new_rudder_angle
    end
end

function hidroplane.elevator_auto_correction(self, longit_speed, dtime)
    local factor = 1
    --if self._elevator_angle > -1.5 then factor = -1 end --here is the "compensator" adjusto to keep it stable
    if self._elevator_angle > 0 then factor = -1 end
    local correction = (hidroplane.elevator_limit*(longit_speed/10000)) * factor * (dtime/hidroplane.ideal_step)
    local before_correction = self._elevator_angle
    local new_elevator_angle = self._elevator_angle + correction
    if math.sign(before_correction) ~= math.sign(new_elevator_angle) then
        self._elevator_angle = 0
    else
        self._elevator_angle = new_elevator_angle
    end
end

function hidroplane.engineSoundPlay(self)
    --sound
    if self.sound_handle then minetest.sound_stop(self.sound_handle) end
    self.sound_handle = minetest.sound_play({name = "hidroplane_engine"},
        {object = self.object, gain = 2.0,
            pitch = 0.5 + ((self._power_lever/100)/2),max_hear_distance = 15,
            loop = true,})
end

--obsolete, will be removed
function getAdjustFactor(curr_y, desired_y)
    local max_difference = 0.1
    local adjust_factor = 0.5
    local difference = math.abs(curr_y - desired_y)
    if difference > max_difference then difference = max_difference end
    return (difference * adjust_factor) / max_difference
end

function hidroplane.autopilot(self, dtime, hull_direction, longit_speed, accel, curr_pos)

    local retval_accel = accel

    local max_autopilot_power = 85
    local max_attack_angle = 1.8

    --climb
    local velocity = self.object:get_velocity()
    local climb_rate = velocity.y * 1.5
    if climb_rate > 5 then climb_rate = 5 end
    if climb_rate < -5 then
        climb_rate = -5
    end

    self._acceleration = 0
    if self._engine_running then
        --engine acceleration calc
        local engineacc = (self._power_lever * hidroplane.max_engine_acc) / 100;
        self.engine:set_animation_frame_speed(60 + self._power_lever)

        local factor = math.abs(climb_rate * 0.5) --getAdjustFactor(curr_pos.y, self._auto_pilot_altitude)
        --increase power lever
        if climb_rate > 0.2 then
            hidroplane.powerAdjust(self, dtime, factor, -1)
        end
        --decrease power lever
        if climb_rate < 0 then
            hidroplane.powerAdjust(self, dtime, factor, 1, max_autopilot_power)
        end
        --do not exceed
        local max_speed = 6
        if longit_speed > max_speed then
            engineacc = engineacc - (longit_speed-max_speed)
            if engineacc < 0 then engineacc = 0 end
        end
        self._acceleration = engineacc
    end

    local hull_acc = vector.multiply(hull_direction,self._acceleration)
    retval_accel=vector.add(retval_accel,hull_acc)

    --pitch
    if self._angle_of_attack > max_attack_angle then
        hidroplane.set_pitch(self, 1, dtime)
    elseif self._angle_of_attack < max_attack_angle then
        hidroplane.set_pitch(self, -1, dtime)
    end

	-- yaw
    hidroplane.set_yaw(self, 0, dtime)

    if longit_speed > 0 then
        hidroplane.rudder_auto_correction(self, longit_speed, dtime)
        hidroplane.elevator_auto_correction(self, longit_speed, dtime)
    end

    return retval_accel
end
