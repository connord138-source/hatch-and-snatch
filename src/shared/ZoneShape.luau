--!strict
-- The shape of a biome zone: a walled sector of the ring around the plots (owner,
-- 2026-10-01: lay the island out like the approved concept, a ring of walled
-- biomes between the fortresses and the open land by the beach). Shared so the
-- server (locked-zone push-out, zone events) and the client (zone moods) agree on
-- who is inside. Angles are math.atan2(z, x) around the hub at the world origin.
export type Sector = {
	inner: number, -- inner wall radius
	outer: number, -- outer wall radius
	from: number, -- start angle (radians)
	to: number, -- end angle, greater than `from`
}

local ZoneShape = {}

local TAU = 2 * math.pi

-- True when `position` (any height) is inside the sector's walls.
function ZoneShape.contains(sector: Sector, position: Vector3): boolean
	local distance = math.sqrt(position.X * position.X + position.Z * position.Z)
	if distance < sector.inner or distance > sector.outer then
		return false
	end
	local offset = (math.atan2(position.Z, position.X) - sector.from) % TAU
	return offset <= sector.to - sector.from
end

-- A point in the sector: `along` 0..1 from `from` to `to`, `depth` 0..1 from the
-- inner wall to the outer one.
function ZoneShape.point(sector: Sector, along: number, depth: number, y: number?): Vector3
	local angle = sector.from + (sector.to - sector.from) * along
	local radius = sector.inner + (sector.outer - sector.inner) * depth
	return Vector3.new(math.cos(angle) * radius, y or 0, math.sin(angle) * radius)
end

return ZoneShape
