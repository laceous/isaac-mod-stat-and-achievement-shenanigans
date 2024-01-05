local mod = RegisterMod('Stat and Achievement Shenanigans', 1)

if REPENTOGON then
  function mod:onSaveSlotLoad()
    mod:RemoveCallback(ModCallbacks.MC_POST_SAVESLOT_LOAD, mod.onSaveSlotLoad)
    mod:setupImGui()
  end
  
  -- REPENTOGON enums tend to have multiple keys per value
  function mod:getKeys(val, tbl)
    local keys = {}
    
    for k, v in pairs(tbl) do
      if v == val then
        table.insert(keys, k)
      end
    end
    
    -- sort CHALLENGE_ keys to the front
    table.sort(keys, function(a, b)
      if string.find(string.upper(a), '^CHALLENGE_') ~= nil then
        return true
      elseif string.find(string.upper(b), '^CHALLENGE_') ~= nil then
        return false
      end
      
      return a < b
    end)
    
    return keys
  end
  
  function mod:isProgressionStat(keys)
    for _, key in ipairs(keys) do
      if string.find(string.upper(key), '^PROGRESSION_') ~= nil then
        return true
      end
    end
    
    return false
  end
  
  function mod:setupImGui()
    if not ImGui.ElementExists('shenanigansMenu') then
      ImGui.CreateMenu('shenanigansMenu', '\u{f6d1} Shenanigans')
    end
    ImGui.AddElement('shenanigansMenu', 'shenanigansMenuItemStats', ImGuiElement.MenuItem, '\u{e473} Stat and Achievement Shenanigans')
    ImGui.CreateWindow('shenanigansWindowStats', 'Stat and Achievement Shenanigans')
    ImGui.LinkWindowToElement('shenanigansWindowStats', 'shenanigansMenuItemStats')
    
    ImGui.AddTabBar('shenanigansWindowStats', 'shenanigansTabBarStats')
    ImGui.AddTab('shenanigansTabBarStats', 'shenanigansTabStats', 'Stats')
    ImGui.AddTab('shenanigansTabBarStats', 'shenanigansTabAchievements', 'Achievements')
    
    -- 0 is NULL
    -- 19 and 403 don't exist in the enum
    for stat = 1, EventCounter.NUM_EVENT_COUNTERS - 1 do
      local keys = mod:getKeys(stat, EventCounter)
      if #keys > 0 then
        local isProgressionStat = mod:isProgressionStat(keys)
        local intStatId = 'shenanigansIntStat' .. stat
        local intStatText = stat .. '.' .. table.remove(keys, 1)
        local intStatTooltip = isProgressionStat and intStatText .. ' (0=Off,1=Normal,2=Hard)' or intStatText
        ImGui.AddInputInteger('shenanigansTabStats', intStatId, intStatText, nil, 0, 1, 100)
        ImGui.SetTooltip(intStatId, intStatTooltip)
        if #keys > 0 then
          ImGui.SetHelpmarker(intStatId, table.concat(keys, ', '))
        end
        ImGui.AddCallback(intStatId, ImGuiCallback.Render, function()
          local gameData = Isaac.GetPersistentGameData()
          ImGui.UpdateData(intStatId, ImGuiData.Value, gameData:GetEventCounter(stat))
        end)
        ImGui.AddCallback(intStatId, ImGuiCallback.Edited, function(num)
          local gameData = Isaac.GetPersistentGameData()
          gameData:IncreaseEventCounter(stat, num - gameData:GetEventCounter(stat))
        end)
      end
    end
    
    for achievement = 1, Achievement.DEAD_GOD do
      local keys = mod:getKeys(achievement, Achievement)
      if #keys > 0 then
        local chkAchievementId = 'shenanigansChkAchievement' .. achievement
        ImGui.AddCheckbox('shenanigansTabAchievements', chkAchievementId, achievement .. '.' .. table.remove(keys, 1), nil, false)
        if #keys > 0 then
          ImGui.SetHelpmarker(chkAchievementId, table.concat(keys, ', '))
        end
        ImGui.AddCallback(chkAchievementId, ImGuiCallback.Render, function()
          local gameData = Isaac.GetPersistentGameData()
          ImGui.UpdateData(chkAchievementId, ImGuiData.Value, gameData:Unlocked(achievement))
        end)
        ImGui.AddCallback(chkAchievementId, ImGuiCallback.Edited, function(b)
          local gameData = Isaac.GetPersistentGameData()
          if b then
            gameData:TryUnlock(achievement) -- Isaac.ExecuteCommand('achievement ' .. achievement)
          else
            Isaac.ExecuteCommand('lockachievement ' .. achievement)
          end
        end)
      end
    end
  end
  
  mod:AddCallback(ModCallbacks.MC_POST_SAVESLOT_LOAD, mod.onSaveSlotLoad)
end