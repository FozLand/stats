--[[
Copyright (C) 2013 PilzAdam <pilzadam@minetest.net>
Copyright (C) 2016 John Cole
This file is part of Stats.

Stats is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

Stats is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with Stats.  If not, see <http://www.gnu.org/licenses/>.
]]

--
-- API
--

stats = {}
local playerstats = {}

--[[
def = {
	name = "digged_nodes",
	description = function(value)
		return " - Digged nodes: "..value)
	end,
}
]]
stats.registered_stats = {}
function stats.register_stat(def)
	table.insert(stats.registered_stats, def)
end

function stats.set_stat(player, name, value)
	local pname = player
	if type(pname) ~= "string" then
		pname = player:get_player_name()
	end
	if not playerstats[pname] then
		playerstats[pname] = {}
	end
	playerstats[pname][name] = value
end

function stats.increase_stat(player, name, value)
	local pname = player
	if type(pname) ~= "string" then
		pname = player:get_player_name()
	end
	if not playerstats[pname] then
		playerstats[pname] = {}
	end
	if not playerstats[pname][name] then
		playerstats[pname][name] = 0
	end
	playerstats[pname][name] = playerstats[pname][name] + value
end

function stats.decrease_stat(player, name, value)
	stats.increase_stat(player, name, -value)
end

function stats.get_stat(player, name)
	local pname = player
	if type(pname) ~= "string" then
		pname = player:get_player_name()
	end
	if not playerstats[pname] then
		playerstats[pname] = {}
	end
	if not playerstats[pname][name] then
		playerstats[pname][name] = 0
	end
	return playerstats[pname][name]
end

--
-- End API
--

stats.register_stat({
	name = "first_login",
	description = function(value)
		local result = "unknown"
		if value > 0 then
			local date = os.date("!%F %T %Z", value)
			local days = math.floor( (os.time() - value) / 864 ) / 100
			result = date.."("..days.." days ago)"
		end
		return " - First login: "..result
	end,
})

stats.register_stat({
	name = "digged_nodes",
	description = function(value)
		return " - Digged nodes: "..value
	end,
})

stats.register_stat({
	name = "placed_nodes",
	description = function(value)
		return " - Placed nodes: "..value
	end,
})

stats.register_stat({
	name = "died",
	description = function(value)
		return " - Died: "..value
	end,
})

stats.register_stat({
	name = "played_time",
	description = function(time)
		time = math.floor(time)
		local timestring = "" .. (time%60) .. "s"
		time = math.floor(time/60)
		if time > 0 then
			timestring = (time%60) .. "m " .. timestring
		end
		time = math.floor(time/60)
		if time > 0 then
			timestring = (time%24) .. "h " .. timestring
		end
		time = math.floor(time/24)
		if time > 0 then
			timestring = time .. "d " .. timestring
		end
		return " - Time played: "..timestring
	end,
})

stats.register_stat({
	name = "crafted",
	description = function(value)
		return " - Crafted items: "..value
	end,
})

local file = io.open(minetest:get_worldpath().."/stats.mt", "r")
if file then
		local table = minetest.deserialize(file:read("*all"))
		if type(table) == "table" then
			playerstats = table
		else
			minetest.log("error", "Corrupted stats file")
		end
		file:close()
end

local function save_stats()
	local path = minetest:get_worldpath()
	os.execute("cp "..path.."/stats.mt "..path.."/stats.bak")

	-- Sometimes the server runs out of RAM causing a crash. It seems to be
	-- crashing while writting the stats file resulting in an empty file. By
	-- serializing the stats data before opening the file, I hope any impending
	-- crash will be occur during serialization before the file is opened. Thus
	-- preserving the previous stats data.
	local data = minetest.serialize(playerstats)
	local file = io.open(path.."/stats.mt", "w")
	if file then
		file:write(data)
		file:close()
	else
		minetest.log("error", "Can't save stats")
	end
end

