#!/usr/bin/lua

-- This script is intended to help initialize the stats on an existing server
-- using the debug.txt log files before enabling the stats mod. The stat totals
-- are added to cummulatively so start will no stats.txt file and only run this
-- script once per debug file. Also, make sure the server is not running, or at
-- the very least that the stats mod is not running yet.

local load_time_start = os.clock()
print('Searching logs for player data...')
local now = os.time()

if #arg ~= 1 then
	io.write(string.format('Usage:\n  %s <WorldPath>\n',arg[0]))
	return
end

-------------
-- HELPERS --
-------------

serialize = function(o, f)
	if type(o) == 'number' then
		f:write(o)
	elseif type(o) == 'string' then
		f:write(string.format('%q', o))
	elseif type(o) == 'table' then
		f:write('{')
		local first = true
		for k,v in pairs(o) do
			if first then
				first = false
			else
				f:write(', ')
			end
			f:write('[')
			serialize(k, f)
			f:write('] = ')
			serialize(v, f)
		end
		f:write('}')
	else
		error('cannot serialize a ' .. type(o))
	end
end

local load_players = function(world_path)
	-- Stats will only be counted for players in auth.txt
	local f = assert(io.open(world_path .. '/auth.txt', 'r'))
	local auth_data = f:read('*all')
	f:close()

	local players = {}
	local count = 0
	for line in string.gmatch(auth_data, '([^\n]*)\n') do
		local pattern = '([^:]*):([^:]*):([^:]*):([^:]*)'
		for n, h, p, t in string.gmatch(line, pattern) do
			table.insert(players,n) -- to retain player order
			players[n] = {
				name = n,
				hash = h,
				privs = p,
				last_login = tonumber(t),
			}
			count = count + 1
		end
	end
	table.sort(players)
	return players, count
end

local approx_player_stats = function(world_path, players, stats)
	local f = assert(io.open(world_path..'/debug.txt', 'r'))
	local debug_data = f:read('*all')
	f:close()

	local time_pattern = '(%d%d%d%d)[-](%d%d)[-](%d%d) (%d%d):(%d%d):(%d%d): (.+)'

	local pre_p        = 'ACTION%[[%S]+%]: '
	local pos_p        = '%(%-?%d+,%-?%d+,%-?%d+%)'
	local node_p       = '[%S]+:[%S]+'
	local player_p     = '([%S]+)'

	local init_pattern   = pre_p..'Giving initial stuff to player '..player_p
	local crafts_pattern = pre_p..'player '..player_p..' crafts '..node_p
	local digged_pattern = pre_p..player_p..' digs '..node_p..' at '..pos_p
	local placed_pattern = pre_p..player_p..' places node '..node_p..' at '..pos_p
	local joined_pattern = pre_p..player_p..' joins game. List of players: '
	local leaves_pattern = pre_p..player_p..' leaves game. List of players: '
	local resets_pattern = '  Separator'

	local join_times = {}
	local time = 0

	-- For each line in the debug data
	for line in string.gmatch(debug_data, '([^\n]*)\n') do

		-- Capture event server time.
		for Y, M, D, h, m, s, event in string.gmatch(line, time_pattern) do
			time = os.time({year = Y, month = M, day = D, hour = h, min = m, sec = s})

			-- Find initial logins.
			for name in string.gmatch(event, init_pattern) do
				if players[name] then
					stats[name].first_login = time
				end
			end

			-- Sum items crafted.
			for name in string.gmatch(event, crafts_pattern) do
				if players[name] then
					stats[name].crafted = (stats[name].crafted or 0) + 1
				end
			end

			-- Sum nodes dug.
			for name in string.gmatch(event, digged_pattern) do
				if players[name] then
					stats[name].digged_nodes = (stats[name].digged_nodes or 0) + 1
				end
			end

			-- Sum nodes placed.
			for name in string.gmatch(event, placed_pattern) do
				if players[name] then
					stats[name].placed_nodes = (stats[name].placed_nodes or 0) + 1
				end
			end

			-- Sum player total time online as played time.
			for name in string.gmatch(event, joined_pattern) do
				if players[name] then
					join_times[name] = time
				end
			end

			for name in string.gmatch(event, leaves_pattern) do
				if players[name] then
					if join_times[name] then
						local time_online = time - join_times[name]
						stats[name].played_time = stats[name].played_time + time_online
						join_times[name] = nil
					else
						print('Warning: Missing join time for player '..name..
							' who left at '..os.date('%F %T %Z',time))
					end
				end
			end
		end

		if string.match(line, resets_pattern) then
			--print('Server reset at '..os.date('%F %T %Z',time))
			for name, join_time in pairs(join_times) do
				local time_online = time - join_time
				stats[name].played_time = stats[name].played_time + time_online
			end
			join_times = {}
		end

	end
end

local calc_claim_counts = function(world_path, players, stats)
	local f = assert(io.open(world_path..'/landrush-claims', 'r'))
	local claim_data = f:read('*all')
	f:close()

	for line in string.gmatch(claim_data, '([^\n]*)\n') do
		local pattern = '([%S]+)%s([%S]+)%s([%S]+)%s([%S]+)'
		for pos, owner, shared, claim_type in string.gmatch(line, pattern) do
			if claim_type == 'landclaim' then
				-- increment owned count
				stats[owner].land_claims = stats[owner].land_claims + 1

				for name in string.gmatch(shared, '([^,]+)') do
					-- increment shared count
					if name ~= '*' and name ~= '*all' and players[name] then
						stats[name].land_shares = stats[name].land_shares + 1
					end
				end
			end
		end
	end
end

local load_player_stats = function(world_path)
	local full_name = world_path .. '/stats.txt'
	local f=io.open(full_name,"r")
	local player_stats = {}
	if f~=nil then
		f:close()
		player_stats = dofile(full_name)
	end

	if type(player_stats) == "table" then
		return player_stats
	else
		error("Corrupted stats file")
	end
end

local save_player_stats = function(world_path, player_stats)
	for k,v in pairs(player_stats) do
		print(v.first_login,v.digged_nodes,v.placed_nodes,v.crafted,v.played_time,k)
	end
	local f = assert(io.open(world_path..'/stats.txt', 'w'))
	f:write('return ')
	serialize(player_stats, f)
	f:close()
end

----------------
-- Main logic --
----------------

local world_path = arg[1]
local players, player_count = load_players(world_path)

local player_stats = {} --load_player_stats(world_path)
for _, name in ipairs(players) do
	if not player_stats[name] then
		player_stats[name] = {
			first_login  = 0,
			played_time  = 0,
			digged_nodes = 0,
			placed_nodes = 0,
			crafted      = 0,
			died         = 0,
			land_claims  = 0,
			land_shares  = 0,
		}
	end
end

approx_player_stats(world_path, players, player_stats)
calc_claim_counts(world_path, players, player_stats)

save_player_stats(world_path, player_stats)

print('Found '..player_count..' players.')
io.write(string.format('Finished in %.3fs\n',os.clock() - load_time_start))
