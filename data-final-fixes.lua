lib={DATA_LOGIC=true}
require("lib/lib")

local hand=logic.hand
logic.seed(settings.startup["randotorio_seed"].value)

local rando={}

rando.queued={} -- table of recipes sitting in queue
rando.eject={} -- Recipes that have ejected ingredients
rando.ejectqueue={} -- Recipes waiting to be ejected
rando.roll={} -- Recipes that have ingredients rolled
rando.rollqueue={} -- Recipe queue for randomization. Happens upon ejecting.

rando.pool={} local pool={} -- The ingredients and recipes pool
pool.items={} -- Item-type ingredients
pool.itemcount={}
pool.fluids={} -- Fluid type ingredients
pool.fluidcount={}


function rando.EjectRecipe(rcp) -- Eject ingredients into pool
	if(rando.eject[rcp.name])then return true end
	if(not logic.CanCraftRecipe(rcp))then return false end

	if(not proto.UsedRecipe(rcp.name) or logic.Ignoring(rcp))then rando.eject[rcp.name]=true return true end
	rando.eject[rcp.name]=true
	local ings=proto.Ingredients(rcp) if(not ings)then return true end
	for k,v in pairs(ings)do
		local ing=proto.Ingredient(v)
		local pv=(ing.type=="fluid" and pool.fluids or pool.items)
		local pc=(ing.type=="fluid" and pool.fluidcount or pool.itemcount)
		pv[ing.name]=pv[ing.name] or {}
		table.insert(pv[ing.name],table.deepcopy(v))
		pc[ing.name]=table_size(pv[ing.name])
	end
	local i=math.random(1,#rando.rollqueue+1)
	table.insert(rando.rollqueue,i,rcp)
	return true
end


--[[ Initialize Rando Logic ]]--

function rando.TransmuteItems()
	if(table_size(hand.items)<1)then return end
	local tbl,key=table.Random(pool.items)
	local _,newkey=table.Random(hand.itemscan)
	if(not newkey or newkey=="")then return end
	if(newkey==key)then return end
	if(key and tbl)then
		local ctbl=#tbl
		local i=math.random(1,ctbl)
		local v=table.deepcopy(proto.Ingredient(tbl[i]))
		table.remove(tbl,i)
		if(ctbl==1)then pool.items[key]=nil end
		local z=(pool.itemcount[key] or 0)-1
		if(z>0)then pool.itemcount[key]=z else pool.itemcount[key]=nil end

		v.name=newkey
		pool.items[newkey]=pool.items[newkey] or {}
		table.insert(pool.items[newkey],v)
		pool.itemcount[newkey]=table_size(pool.items[newkey])
	end	
end
function rando.TransmuteFluids()
	if(table_size(hand.fluids)<1)then return end
	local tbl,key=table.Random(pool.fluids)
	local t,fld=table.Random(hand.fluids)
	local temp,tv=table.First(t)
	local newkey=tv.name
	if(not newkey or newkey=="" or istable(newkey))then logic.debug("bad fluid transmute"..serpent.block(newkey).."\n--------\n"..serpent.block(t)) return end
	if(newkey==key)then return end
	if(key and tbl)then
		local ctbl=#tbl
		local i=math.random(1,ctbl)
		local v=table.deepcopy(proto.Ingredient(tbl[i]))
		table.remove(tbl,i)
		if(ctbl==1)then pool.fluids[key]=nil end
		local z=(pool.fluidcount[key] or 0)-1
		if(z>0)then pool.fluidcount[key]=z else pool.fluidcount[key]=nil end


		v.name=newkey
		--if(not newkey)then error(serpent.block(tv)) end
		pool.fluids[newkey]=pool.fluids[newkey] or {}
		table.insert(pool.fluids[newkey],v)
		pool.fluidcount[newkey]=table_size(pool.fluids[newkey])
	end	
end

function rando.CountPool()
	local counts={items={},fluids={}}
	local ifv
	local ffv
	for key,c in pairs(pool.itemcount)do counts.items[c]=counts.items[c] or {} counts.items[c][key]=true if(c>=7 and not hand.items[key])then ifv=math.max(ifv or 0,c) end end
	for key,c in pairs(pool.fluidcount)do counts.fluids[c]=counts.fluids[c] or {} counts.fluids[c][key]=true if(c>=7 and not logic.Fluid(key))then ffv=math.max(ffv or 0,c) end end
	return counts,ifv,ffv
end

function logic.HandChanged(src,e)
	if(src=="recipe" and not rando.queued[e.name])then rando.queued[e.name]=true
		if(logic.Ignoring(e))then
			rando.EjectRecipe(e)
			rando.RollRecipe(e)
		else
			local i
			local ejq=table_size(rando.ejectqueue)+1
			if(logic.CanAffordRecipe(e) and logic.CanCraftRecipe(e))then i=math.random(1,math.ceil(ejq/2))
			else i=math.random(math.ceil(ejq*0.75),ejq)
			end
			table.insert(rando.ejectqueue,i,e)
		end
	end
end
local vvv=0

function rando.RollRecipe(rcp) -- If we have enough stuff to roll it (e.g. no duplicates or whatnot)
	if(rando.roll[rcp.name])then return true end

	if(not logic.CanCraftRecipe(rcp))then return false end

	if(not proto.UsedRecipe(rcp.name) or logic.ShouldIgnore(rcp.name,rcp))then

		logic.ScanRecipe(rcp,true)
		logic.ScanEntities()
		rando.roll[rcp.name]=true
		return true
	end

	local ings=proto.Ingredients(rcp) if(not ings)then
		logic.ScanRecipe(rcp,true)
		logic.ScanEntities()
		rando.roll[rcp.name]=true
		return true
	end
	local counts,ifv,ffv=rando.CountPool()

	if(rando.rolls<4)then -- don't infinite loop
	if(ifv)then -- we have 10 or more items of something, let's check if this recipe makes something in there
		for i,rsz in pairs(proto.Results(rcp))do local r=proto.Result(rsz)
			if(r.type=="item" and (not counts.items[ifv][r.name] and (pool.itemcount[r.name] or 0)<(math.ceil(ifv/1.5)) ))then return false end -- no rolls, wait for thing that makes the item in our queue
		end
	elseif(counts.fluids[ffv])then
		for i,rsz in pairs(proto.Results(rcp))do local r=proto.Result(rsz)
			if(r.type=="fluid" and (not counts.fluids[ffv][r.name] and (pool.fluidcount[r.name] or 0)<(math.ceil(ifv/1.5)) ))then return false end
		end
	end
	end

	local new_callback={item={},fluid={}}
	local new_list={item={},fluid={}}
	local new_ings={}

	for k,ving in pairs(ings)do local v=proto.Ingredient(ving)
		local vtp=v.type or "item"
		local pool=(v.type=="fluid" and pool.fluids or pool.items)
		local cs=(v.type=="fluid" and counts.fluids or counts.items)
		local newing,newid
		for rank,vals in table.RankedPairs(cs)do --if table_size(cs)>5 and (rank <=2 or (rank>2 and math.random(1,rank)>math.floor((rank-1)/2)))then
			if(vals)then for pname in RandomPairs(vals)do
				if(((v.type~="fluid" and hand.itemscan[pname]) or (v.type=="fluid" and logic.CanFluid(pname,v.temperature))) and not new_list[v.type or "item"][pname])then
					new_list[v.type or "item"][pname]=true
					if(not pool[pname])then logic.debug(pname) end
					newing,newid=table.Random(pool[pname])
					cs[rank][pname]=nil
					break
				end
			end end
			if(newing and newid)then break end
		end
		if(not newing and not newid)then -- Try to transmute something if we have to.
			return false
		end
		new_callback[vtp][newing[1] or newing.name]=newid
		newing.fluidbox_index=nil
		if(true)then if(newing[2])then newing[2]=(ving[2] or ving.amount) else newing.amount=(ving[2] or ving.amount) end end
		new_ings[k]=newing
	end

	if(rcp.ingredients)then rcp.ingredients=table.deepcopy(new_ings) end
	if(rcp.normal and rcp.normal.ingredients)then rcp.normal.ingredients=table.deepcopy(new_ings) end
	if(rcp.expensive and rcp.expensive.ingredients)then rcp.expensive.ingredients=table.deepcopy(new_ings) end
	for pooltype,tbls in pairs(new_callback)do
		for nm,id in pairs(tbls)do
			table.remove(pool[pooltype.."s"][nm],id)
			local z=table_size(pool[pooltype.."s"][nm])
			pool[pooltype.."count"][nm]=(z==0 and nil or z)
			if(z==0)then pool[pooltype.."s"][nm]=nil pool[pooltype.."count"][nm]=nil end
		end
	end
	logic.ScanRecipe(rcp,true)
	logic.ScanEntities()
	rando.roll[rcp.name]=true
	return true
	
end

rando.rolls=0
rando.last_eject=0
rando.last_roll=0
function rando.WalkAction(iter)
	logic.ScanEntities()

	local dbg=(table_size(rando.roll)==1266)
	if(dbg)then
		--logic.ScanItems()
		--logic.ScanRecipes()
		--logic.ScanTechnologies()
	end

	local rcpmin=settings.startup.randotorio_recipe_min.value
	local rcpmax=settings.startup.randotorio_recipe_max.value
	rcpmax=math.max(rcpmin,rcpmax)
	rcpmin=math.min(rcpmin,rcpmax)
	-- Eject a few random recipes
	for rj=1,math.random(rcpmin,rcpmax)do local k=1 local v=rando.ejectqueue[k] if(not v)then break end
		table.remove(rando.ejectqueue,1)
		if(not rando.EjectRecipe(v))then table.insert(rando.ejectqueue,#rando.ejectqueue+1,v) else rando.rolls=0 end
	end


	local rollmin=settings.startup.randotorio_roll_min.value
	local rollmax=settings.startup.randotorio_roll_max.value
	rollmax=math.max(rollmin,rollmax)
	rollmin=math.min(rollmin,rollmax)
	-- Roll a few recipes
	for rj=1,math.random(rollmin,rollmax)do local k=1 local v=rando.rollqueue[k] if(not v)then break end
		table.remove(rando.rollqueue,1)
		if(not rando.RollRecipe(v))then table.insert(rando.rollqueue,#rando.rollqueue+1,v) else rando.rolls=0 end
	end

	local techmin=settings.startup.randotorio_tech_min.value
	local techmax=settings.startup.randotorio_tech_max.value
	techmax=math.max(techmin,techmax)
	techmin=math.min(techmin,techmax)
	-- Scan a few technologies
	local rj=0 local rm=math.random(techmin,techmax)
	for k,v in RandomPairs(data.raw.technology)do if(rj>=rm)then break end
		if(not hand.techscan[v.name] and logic.CanResearchTechnology(v) and logic.CanAffordTechnology(v))then
			logic.PushTechnology(v) logic.ScanTechnology(v) -- this will raise hand changes to eject & add the recipes to queues
			rj=rj+1
		end
	end

	logic.ScanEntities()
	logic.ScanResources()
	for k,v in pairs(hand.itemscan)do
		if(istable(v))then logic.ScanItem(proto.RawItem(k)) end
	end

	local transmute_rolls=5 --settings.startup.randotorio_transmute_roll.value or 5
	local crash_rolls=transmute_rolls*4
	rando.rolls=rando.rolls+1
	local equal_rolls=(table_size(rando.eject)==rando.last_eject and table_size(rando.roll)==rando.last_roll)
	if(rando.rolls>transmute_rolls and equal_rolls)then
		local counts,ifv,ffv=rando.CountPool()
		if(logic.seablock)then
			rando.TransmuteItems()
			rando.TransmuteFluids()
		else
			if(table_size(counts.items)<=4)then rando.TransmuteItems() end
			if(table_size(counts.fluids)<=4)then rando.TransmuteFluids() end
		end
		--logic.ScanItems()
	end
	if(table_size(pool.items)==0 and table_size(pool.fluids)==0 and equal_rolls and rando.rolls>crash_rolls)then
		--logic.ScanItems()
		if(not logic.HasMoreRecipes())then return false end
		--logic.ScanRecipes()
		logic.debug("out of queue on iter " .. iter)
	end

	rando.last_roll=table_size(rando.roll)
	rando.last_eject=table_size(rando.eject)

end
function rando.WalkCondition(iter)
	if(table_size(hand.techs)==0)then return true end
	for k,v in pairs(hand.recipes)do
		if(rando.queued[k] and (not rando.eject[k] or not rando.roll[k]) and proto.UsedRecipe(k))then return true end
	end

	return false --return logic.HasMoreRecipes() --
end


logic.dbgnames={"ents","items","recipes","fluids","labpacks","techs"}
function logic.debug(s)
	--if(true)then return end
	local dbg={}
	for k,v in pairs(hand)do
		if(table.HasValue(logic.dbgnames,k))then dbg[k]={} for i,e in pairs(v)do dbg[k][i]=true end else dbg[k]=v end
	end

	--logic.ScanTechnologies()
	local techs={}
	local uotech={}
	for k,v in pairs(data.raw.technology)do if(not hand.techscan[v.name])then -- and logic.CanAffordTechnology(v)
		--local fx=proto.TechEffects(v)
		--for x,y in pairs(fx.recipes)do if(y.type=="unlock-recipe" and y.recipe=="lab-2")then table.insert(uotech,v) end end
		--for x,y in pairs(fx.items)do uotech[v.name]=fx.items end

		table.insert(techs,{aname=v.name,ceffects=v.effects,bunit=v.unit})
	end end -- and logic.CanRecursiveAffordTechnology(v)

	local handy={}
	for k,v in pairs(hand.itemscan)do if(istable(v))then handy[k]=v end end

	local misroll,miseject={},{}
	local misused={}
	for k,v in pairs(rando.queued)do if(not rando.roll[k])then misroll[k]=true end if(not rando.eject[k])then miseject[k]=true end end
	for k,v in pairs(misroll)do
		if(proto.UsedRecipe(k))then misused[k]=true end
	end
	local badlabs={}
	local badpacks={}
	for k,v in pairs(data.raw.lab)do for i,e in pairs(v.inputs)do if(not hand.labpacks[e] and not hand.entscan[v.name])then badpacks[e]=true badlabs[v.name]=hand.recipes[v.name] or "NO RECIPE" end end end

	error(tostring(s).."\n"..
	"test:"..serpent.block(hand.techscan["bio-wood-processing"]).."\n"..
	"test2:"..serpent.block(handy).."\n"..

	"---POOL---".."\n"..
	"Itemcount:"..serpent.block(pool.itemcount).."\n"..
	"Fluidcount:"..serpent.block(pool.fluidcount).."\n"..
	--"Labpacks:"..serpent.block(dbg.labpacks).."\n"..
	--"Labslots:"..serpent.block(dbg.labslots).."\n"..
	--"Badlabs:"..serpent.block(badlabs).."\n"..
	--"Badpacks:"..serpent.block(badpacks).."\n"..
	"Misroll:"..serpent.block(misroll).."\n"..
	"MisEject:"..serpent.block(miseject).."\n"..
	"MisUsed:"..serpent.block(misused).."\n"..
	--"--------------TECHS:----------------------"..serpent.block(techs).."\n"..
	"--------------HAND:----------------------"..serpent.block(dbg).."\n"..

	"--------------RANDO:----------------------".."\n"..
	table_size(rando.queued) .. " < Queued | Ejected > " .. table_size(rando.eject) .."\n"..
	table_size(rando.roll) .. " < Rolled |" .. "\n"..
	--"QUEUED:"..serpent.block(rando.queued).."\n"..
	--"EJECTED:"..serpent.block(rando.eject).."\n"..
	--"ROLLED:"..serpent.block(rando.roll).."\n"..
	"EJECT QUEUE:"..serpent.block(rando.ejectqueue).."\n"..
	"ROLL QUEUE:"..serpent.block(rando.rollqueue).."\n"..
	"BIGPOOL:"..serpent.block(pool).."\n"..
	"")

end

function logic.OnItemScanned(item)
	--if(not logic.loading and proto.LabPack(item.name))then rando.ScanTechAutomation(item) end
	if(logic.seablock)then
		if(logic.SeablockScience[item.name])then logic.PushItem(data.raw.tool[logic.SeablockScience[item.name]],1,true) end
	end
end
function rando.EjectHand()
	for nm,rcp in pairs(hand.recipes)do if(not rando.eject[rcp.name])then
		rando.EjectRecipe(rcp)
	end end
end


if(settings.startup.randotorio_spaceblock.value==false)then
	logic.spaceblock=true -- ignore recipes. it's backwards because it makes sense in the menu.
end

--== REWRITE ==--

rando.queued = {}
rando.unaffordable_queued = {}
rando.unaffordable_recipe_queue = {}
rando.recipe_queue = {}
rando.thing_number = {}
rando.thing_cost = {}
rando.thing_automatable = {}
rando.item_selected_times = {}
rando.fluid_selected_times = {}
rando.is_raw_resource = {}
rando.used_one_ingredient_recipes = {}
rando.total_things = 0

function logic.HandChanged(src,e)
	if (src == "recipe" and not rando.queued[e.name]) then
		if (not logic.Ignoring(e)) then
			if (logic.CanAffordRecipe(e) and logic.CanCraftRecipe(e)) then
				rando.queued[e.name] = true
				table.insert(rando.recipe_queue, e)
			else
				if (not rando.unaffordable_queued[e.name]) then
					rando.unaffordable_queued[e.name] = true
					table.insert(rando.unaffordable_recipe_queue, e)
				end
			end
		end
	end
	if ((src == "item" or src == "fluid") and not rando.thing_number[src .. ":" .. e.name]) then
		local thing_id = src .. ":" .. e.name
		if (not rando.thing_cost[thing_id]) then
			rando.is_raw_resource[thing_id] = true
			if (src == "item") then
				rando.thing_cost[thing_id] = 1 -- 1 item = 1 cost
				rando.thing_automatable[thing_id] = false
			else
				rando.thing_cost[thing_id] = 0.05 -- 20 fluid = 1 cost
				rando.thing_automatable[thing_id] = true
			end
		end

		if (src == "item") then
			rando.item_selected_times[e.name] = 0
		else
			rando.fluid_selected_times[e.name] = 0
		end

		rando.total_things = rando.total_things + 1
		rando.thing_number[thing_id] = rando.total_things
	end
end

function rando.BFSStep(iter)
	-- We have the following data:
	--  hand.recipes -> rando.recipe_queue - recipes that are accessible to us
	--  hand.items - craftable items

	log("alive")

	-- Cheat. Better method TBD
	for item, _ in pairs(hand.resource_scan) do
		rando.thing_automatable["item:" .. item] = true
	end

	-- Update lab pack status, because apparently you cannot research anything if you crafted tech packs before placing a lab
	for item, itemdata in pairs(hand.itemscan) do
		if (type(itemdata) == "table" and itemdata.labpack == false and hand.labslots[item]) then
			itemdata.labpack = true 
			logic.PushLabPack(proto.RawItem(item))
		end
	end

	if (table_size(rando.recipe_queue) == 0) then
		for k, e in pairs(rando.unaffordable_recipe_queue) do
			if (not rando.queued[e.name] and logic.CanAffordRecipe(e) and logic.CanCraftRecipe(e)) then
				rando.queued[e.name] = true
				table.insert(rando.recipe_queue, e)
			end
		end

		if (table_size(rando.recipe_queue) == 0) then
			-- logic.debug()
			return true
		end
	end

	-- Pick a random recipe.
	local recipe_id = math.random(1, table_size(rando.recipe_queue))
	local rcp = rando.recipe_queue[recipe_id]
	table.remove(rando.recipe_queue, recipe_id)

	-- Determine if the recipe result is usually automatable
	local is_automatable = true
	local ings = proto.Ingredients(rcp)
	for k, v in pairs(ings) do
		local ing = proto.Ingredient(v)
		if (not rando.thing_automatable[ing.type .. ":" .. ing.name]) then
			is_automatable = false
		end
	end

	rando.used_one_ingredient_recipes[rcp.category or "crafting"] = rando.used_one_ingredient_recipes[rcp.category or "crafting"] or {}

	-- Calculate base cost of a recipe
	local base_cost = 0
	for k, v in pairs(ings) do
		local ing = proto.Ingredient(v)
		base_cost = base_cost + rando.thing_cost[ing.type .. ":" .. ing.name] * ing.amount
	end

	-- Collect items/fluids with their weights
	local weights = {item = {}, fluid = {}}
	local weight_sum = {item = 0, fluid = 0}

	for _, cat in pairs({"item", "fluid"}) do
		for v, x in pairs(hand[cat .. "s"]) do
			-- If the recipe is automatable but item is not, don't include it
			if (not (is_automatable and not rando.thing_automatable[cat .. ":" .. v])) then
				-- If the recipe is one-ingredient and the item is already used as one, don't include it
				if (not (table_size(ings) == 1 and rando.used_one_ingredient_recipes[rcp.category or "crafting"][cat .. ":" .. v])) then
					-- If the item is too expensive, ignore it
					if (rando.thing_cost[cat .. ":" .. v] <= base_cost) then
						weights[cat][v] = 3 + rando[cat .. "_selected_times"][v]
						-- If the item is a raw resource, ignore this
						if (rando.is_raw_resource[cat .. ":" .. v]) then
							weights[cat][v] = 1
						end

						weight_sum[cat] = weight_sum[cat] + weights[cat][v]
					end
				end
			end
		end
	end

	-- Check that we actually have enough items to randomize
	local recipe_ings = {item = 0, fluid = 0}

	for k, v in pairs(ings) do
		local ing = proto.Ingredient(v)
		recipe_ings[ing.type] = recipe_ings[ing.type] + 1
	end

	if (recipe_ings.item <= table_size(weights.item) and recipe_ings.fluid <= table_size(weights.fluid)) then
		-- Randomize the recipe
		local new_ings = {}
		for k, v in pairs(ings) do
			local ing = proto.Ingredient(v)
			local wrand = math.random(1, weight_sum[ing.type])
			local picked_ing = nil
			for elem, wt in pairs(weights[ing.type]) do
				if (wt) then
					wrand = wrand - wt
					if (wrand <= 0) then
						picked_ing = elem
						weight_sum[ing.type] = weight_sum[ing.type] - wt
						weights[ing.type][picked_ing] = nil
						break
					end
				end
			end
			local new_ing = table.deepcopy(ing)
			new_ing.name = picked_ing
			-- Reduce count a bit
			new_ing.amount = math.min(new_ing.amount, math.max(1, math.ceil(base_cost / rando.thing_cost[new_ing.type .. ":" .. new_ing.name])))
			table.insert(new_ings, new_ing)
		end

		-- Check if this recipe would be automatable
		is_automatable = true
		for k, ing in pairs(new_ings) do
			if (not rando.thing_automatable[ing.type .. ":" .. ing.name]) then
				is_automatable = false
			end
		end

		-- Calculate the current cost of a recipe
		local current_cost = 0
		for k, ing in pairs(new_ings) do
			current_cost = current_cost + rando.thing_cost[ing.type .. ":" .. ing.name] * ing.amount
		end

		local crafting_time_multiplier = current_cost / base_cost

		-- Modify result count based on base_cost and current_cost (result is between 1 and stack size)
		local new_results = {}
		for k, v in pairs(proto.Results(rcp)) do
			local res = proto.Result(v)
			local new_res = table.deepcopy(res)
			if (base_cost > 0 and current_cost > 0) then
				-- Get item stack size
				local stack_size = 10000
				if ((res.type or "item") == "item") then
					local item = proto.RawItem(res.name)
					if item then
						stack_size = item.stack_size
					end
				end
				for _, key in pairs({"amount", "amount_min", "amount_max"}) do
					if (new_res[key] and new_res[key] > 0) then
						local new_result = math.max(1, math.min(stack_size, math.floor(new_res[key] * current_cost / base_cost + 0.5)))
						crafting_time_multiplier = math.min(crafting_time_multiplier, new_result / new_res[key])
						new_res[key] = new_result
					end
				end
			end
			table.insert(new_results, new_res)
		end

		-- Rewrite stuff
		if (rcp.ingredients) then
			rcp.ingredients = table.deepcopy(new_ings)
		end
		if (rcp.result) then
			rcp.result = new_results[1].name
			rcp.result_count = new_results[1].amount
		end
		if (rcp.results) then
			rcp.results = table.deepcopy(new_results)
		end
		rcp.energy_required = math.max(1, math.min(100000, math.floor((rcp.energy_required or 0.5) * crafting_time_multiplier * 10 + 0.5))) / 10.0

		if (rcp.normal) then
			if (rcp.normal.ingredients) then
				rcp.normal.ingredients = table.deepcopy(new_ings)
			end
			if (rcp.normal.result) then
				rcp.normal.result = new_results[1].name
				rcp.normal.result_count = new_results[1].amount
			end
			if (rcp.normal.results) then
				rcp.normal.results = table.deepcopy(new_results)
			end
			rcp.normal.energy_required = math.floor((rcp.normal.energy_required or 0.5) * current_cost / base_cost * 10 + 0.5) / 10.0
		end

		if (rcp.expensive) then
			if (rcp.expensive.ingredients) then
				rcp.expensive.ingredients = table.deepcopy(new_ings)
			end
			if (rcp.expensive.result) then
				rcp.expensive.result = new_results[1].name
				rcp.expensive.result_count = new_results[1].amount
			end
			if (rcp.expensive.results) then
				rcp.expensive.results = table.deepcopy(new_results)
			end
			rcp.expensive.energy_required = math.floor((rcp.expensive.energy_required or 0.5) * current_cost / base_cost * 10 + 0.5) / 10.0
		end

		base_cost = current_cost

		log("Randomized recipe " .. rcp.name .. ".")
		log("New ingredients:")
		for k, ing in pairs(proto.Ingredients(rcp)) do
			log("  " .. ing.type .. ":" .. ing.name .. " - " .. ing.amount)
		end	
		if (is_automatable) then
			log("Automatable")
		end
		log("")
	end

	-- Update ingredient participation
	for k, v in pairs(proto.Ingredients(rcp)) do
		local ing = proto.Ingredient(v)
		rando[ing.type .. "_selected_times"][ing.name] = (rando[ing.type .. "_selected_times"][ing.name] or 0) + 1
		if (recipe_ings.item + recipe_ings.fluid == 1) then
			rando.used_one_ingredient_recipes[rcp.category or "crafting"][ing.type .. ":" .. ing.name] = true
		end
	end

	-- Update result costs
	for k, v in pairs(proto.Results(rcp)) do
		local res = proto.Result(v)
		local res_amt = res.amount
		if (not res_amt) then
			res_amt = (res.amount_min + res.amount_max) / 2.0
		end
		if (res.probability) then
			res_amt = res_amt * res.probability
		end

		local res_id = (res.type or "item") .. ":" .. res.name

		if (rando.thing_cost[res_id] == nil) then
			rando.thing_cost[res_id] = base_cost / res_amt
		end
		if (rando.thing_automatable[res_id] == nil) then
			rando.thing_automatable[res_id] = is_automatable
		end

		if (is_automatable and not rando.thing_automatable[res_id]) then
			rando.thing_automatable[res_id] = true
			rando.thing_cost[res_id] = base_cost / res_amt
		end
		if ((is_automatable or not rando.thing_automatable[res_id]) and base_cost / res_amt < rando.thing_cost[res_id]) then
			rando.thing_cost[res_id] = base_cost / res_amt
		end
	end

	logic.ScanRecipe(rcp, true)

	-- Scan cycle
	logic.ScanTechnologies()
	logic.ScanEntities()
	logic.ScanResources()

	-- Also unlock technologies manually, because it only checks hand
	for k,v in pairs(data.raw.technology) do
		if(not hand.techscan[v.name] and logic.CanResearchTechnology(v) and logic.CanAffordTechnology(v))then
			logic.PushTechnology(v) logic.ScanTechnology(v)
		end
	end

	-- Check waiting recipe availability
	for k, e in pairs(rando.unaffordable_recipe_queue) do
		if (not rando.queued[e.name] and logic.CanAffordRecipe(e) and logic.CanCraftRecipe(e)) then
			rando.queued[e.name] = true
			table.insert(rando.recipe_queue, e)
		end
	end
end

--== END REWRITE ==--

function rando.InitLogic()
	if(mods["SeaBlock"])then logic.Seablock() end
	logic.lua()
	rando.EjectHand()
	logic.ScanTechnologies()
	--logic.ScanItems()
	logic.ScanEntities()
	logic.ScanResources()
	--rando.EjectHand()
	logic.loading=false
end
rando.InitLogic()

-- logic.Walk(rando.WalkCondition,rando.WalkAction,4000)
logic.Walk(rando.WalkCondition,rando.BFSStep,40000)


--logic.debug("Roll Finished")



lib.lua()