local timer = 0
minetest.register_globalstep(function(dtime)
	timer = timer + dtime
	
	-- NOTE: Set this to a higher value to remove some load from the server
	if timer > 1 then
		for _,player in ipairs(minetest.get_connected_players()) do
			stats.increase_stat(player, "played_time", timer)
		end
		timer = 0
	end
end)

local function save()
	save_stats()
	minetest.after(60, save)
end
minetest.after(60, save)

minetest.register_on_shutdown(function() 
	save_stats()
end)

minetest.register_on_newplayer(function(player)
	stats.set_stat(player, "first_login", os.time())
end)

minetest.register_on_dignode(function(pos, oldnode, player)
	if player and player:is_player() then
		stats.increase_stat(player, "digged_nodes", 1)
	end
end)

minetest.register_on_placenode(function(pos, newnode, player, oldnode, itemstack)
	if player and player:is_player() then
		stats.increase_stat(player, "placed_nodes", 1)
	end
end)

minetest.register_on_dieplayer(function(player)
	stats.increase_stat(player, "died", 1)
end)

minetest.register_on_craft(function(itemstack, player, old_craft_grid, craft_inv)
	stats.increase_stat(player, "crafted", itemstack:get_count())
end)

--
-- CLI
--

minetest.register_chatcommand("stats", {
	params = "<name>",
	description = "Prints the stats of the player",
	privs = {kick=true},
	func = function(name, param)
		local player_name = name
		if param ~= "" then
			player_name = string.match(param, '^([^ ]+)$')
			if not player_name then
				return false, 'Invalid parameters (see /help stats)'
			elseif not core.auth_table[player_name] then
				return false, 'Player ' .. player_name .. ' does not exist.'
			end
		end

		minetest.chat_send_player(name, "Stats for "..player_name..":")
		for _,def in ipairs(stats.registered_stats) do
			local value = stats.get_stat(player_name, def.name)
			minetest.chat_send_player(name, def.description(value))
		end
	end,
})

--
-- GUI
--

local gui_state = {}

function stats.player_search(query)

	-- Return a table with the stats of each player whose name contains the
	-- search string in a separate row. If the search string is empty, return a
	-- table for all of the connected players.

	local results = {}
	if query == '' then
		for _,player in ipairs(minetest.get_connected_players()) do
			local player_name = player:get_player_name()
			local row = {player_name}
			for _,stat in ipairs(stats.registered_stats) do
				local value = stats.get_stat(player_name, stat.name)
				table.insert(row,value)
			end
			table.insert(results,row)
		end
	else
		for player_name,_ in pairs(playerstats) do
			if string.find(string.lower(player_name), string.lower(query)) then
				local row = {player_name}
				for _,stat in ipairs(stats.registered_stats) do
					local value = stats.get_stat(player_name, stat.name)
					table.insert(row,value)
				end
				table.insert(results,row)
				if #results > 99 then break end
			end
		end
	end

	table.sort(results, function(a,b)
		return a[1] < b[1]
	end)
	return results
end

local function summary_form(name)
	if type(name) ~= 'string' or not gui_state[name] then
		local fs = 'size[12,7.5]'
		fs = fs..'label[0,0;Stats Summary Form - An Error Occurred.]'
		return fs
	end
	local player_name = gui_state[name].player_name
	local query = gui_state[name].query

	local fs = 'size[12,7.5]'
	fs = fs..'label[0,0;Stats - summary for player: '..player_name..']'
	fs = fs..'button_exit[11,-0.2;1,1;exit;X]'

	fs = fs..'tableoptions[highlight=#1e1e1e]'
	fs = fs..'tablecolumns['..
		'text,align=right;'..
		'text,align=left,padding=1;'..
		'text,align=left]'
	fs = fs..'table[0,0.7;11.8,5.9;summary;'..
		'Stat.,Value,Description,'
	for i,def in ipairs(stats.registered_stats) do
		local value = stats.get_stat(player_name, def.name)
		local desc  = def.description(value)
		fs = fs..def.name..','..math.floor(value)..','..desc..','
	end
	fs = fs..';]'

	fs = fs..'button[0,6.8;3,1;search;Search]'
	fs = fs..'field[3.3,7.13;9,1;query;;'..query..']'

	return fs
