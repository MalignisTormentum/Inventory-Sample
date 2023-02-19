local inventory = game.ReplicatedStorage.GetInventory:InvokeServer()

local function get_item(item_name : string) -- Returns an item in replicated storage sharing the name passed to the function, or nil if it doesn't exist.
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

-- Renders the face or accessory in a GuiObject and returns the GuiObject.
local function render_item(item : Instance, parent_frame : Frame)
	if item:IsA('Decal') then
		local image_button = parent_frame.ImageButton:Clone()
		image_button.Parent = parent_frame
		image_button.Image = item.Texture
		image_button.Visible = true
		image_button.TextLabel.Text = item.Name
		image_button.Name = item.Name
		
		image_button.MouseEnter:Connect(function() 
			script.Parent.mouse_hover:Play() 
		end)
		
		return image_button
	end
	
	if item:IsA('Accessory') then
		local handle = item:FindFirstChild('Handle')
		if handle then
			local image_button = parent_frame.ImageButton:Clone()			
			local vpf = parent_frame.ViewportFrame:Clone()
			
			item.Parent = vpf
			handle:PivotTo(CFrame.new(0, 0, 0) * CFrame.Angles(0, math.rad(90), 0))
			
			local cam = Instance.new('Camera', vpf)
			cam.CFrame = CFrame.new(handle.Position - Vector3.new(3, 0, 0), handle.Position)
			
			vpf.CurrentCamera = cam
			vpf.Visible = true
			vpf.Parent = image_button
			
			image_button.Parent = parent_frame
			image_button.Visible = true
			image_button.TextLabel.Text = item.Name
			image_button.Name = item.Name
			
			image_button.MouseEnter:Connect(function()
				script.Parent.mouse_hover:Play() 
			end)
			
			return image_button
		end
	end
end

-- Handles teh search functions for both the shop and the inventory UIs to make access to an item quicker.
-- Also handles the exit button on the respective UI.
for _, n in pairs({'Inventory', 'Shop'}) do
	script.Parent[n].Search.Bar:GetPropertyChangedSignal('Text'):Connect(function()
		local text = script.Parent[n].Search.Bar.Text

		for _, v in pairs(script.Parent[n].Scroll:GetChildren()) do
			if v:IsA('GuiObject') and v.Name ~='ImageButton' and v.Name ~= 'ViewportFrame' and v.Name ~= 'Clear' then
				if string.find(v.TextLabel.Text:lower(), text:lower()) then
					v.Visible = true
				else
					v.Visible = false
				end
			end
		end
	end)
	
	script.Parent[n].MainBG.ExitButton.MouseButton1Down:Connect(function()
		script.Parent.mouse_click:Play()
		script.Parent[n].Visible = false
	end)
end

-- Apply open affects to the HUD buttons. Makes the inventory and shop UIs visible.
for _, v in pairs(script.Parent.HUD:GetChildren()) do
	if v:IsA('GuiButton') then
		v.MouseEnter:Connect(function()
			script.Parent.mouse_hover:Play() 
		end)
		v.MouseButton1Down:Connect(function()
			script.Parent.mouse_click:Play()
			
			local frame = script.Parent:FindFirstChild(v.Name)
			if not frame or frame.Visible then return end
			
			for _, x in pairs(script.Parent:GetChildren()) do
				if x:IsA('Frame') and x.Name ~= 'HUD' then
					x.Visible = false
				end
			end
			
			if frame then
				frame.Position = UDim2.new(2, 0, .5, 0)
				frame.Visible = true
				frame:TweenPosition(UDim2.new(.5, 0, .5, 0), Enum.EasingDirection.Out, Enum.EasingStyle.Back, 1, false)
			end
		end)
	end
end

-- Check with the server to see if the player owns any items. If they do, render them in the inventory. When the buttons are clicked, a
-- request is made to the server to apply the item.
if inventory then
	for _, v in pairs(inventory) do
		local item = get_item(v)
		if item then
			item = item:Clone()
			local button = render_item(item, script.Parent.Inventory.Scroll)
			button.MouseButton1Down:Connect(function()
				script.Parent.mouse_click:Play()
				game.ReplicatedStorage.EquipAsset:FireServer(item.Name)
			end)
		end
	end
end

-- Create a button to clear a player's currently worn accessories.
local clear_button = script.Parent.Inventory.Scroll.ImageButton:Clone()
clear_button.Parent = script.Parent.Inventory.Scroll
clear_button.Visible = true
clear_button.Name = 'Clear'
clear_button.TextLabel.Text = 'Remove Accessories'

clear_button.MouseEnter:Connect(function()
	script.Parent.mouse_hover:Play() 
end)

clear_button.MouseButton1Down:Connect(function()
	script.Parent.mouse_click:Play()
	game.ReplicatedStorage.RemoveAsset:FireServer()
end)

-- For every item a player does not own, render it in the shop and give it a price. When the item is clicked in the shop,
-- make a request to the server to buy the item. If successful, add to the inventory UI and remove the item from the shop.
for _, folder in pairs({game.ReplicatedStorage.Faces, game.ReplicatedStorage.Accessories}) do
	for _, v in pairs(folder:GetChildren()) do
		if not table.find(inventory, v.Name) then
			local item = v:Clone()
			local button = render_item(item, script.Parent.Shop.Scroll)
			
			button.TextLabel.Text = button.TextLabel.Text .. ' (' .. (item:GetAttribute('Price') or 0) .. 'g)'
			
			button.MouseButton1Down:Connect(function()
				script.Parent.mouse_click:Play()
				local res = game.ReplicatedStorage.PurchaseAsset:InvokeServer(item.Name)
				
				if res.OK then
					local new_button = render_item(item:Clone(), script.Parent.Inventory.Scroll)
					
					new_button.MouseButton1Down:Connect(function()
						script.Parent.mouse_click:Play()
						game.ReplicatedStorage.EquipAsset:FireServer(item.Name)
					end)
					
					button:Destroy()
				end
			end)
		end
	end
end
