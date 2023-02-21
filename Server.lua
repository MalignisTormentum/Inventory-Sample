local accessories = { -- A premade table of accesory IDs for the demo.
	64082730, 52458643, 48545806, 1180419124, 439946249,
	11748356, 1235488, 1365767, 26019070, 2222720521, 
	1073690, 121389847, 4390888537, 128992838, 494291269
}

local MPS = game:GetService('MarketplaceService') -- Get services and store references to them as variables.
local IS = game:GetService('InsertService')
local DSS = game:GetService('DataStoreService')
local MS = game:GetService('MessagingService')

local DS = DSS:GetDataStore('PlayerInventory') -- Get the player inventory store via the DataStoreService.
local AS = DSS:GetDataStore('AssetStore') -- Holds all asset information not available through GetProductInfo().

local server_data = {} -- Writing to the datastore every time a sale is made is bad practice, so we use a table to hold the data while the player is in the server instead.
local asset_data = {}

local function get_item(item_name : string) -- Searches for an item with the passed name in ReplicatedStorage. If found, returns it. Else returns nil.
	for _, v in pairs(game.ReplicatedStorage:GetChildren()) do
		if v:IsA('Folder') then
			for _, item in pairs(v:GetChildren()) do
				if item.Name == item_name then
					return item
				end
			end
		end
	end
	return nil
end

-- Runs when the game is loaded for the first time. Later runs can establish new inventory through external tools or manually.
-- Uses the IS and MPS to get the names and prices for all accessories in the demo, and insert them into ReplicatedStorage
-- Where both the client and the server can access them; the client renders them in ViewportFrames.
local function init_assets()
	for _, v in pairs(accessories) do 
		coroutine.wrap(function()
			local item_info = MPS:GetProductInfo(v)
			local item_model = IS:LoadAsset(v)

			for _, x in pairs(item_model:GetChildren()) do

				if x:IsA('Accessory') then
					x.Parent = game.ReplicatedStorage.Accessories
					x.Name = item_info.Name
				end

				if x:IsA('Decal') then
					x.Parent = game.ReplicatedStorage.Faces
					x.Name = item_info.Name
				end

				x:SetAttribute('Price', item_info.PriceInRobux or 1250)
				
				asset_data[item_info.Name] = {
					Owners = {}, 
					ID = v, 
					Price = item_info.PriceInRobux or 1250
				}
			end
		end)()
	end
	AS:SetAsync('ASSETS', asset_data)
end

-- For subsequent runs of the game, or when new assets are added.
local function load_assets(assets : table)
	for i, v in pairs(assets) do
		local item_model = IS:LoadAsset(v.ID)
		for _, x in pairs(item_model:GetChildren()) do

			if x:IsA('Accessory') then
				x.Parent = game.ReplicatedStorage.Accessories
				x.Name = i
			end

			if x:IsA('Decal') then
				x.Parent = game.ReplicatedStorage.Faces
				x.Name = i
			end

			x:SetAttribute('Price', v.PriceInRobux)
		end
	end
end

-- Attempt to get available asset information.
local s, assets = pcall(function()
	return AS:GetAsync('ASSETS')
end)

if s then
	if assets then
		load_assets(assets)
	else
		init_assets()
	end
else
	init_assets()
end


game.Players.PlayerAdded:Connect(function(plr : Player) -- Event fires when a player joins.
	local key = 'Player_' .. plr.UserId
	
	local s, d = pcall(function() -- Get the player's stored data.
		return DS:GetAsync(key)
	end)
	
	if s then -- If successful, if it exists, add it to the server data table. If it doesn't exist, create a default player data table.
		if d then
			server_data[key] = d
		else
			server_data[key] = {Gold = 100000, Sales = 0, Inventory = {}}
		end
	end
	
	local leaderstats = Instance.new('Folder', plr) -- Create the leaderboard to show how many items a player has bought and how much gold they have.
	leaderstats.Name = 'leaderstats'
	
	local gold = Instance.new('IntValue', leaderstats)
	gold.Name = 'Gold'
	gold.Value = server_data[key].Gold or 0
	
	local sales = Instance.new('IntValue', leaderstats)
	sales.Name = 'Sales'
	sales.Value = server_data[key].Sales or 0
end)