end

local function search_form(name)
	if type(name) ~= 'string' or not gui_state[name] then
		local fs = 'size[12,7.5]'
		fs = fs..'label[0,0;Stats Search Form - An Error Occurred.]'
		return fs
	end
	local query = gui_state[name].query
	local results = gui_state[name].results

	local fs = 'size[12,7.5]'
	fs = fs..'label[0,0;Stats - search results for: '..query..']'
	fs = fs..'button_exit[11,-0.2;1,1;exit;X]'

	fs = fs..'tableoptions[highlight=#1e1e1e]'

	fs = fs..'tablecolumns[text,align=right;text,align=left'
	for i = 1,#(stats.registered_stats) do fs = fs..';text,align=right' end
	fs = fs..']'

	fs = fs..'table[0,0.7;11.8,5.9;results;'..'#:,Name'
	for _,stat in ipairs(stats.registered_stats) do fs = fs..','..stat.name end
	for i,row in ipairs(results) do
		fs = fs..','..tostring(i)..':'
		for _,stat in ipairs(row) do
			fs = fs..','..stat
		end
	end
	fs = fs..';]'

	fs = fs..'button[0,6.8;3,1;search;Search]'
	fs = fs..'field[3.3,7.13;9,1;query;;'..query..']'
	return fs
end

local function edit_form(name)
	if type(name) ~= 'string' or not gui_state[name] then
		local fs = 'size[12,7.5]'
		fs = fs..'label[0,0;Stats Edit Form - An Error Occurred.]'
		return fs
	end
	local player_name = gui_state[name].player_name
	local query = gui_state[name].query
	local stat = gui_state[name].stat
	local value = stats.get_stat(player_name, stat.name)
	local desc  = stat.description(value)

	local fs = 'size[12,7.5]'
	fs = fs..'label[0,0;Stats - editor for player: '..player_name..']'
	fs = fs..'button_exit[11,-0.2;1,1;exit;X]'

	fs = fs..'button[0,0.8;12,1;back;Back to Player Summary]'

	fs = fs..'button[1,2.3;1,1;prev;<]'
	fs = fs..'label[5,2.55;'..stat.name..']'
	fs = fs..'button[10,2.3;1,1;next;>]'

	fs = fs..'tableoptions[highlight=#1e1e1e]'
	fs = fs..'tablecolumns[text,align=center]'
	fs = fs..'table[1,3.3;9.75,1.5;desc;,'..desc..';]'

	fs = fs..'button[1,5.3;3,1;update;Update]'
	fs = fs..'field[4.3,5.63;7,1;value;Value;'..value..']'

	fs = fs..'button[0,6.8;3,1;search;Search]'
	fs = fs..'field[3.3,7.13;9,1;query;;'..query..']'
	return fs
end

minetest.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= 'stats:summary' then return end

	local name = player:get_player_name()
	if not minetest.check_player_privs(name, {kick=true}) then
		minetest.kick_player(name, 'Privilege violation.')
	end

	if fields then
		if fields.summary and
		   minetest.check_player_privs(name, {server=true}) then
			local row, col = string.match(fields.summary, 'CHG:([0-9]+):([0-9]+)')
			if row and tonumber(row) > 1 then
				gui_state[name].view   = 'edit'
				gui_state[name].stat   = stats.registered_stats[row-1]
				minetest.show_formspec(name, 'stats:edit', edit_form(name))
			end
			return
		end

		if fields.search then
			local results = stats.player_search(fields.query)
			gui_state[name].view   = 'search'
			gui_state[name].player_name = nil
			gui_state[name].query   = fields.query
			gui_state[name].results = stats.player_search(fields.query)
			minetest.show_formspec(name, 'stats:search', search_form(name))
			return
		end

		-- Refresh form
		if not fields.quit then
			minetest.show_formspec(name, formname, summary_form(name))
		end
	end
