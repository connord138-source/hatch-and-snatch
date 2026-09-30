--!strict
-- Where an egg is on the conveyor loop, from its age alone. The server moves the
-- egg parts a few times a second (enough for buying), and every client moves them
-- smoothly on the same path each frame (BeltController), so the belt costs almost
-- no bandwidth. Eggs start in the middle of the hatchery tunnel and ride one lap.
local Config = require(script.Parent.Config)

local conveyor = Config.Eggs.conveyor
local TUNNEL_CENTER = math.rad(conveyor.tunnelCenterDegrees)
local ANGULAR_SPEED = conveyor.speed / conveyor.radius

local Belt = {
	TUNNEL_CENTER = TUNNEL_CENTER,
	TUNNEL_HALF = math.rad(conveyor.tunnelHalfDegrees),
	LAP_SECONDS = 2 * math.pi / ANGULAR_SPEED,
}

-- The loop angle of an egg that has been riding for `age` seconds.
function Belt.angle(age: number): number
	return TUNNEL_CENTER + ANGULAR_SPEED * age
end

-- Whether that angle is inside the tunnel (no buying there).
function Belt.inTunnel(angle: number): boolean
	local fromCenter = math.abs(((angle - TUNNEL_CENTER + math.pi) % (2 * math.pi)) - math.pi)
	return fromCenter <= Belt.TUNNEL_HALF
end

-- The egg's CFrame at that angle around `center`, with a little bob.
function Belt.cframe(center: Vector3, angle: number): CFrame
	local bob = math.sin(angle * 6) * 0.15
	local position = center
		+ Vector3.new(
			math.cos(angle) * conveyor.radius,
			conveyor.height + bob,
			math.sin(angle) * conveyor.radius
		)
	return CFrame.new(position) * CFrame.Angles(0, -angle, 0)
end

return Belt