game.Players.PlayerRemoving:Connect(function(plr : Player) -- Fires when the player leaves the server.
	local key = 'Player_' .. plr.UserId
	local count = 0
	
	while count < 5 do -- Makes five attempts to set the player's data.
		local s, d = pcall(function()
			DS:SetAsync(key, server_data[key])
		end)
		
		if s then
			server_data[key] = nil -- If the data has been set to the datastore successfully then remove the player's data from the temp server data table.
			break
		else
			task.wait(1)
			count += 1
		end
	end
end)

-- Removes all accessories a player may be wearing.
game.ReplicatedStorage.RemoveAsset.OnServerEvent:Connect(function(plr : Player)
	if not plr.Character then 
		return 
	end
	
	for _, v in pairs(plr.Character:GetChildren()) do
		if v:IsA('Accessory') then v:Destroy() end
	end
end)

-- Returns all the items a player owns.
game.ReplicatedStorage.GetInventory.OnServerInvoke = function(plr : Player)
	local key = 'Player_' .. plr.UserId
	
	repeat 
		task.wait() 
	until 
	server_data[key]
	
	return server_data[key].Inventory
end

-- When a player makes a purchase, check to see if item exists (sanity check). If it does, and the player has enough gold,
-- add the item to their inventory, and update their leaderstats and server data.
game.ReplicatedStorage.PurchaseAsset.OnServerInvoke = function(plr : Player, item_name : string)
	local item = get_item(item_name)
	local key = 'Player_' .. plr.UserId

	if item then
		local price = item:GetAttribute('Price') or 0
		if server_data[key].Gold >= price then
			plr.leaderstats.Gold.Value -= price
			plr.leaderstats.Sales.Value += 1
			
			table.insert(server_data[key].Inventory, item_name)
			
			server_data[key].Gold -= price
			server_data[key].Sales += 1
			
			return {OK = true}
		end
	end
	
	return {OK = false}
end

-- Checks to see if requested item exists (sanity check). If it does and the player is already wearing it, remove it from the player and end there.
-- If it doesn't, check to see that they have no more than eight accessories on and add the item if they don't. Faces update the current face texture, whereas
-- accessories are cloned and parented to the player's character.

-- If the item is a gear, it has the player unequip all tools and checks to see if they have the gear already. If they do, it destroys it and returns. 
-- If they don't, it gets cloned to their backpack.

game.ReplicatedStorage.EquipAsset.OnServerEvent:Connect(function(plr : Player, item_name : string)
	local item = get_item(item_name)
	if item then
		if item:IsA('Gear') then
			local hum = plr.Character:WaitForChild('Humanoid')
			hum:UnequipTools()
			
			local existing_item = plr.Backpack:FindFirstChild(item_name)
			
			if existing_item then
				existing_item:Destroy()
				return
			else
				item = item:Clone()
				item.Parent = plr.Backpack
			end
		else
			local existing = plr.Character:FindFirstChild(item_name)

			if existing then 
				existing:Destroy()
				return
			else
				local count = 0

				for _, v in pairs(plr.Character:GetChildren()) do
					if v:IsA('Accessory') then
						count += 1
					end
				end

				if count < 8 then
					if item:IsA('Accessory') then
						item = item:Clone()
						item.Parent = plr.Character

					elseif item:IsA('Decal') then
						local head = plr.Character:FindFirstChild('Head')
						
						if head then
							local face = head:FindFirstChildOfClass('Decal')

							if face then 
								face.Texture = item.Texture 
							end
						end
					end
				end
			end
		end
	end
end)

-- This is where the game listens for new assets being created from external tools. It also utilizes a request variable to perform different tasks.

MS:SubscribeAsync('EXTERNAL_RESPONDER', function(t : table)
	local data = t.Data
	if type(data) == 'table' then
		if data.Request then
			if data.Request == 'KICK_PLAYER' then
				local ID = data.ID
				local message = data.Message
				
				if ID and message then
					for _, plr in pairs(game.Players:GetPlayers()) do
						if plr.UserId == data.ID then
							plr:Kick(message)
							break
						end
					end
				end
			end
			
			if data.Request == 'ADD_ITEM' then
				local new_asset_data = data.AssetData
				if asset_data then
					load_assets(new_asset_data) 
				end
			end
		end
	end
end)
