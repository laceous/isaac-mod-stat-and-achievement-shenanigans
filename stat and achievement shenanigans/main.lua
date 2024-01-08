local mod = RegisterMod('Stat and Achievement Shenanigans', 1)
local json = require('json')

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
  
  -- exclude modded characters
  function mod:isCharacterAchievement(achievement)
    for i = 0, PlayerType.NUM_PLAYER_TYPES - 1 do
      local playerConfig = EntityConfig.GetPlayer(i)
      if playerConfig:GetAchievementID() == achievement then
        return true
      end
    end
    
    return false
  end
  
  function mod:processImportedJson(s)
    local gameData = Isaac.GetPersistentGameData()
    local _, data = pcall(json.decode, s)
    
    if type(data) == 'table' then
      if type(data.stats) == 'table' then
        for k, v in pairs(data.stats) do
          local stat = nil
          if type(k) == 'string' then
            stat = tonumber(string.match(k, '^(%d+)'))
          end
          if math.type(stat) == 'integer' and math.type(v) == 'integer' and stat >= 1 and stat <= EventCounter.NUM_EVENT_COUNTERS - 1 and v >= 0 then
            gameData:IncreaseEventCounter(stat, v - gameData:GetEventCounter(stat))
          end
        end
      end
      if type(data.achievements) == 'table' then
        for k, v in pairs(data.achievements) do
          local achievement = nil
          if type(k) == 'string' then
            achievement = tonumber(string.match(k, '^(%d+)'))
          end
          if math.type(achievement) == 'integer' and type(v) == 'boolean' and achievement >= 1 and achievement <= Achievement.DEAD_GOD then
            if v then
              gameData:TryUnlock(achievement)
            else
              Isaac.ExecuteCommand('lockachievement ' .. achievement)
            end
          end
        end
      end
    end
  end
  
  -- the json library doesn't have pretty print so custom output our json
  function mod:getJsonExport(inclProgressionStats, inclOtherStats, inclCharacterAchievements, inclOtherAchievements)
    local gameData = Isaac.GetPersistentGameData()
    local s = '{'
    
    s = s .. '\n  "stats": {'
    local hasAtLeastOneStat = false
    for stat = 1, EventCounter.NUM_EVENT_COUNTERS - 1 do
      local keys = mod:getKeys(stat, EventCounter)
      if #keys > 0 then
        local isProgressionStat = mod:isProgressionStat(keys)
        if (isProgressionStat and inclProgressionStats) or (not isProgressionStat and inclOtherStats) then
          s = s .. '\n    ' .. json.encode(stat .. '-' .. keys[1]) .. ': ' .. gameData:GetEventCounter(stat) .. ','
          hasAtLeastOneStat = true
        end
      end
    end
    if hasAtLeastOneStat then
      s = string.sub(s, 1, -2) -- strip last comma
    end
    s = s .. '\n  },'
    
    s = s .. '\n  "achievements": {'
    local hasAtLeastOneAchievement = false
    for achievement = 1, Achievement.DEAD_GOD do
      local keys = mod:getKeys(achievement, Achievement)
      if #keys > 0 then
        local isCharacterAchievement = mod:isCharacterAchievement(achievement)
        if (isCharacterAchievement and inclCharacterAchievements) or (not isCharacterAchievement and inclOtherAchievements) then
          s = s .. '\n    ' .. json.encode(achievement .. '-' .. keys[1]) .. ': ' .. tostring(gameData:Unlocked(achievement)) .. ','
          hasAtLeastOneAchievement = true
        end
      end
    end
    if hasAtLeastOneAchievement then
      s = string.sub(s, 1, -2)
    end
    s = s .. '\n  }'
    
    s = s .. '\n}'
    return s
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
    ImGui.AddTab('shenanigansTabBarStats', 'shenanigansTabStatsImportExport', 'Import/Export')
    
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
          if b then
            local gameData = Isaac.GetPersistentGameData()
            gameData:TryUnlock(achievement) -- Isaac.ExecuteCommand('achievement ' .. achievement)
          else
            Isaac.ExecuteCommand('lockachievement ' .. achievement)
          end
        end)
      end
    end
    
    local importText = ''
    ImGui.AddElement('shenanigansTabStatsImportExport', '', ImGuiElement.SeparatorText, 'Import')
    ImGui.AddText('shenanigansTabStatsImportExport', 'Paste JSON here:', false, '')
    ImGui.AddInputTextMultiline('shenanigansTabStatsImportExport', 'shenanigansTxtStatsImport', '', function(txt)
      importText = txt
    end, importText, 12)
    for i, v in ipairs({
                        { text = 'Cut'        , func = function()
                                                         Isaac.SetClipboard(importText)
                                                         ImGui.UpdateData('shenanigansTxtStatsImport', ImGuiData.Value, '')
                                                         importText = ''
                                                       end },
                        { text = 'Copy'       , func = function()
                                                         Isaac.SetClipboard(importText)
                                                       end },
                        { text = 'Paste'      , func = function()
                                                         local clipboard = Isaac.GetClipboard()
                                                         if clipboard then
                                                           ImGui.UpdateData('shenanigansTxtStatsImport', ImGuiData.Value, clipboard)
                                                           importText = clipboard
                                                         end
                                                       end },
                        { text = 'Import JSON', func = function()
                                                         mod:processImportedJson(importText)
                                                       end },
                      })
    do
      ImGui.AddButton('shenanigansTabStatsImportExport', 'shenanigansBtnStatsImport' .. i, v.text, v.func, false)
      if i < 4 then
        ImGui.AddElement('shenanigansTabStatsImportExport', '', ImGuiElement.SameLine, '')
      end
    end
    
    local exportBooleans = {
      progressionStats = true,
      otherStats = true,
      characterAchievements = true,
      otherAchievements = true,
    }
    ImGui.AddElement('shenanigansTabStatsImportExport', '', ImGuiElement.SeparatorText, 'Export')
    for i, v in ipairs({
                        { text = 'Export progression stats?'     , exportBoolean = 'progressionStats'     , helpText = 'Completion marks' },
                        { text = 'Export other stats?'           , exportBoolean = 'otherStats' },
                        { text = 'Export character achievements?', exportBoolean = 'characterAchievements', helpText = 'Character unlocks' },
                        { text = 'Export other achievements?'    , exportBoolean = 'otherAchievements' },
                      })
    do
      local chkStatsExportId = 'shenanigansChkStatsExport' .. i
      ImGui.AddCheckbox('shenanigansTabStatsImportExport', chkStatsExportId, v.text, function(b)
        exportBooleans[v.exportBoolean] = b
      end, exportBooleans[v.exportBoolean])
      if v.helpText then
        ImGui.SetHelpmarker(chkStatsExportId, v.helpText)
      end
    end
    ImGui.AddButton('shenanigansTabStatsImportExport', 'shenanigansBtnStatsExport', 'Copy JSON to clipboard', function()
      Isaac.SetClipboard(mod:getJsonExport(exportBooleans.progressionStats, exportBooleans.otherStats, exportBooleans.characterAchievements, exportBooleans.otherAchievements))
    end, false)
  end
  
  mod:AddCallback(ModCallbacks.MC_POST_SAVESLOT_LOAD, mod.onSaveSlotLoad)
end