end)

minetest.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= 'stats:search' then return end

	local name = player:get_player_name()
	if not minetest.check_player_privs(name, {kick=true}) then
		minetest.kick_player(name, 'Privilege violation.')
	end

	if fields then
		if fields.results then
			local row, col = string.match(fields.results, 'CHG:([0-9]+):([0-9]+)')
			if row and tonumber(row) > 1 then
				gui_state[name].view        = 'summary'
				gui_state[name].player_name = gui_state[name].results[row-1][1]
				gui_state[name].results     = nil
				minetest.show_formspec(name, 'stats:summary', summary_form(name))
			else
				table.sort(gui_state[name].results, function(a,b)
					return a[col-1] > b[col-1]
				end)
				minetest.show_formspec(name, formname, search_form(name))
			end
			return
		end

		if fields.search then
			gui_state[name].query   = fields.query
			gui_state[name].results = stats.player_search(fields.query)
			minetest.show_formspec(name, formname, search_form(name))
			return
		end
	end
end)

minetest.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= 'stats:edit' then return end

	local name = player:get_player_name()
	if not minetest.check_player_privs(name, {server=true}) then
		minetest.kick_player(name, 'Privilege violation.')
	end

	if fields then
		if fields.back then
			minetest.show_formspec(name, 'stats:summary', summary_form(name))
			return
		end

		if fields.prev then
			local prev = stats.registered_stats[#stats.registered_stats]
			for index, stat in ipairs(stats.registered_stats) do
				if stat == gui_state[name].stat then
					gui_state[name].stat = prev
					break
				else
					prev = stat
				end
			end
			minetest.show_formspec(name, formname,edit_form(name))
			return
		end

		if fields.next then
			local stats = stats.registered_stats
			for index, stat in ipairs(stats) do
				if stat == gui_state[name].stat then
					if index == #stats then index = 0 end
					gui_state[name].stat = stats[index+1]
					break
				end
			end
			minetest.show_formspec(name, formname,edit_form(name))
			return
		end

		if fields.update and tonumber(fields.value) then
			local player_name = gui_state[name].player_name
			local stat_name   = gui_state[name].stat.name
			stats.set_stat(player_name, stat_name, tonumber(fields.value))
			minetest.show_formspec(name, formname, edit_form(name))
			return
		end

		if fields.search then
			gui_state[name].view    = 'search'
			gui_state[name].query   = fields.query
			gui_state[name].results = stats.player_search(fields.query)
			minetest.show_formspec(name, 'stats:search', search_form(name))
			return
		end
	end
end)

minetest.register_chatcommand('stats_gui', {
	params = '[player_name]',
	description = 'Launches the stats gui.',
	privs = {kick=true},
	func = function(name, param)
		local player_name = name
		if param ~= "" then
			player_name = string.match(param, '^([^ ]+)$')
			if not player_name then
				return false, 'Invalid parameters (see /help stats)'
			elseif not minetest.auth_table[player_name] then
				return false, 'Player ' .. player_name .. ' does not exist.'
			end
		end

		if gui_state[name] and name == player_name then -- resume
			local view = gui_state[name].view
			if view == 'search' then
				minetest.show_formspec(name, 'stats:search',  search_form(name))
			elseif view == 'edit' then
				minetest.show_formspec(name, 'stats:edit',    edit_form(name))
			else
				minetest.show_formspec(name, 'stats:summary', summary_form(name))
			end
		else
			gui_state[name] = {}
			gui_state[name].view = 'summary'
			gui_state[name].query = ''
			gui_state[name].player_name = player_name
			minetest.show_formspec(name, 'stats:summary', summary_form(name))
		end
	end
})
