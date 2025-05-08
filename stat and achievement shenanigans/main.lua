local mod = RegisterMod('Stat and Achievement Shenanigans', 1)
local json = require('json')

if REPENTOGON then
  mod.maxAchievement = REPENTANCE_PLUS and Achievement.WON_ONLINE_DAILY or Achievement.DEAD_GOD -- 640 or 637
  
  function mod:onModsLoaded()
    mod:setupImGui()
  end
  
  -- REPENTOGON enums tend to have multiple keys per value
  function mod:getKeys(tbl, val)
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
  
  function mod:hasKey(tbl, key)
    for _, v in pairs(tbl) do
      if v.key == key then
        return true
      end
    end
    
    return false
  end
  
  function mod:isProgressionStat(keys)
    for _, key in pairs(keys) do
      key = string.upper(key)
      if string.find(key, '^PROGRESSION_') ~= nil or
         string.find(key, '^%d+%.PROGRESSION_') ~= nil
      then
        return true
      end
    end
    
    return false
  end
  
  function mod:tblSearch(tbl, s)
    s = string.lower(s)
    for _, v in pairs(tbl) do
      if string.find(string.lower(v), s, 1, true) then
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
  
  function mod:getXmlMaxAchievementId()
    local id = mod.maxAchievement + 1
    local entry = XMLData.GetEntryById(XMLNode.ACHIEVEMENT, id)
    while entry and type(entry) == 'table' do
      id = id + 1
      entry = XMLData.GetEntryById(XMLNode.ACHIEVEMENT, id)
    end
    
    return id - 1
  end
  
  function mod:getXmlAchievementId(nameAndSourceId)
    local id = mod.maxAchievement + 1
    local entry = XMLData.GetEntryById(XMLNode.ACHIEVEMENT, id)
    while entry and type(entry) == 'table' do
      if entry.id and entry.id ~= '' and entry.name and entry.name ~= '' and entry.sourceid and entry.sourceid ~= '' then
        if entry.name .. entry.sourceid == nameAndSourceId then
          return entry.id
        end
      end
      
      id = id + 1
      entry = XMLData.GetEntryById(XMLNode.ACHIEVEMENT, id)
    end
    
    return nil
  end
  
  function mod:getXmlAchievementText(id)
    id = tonumber(id)
    
    if math.type(id) == 'integer' then
      local entry = XMLData.GetEntryById(XMLNode.ACHIEVEMENT, id)
      -- name is only available for modded achievements
      -- steam_name is only available for more recent achievements and doesn't contain any more info than in the enum
      -- steam_description has lots of ???
      if entry and type(entry) == 'table' and entry.text and entry.text ~= '' then
        return entry.text
      end
    end
    
    return nil
  end
  
  function mod:getXmlModName(sourceid)
    local entry = XMLData.GetModById(sourceid)
    if entry and type(entry) == 'table' and entry.name and entry.name ~= '' then
      return entry.name
    end
    
    return nil
  end
  
  function mod:getModdedAchievements()
    local achievements = {}
    
    local id = mod.maxAchievement + 1
    local entry = XMLData.GetEntryById(XMLNode.ACHIEVEMENT, id)
    while entry and type(entry) == 'table' do
      table.insert(achievements, entry)
      
      id = id + 1
      entry = XMLData.GetEntryById(XMLNode.ACHIEVEMENT, id)
    end
    
    return achievements
  end
  
  function mod:unlockLock(achievement, unlock)
    if unlock then
      local gameData = Isaac.GetPersistentGameData()
      gameData:TryUnlock(achievement, false) -- Isaac.ExecuteCommand('achievement ' .. achievement)
    else
      Isaac.ExecuteCommand('lockachievement ' .. achievement)
    end
  end
  
  function mod:processImportedJson(s)
    local function sortKeys(a, b)
      return a.key < b.key
    end
    
    local gameData = Isaac.GetPersistentGameData()
    local jsonDecoded, data = pcall(json.decode, s)
    local maxAchievementId = mod:getXmlMaxAchievementId()
    local stats = {}
    local achievements = {}
    
    if jsonDecoded and type(data) == 'table' then
      if type(data.stats) == 'table' then
        for k, v in pairs(data.stats) do
          local stat = nil
          if type(k) == 'string' then
            stat = tonumber(string.match(k, '^(%d+)'))
          end
          if math.type(stat) == 'integer' and math.type(v) == 'integer' and stat >= 1 and stat <= EventCounter.NUM_EVENT_COUNTERS - 1 and v >= 0 then
            if not mod:hasKey(stats, stat) then
              table.insert(stats, { key = stat, value = v })
            end
          end
        end
      end
      if type(data.achievements) == 'table' then
        for k, v in pairs(data.achievements) do
          local achievement = nil
          if type(k) == 'string' then
            if string.sub(k, 1, 2) == 'M-' then
              achievement = tonumber(mod:getXmlAchievementId(string.sub(k, 3)))
            else
              achievement = tonumber(string.match(k, '^(%d+)'))
            end
          end
          if math.type(achievement) == 'integer' and type(v) == 'boolean' and achievement >= 1 and achievement <= maxAchievementId then
            if not mod:hasKey(achievements, achievement) then
              table.insert(achievements, { key = achievement, value = v })
            end
          end
        end
      end
      
      table.sort(stats, sortKeys)
      table.sort(achievements, sortKeys)
      
      for _, v in ipairs(stats) do
        gameData:IncreaseEventCounter(v.key, v.value - gameData:GetEventCounter(v.key))
      end
      for _, v in ipairs(achievements) do
        mod:unlockLock(v.key, v.value)
      end
    end
    
    return jsonDecoded, jsonDecoded and 'Imported ' .. #stats .. ' stats and ' .. #achievements .. ' achievements' or data
  end
  
  -- the json library doesn't have pretty print so custom output our json
  function mod:getJsonExport(inclProgressionStats, inclOtherStats, inclCharacterAchievements, inclOtherAchievements, inclModdedAchievements)
    local gameData = Isaac.GetPersistentGameData()
    local s = '{'
    
    s = s .. '\n  "stats": {'
    local sbStats = {}
    for stat = 1, EventCounter.NUM_EVENT_COUNTERS - 1 do
      local keys = mod:getKeys(EventCounter, stat)
      if #keys > 0 then
        local isProgressionStat = mod:isProgressionStat(keys)
        if (isProgressionStat and inclProgressionStats) or (not isProgressionStat and inclOtherStats) then
          table.insert(sbStats, '\n    ' .. json.encode(stat .. '-' .. keys[1]) .. ': ' .. gameData:GetEventCounter(stat))
        end
      end
    end
    s = s .. table.concat(sbStats, ',')
    s = s .. '\n  },'
    
    s = s .. '\n  "achievements": {'
    local sbAchievements = {}
    for achievement = 1, mod.maxAchievement do
      local keys = mod:getKeys(Achievement, achievement)
      if #keys > 0 then
        local isCharacterAchievement = mod:isCharacterAchievement(achievement)
        if (isCharacterAchievement and inclCharacterAchievements) or (not isCharacterAchievement and inclOtherAchievements) then
          table.insert(sbAchievements, '\n    ' .. json.encode(achievement .. '-' .. keys[1]) .. ': ' .. tostring(gameData:Unlocked(achievement)))
        end
      end
    end
    if inclModdedAchievements then
      for _, v in ipairs(mod:getModdedAchievements()) do
        if v.id and v.id ~= '' and v.name and v.name ~= '' and v.sourceid and v.sourceid ~= '' then
          local achievement = tonumber(v.id)
          if math.type(achievement) == 'integer' then
            -- ids are transient, the json file saves these as name + sourceid
            table.insert(sbAchievements, '\n    ' .. json.encode('M-' .. v.name .. v.sourceid) .. ': ' .. tostring(gameData:Unlocked(achievement)))
          end
        end
      end
    end
    s = s .. table.concat(sbAchievements, ',')
    s = s .. '\n  }'
    
    s = s .. '\n}'
    return s
  end
  
  function mod:setupImGuiMenu()
    if not ImGui.ElementExists('shenanigansMenu') then
      ImGui.CreateMenu('shenanigansMenu', '\u{f6d1} Shenanigans')
    end
  end
  
  function mod:setupImGui()
    ImGui.AddElement('shenanigansMenu', 'shenanigansMenuItemStats', ImGuiElement.MenuItem, '\u{e473} Stat and Achievement Shenanigans')
    ImGui.CreateWindow('shenanigansWindowStats', 'Stat and Achievement Shenanigans')
    ImGui.LinkWindowToElement('shenanigansWindowStats', 'shenanigansMenuItemStats')
    
    ImGui.AddTabBar('shenanigansWindowStats', 'shenanigansTabBarStats')
    ImGui.AddTab('shenanigansTabBarStats', 'shenanigansTabStats', 'Stats')
    ImGui.AddTab('shenanigansTabBarStats', 'shenanigansTabAchievements', 'Achievements')
    ImGui.AddTab('shenanigansTabBarStats', 'shenanigansTabAchievementsModded', 'Achievements (Modded)')
    ImGui.AddTab('shenanigansTabBarStats', 'shenanigansTabStatsImportExport', 'Import/Export')
    
    local stats = {}
    local statElements = {}
    for stat = 1, EventCounter.NUM_EVENT_COUNTERS - 1 do -- 0 is NULL
      local keys = mod:getKeys(EventCounter, stat)
      if #keys > 0 then
        keys[1] = stat .. '.' .. keys[1]
        table.insert(stats, { stat = stat, keys = keys })
      end
    end
    ImGui.AddInputText('shenanigansTabStats', 'shenanigansTxtStatsSearch', '', function(txt)
      local searchedStats
      if txt == '' then
        searchedStats = stats
      else
        searchedStats = {}
        for _, v in ipairs(stats) do
          if mod:tblSearch(v.keys, txt) then
            table.insert(searchedStats, v)
          end
        end
      end
      mod:clearElements(statElements)
      mod:processStats(searchedStats, statElements)
    end, '', 'Search...')
    ImGui.AddElement('shenanigansTabStats', '', ImGuiElement.Separator, '')
    mod:processStats(stats, statElements)
    
    local achievements = {}
    local achievementElements = {}
    local achievementSort = 0 -- 0 = numerical, 1 = unlocked to bottom, 2 = unlocked to top
    -- potential improvement: XMLData.GetEntryById(XMLNode.ACHIEVEMENT, id).sourceid == 'BaseGame'
    -- this can be manipulated by adding <id>BaseGame</id> to the metadata.xml file
    -- that's extrememly rare, but still technically possible
    for achievement = 1, mod.maxAchievement do
      local keys = mod:getKeys(Achievement, achievement)
      if #keys > 0 then
        local achievementText = mod:getXmlAchievementText(achievement)
        if achievementText then
          table.insert(keys, achievementText)
        end
        keys[1] = achievement .. '.' .. keys[1]
        table.insert(achievements, { achievement = achievement, keys = keys })
      end
    end
    local searchedAchievements = achievements
    ImGui.AddInputText('shenanigansTabAchievements', 'shenanigansTxtAchievementsSearch', '', function(txt)
      if txt == '' then
        searchedAchievements = achievements
      else
        searchedAchievements = {}
        for _, v in ipairs(achievements) do
          if mod:tblSearch(v.keys, txt) then
            table.insert(searchedAchievements, v)
          end
        end
      end
      mod:clearElements(achievementElements)
      mod:processAchievements(searchedAchievements, achievementElements, 'shenanigansTabAchievements', 'shenanigansChkAchievement', achievementSort)
    end, '', 'Search...')
    ImGui.AddRadioButtons('shenanigansTabAchievements', 'shenanigansRadAchievementsSort', function(idx)
      achievementSort = idx
      mod:clearElements(achievementElements)
      mod:processAchievements(searchedAchievements, achievementElements, 'shenanigansTabAchievements', 'shenanigansChkAchievement', achievementSort)
    end, { '\u{f162}', '\u{f884}', '\u{f160}' }, achievementSort, true)
    ImGui.SetHelpmarker('shenanigansRadAchievementsSort', 'Click to refresh (does not auto-refresh)')
    ImGui.AddElement('shenanigansTabAchievements', '', ImGuiElement.Separator, '')
    mod:processAchievements(achievements, achievementElements, 'shenanigansTabAchievements', 'shenanigansChkAchievement', achievementSort)
    
    local moddedAchievements = {}
    local moddedAchievementElements = {}
    local moddedAchievementSort = 0
    for _, v in ipairs(mod:getModdedAchievements()) do
      local keys = {}
      table.insert(keys, v.name or '')
      if v.text and v.text ~= '' then
        table.insert(keys, v.text)
      end
      if v.sourceid and v.sourceid ~= '' then
        local modName = mod:getXmlModName(v.sourceid)
        table.insert(keys, modName or v.sourceid)
      end
      if v.id and v.id ~= '' and #keys > 0 then
        local achievement = tonumber(v.id)
        if math.type(achievement) == 'integer' then
          keys[1] = achievement .. '.' .. keys[1]
          table.insert(moddedAchievements, { achievement = achievement, keys = keys })
        end
      end
    end
    local moddedSearchedAchievements = moddedAchievements
    ImGui.AddInputText('shenanigansTabAchievementsModded', 'shenanigansTxtAchievementsModdedSearch', '', function(txt)
      if txt == '' then
        moddedSearchedAchievements = moddedAchievements
      else
        moddedSearchedAchievements = {}
        for _, v in ipairs(moddedAchievements) do
          if mod:tblSearch(v.keys, txt) then
            table.insert(moddedSearchedAchievements, v)
          end
        end
      end
      mod:clearElements(moddedAchievementElements)
      mod:processAchievements(moddedSearchedAchievements, moddedAchievementElements, 'shenanigansTabAchievementsModded', 'shenanigansChkAchievementModded', moddedAchievementSort)
    end, '', 'Search...')
    ImGui.AddRadioButtons('shenanigansTabAchievementsModded', 'shenanigansRadAchievementsModdedSort', function(idx)
      moddedAchievementSort = idx
      mod:clearElements(moddedAchievementElements)
      mod:processAchievements(moddedSearchedAchievements, moddedAchievementElements, 'shenanigansTabAchievementsModded', 'shenanigansChkAchievementModded', moddedAchievementSort)
    end, { '\u{f162}', '\u{f884}', '\u{f160}' }, moddedAchievementSort, true)
    ImGui.SetHelpmarker('shenanigansRadAchievementsModdedSort', 'Click to refresh (does not auto-refresh)')
    ImGui.AddElement('shenanigansTabAchievementsModded', '', ImGuiElement.Separator, '')
    mod:processAchievements(moddedAchievements, moddedAchievementElements, 'shenanigansTabAchievementsModded', 'shenanigansChkAchievementModded', moddedAchievementSort)
    
    local importText = ''
    ImGui.AddElement('shenanigansTabStatsImportExport', '', ImGuiElement.SeparatorText, 'Import')
    ImGui.AddText('shenanigansTabStatsImportExport', 'Paste JSON here:', false, '')
    ImGui.AddInputTextMultiline('shenanigansTabStatsImportExport', 'shenanigansTxtStatsImport', '', function(txt)
      importText = txt
    end, importText, 12)
    for i, v in ipairs({
                        { text = 'Cut'        , func = function()
                                                         if importText ~= '' then
                                                           Isaac.SetClipboard(importText)
                                                           ImGui.UpdateData('shenanigansTxtStatsImport', ImGuiData.Value, '')
                                                           importText = ''
                                                         end
                                                       end },
                        { text = 'Copy'       , func = function()
                                                         if importText ~= '' then
                                                           Isaac.SetClipboard(importText)
                                                         end
                                                       end },
                        { text = 'Paste'      , func = function()
                                                         local clipboard = Isaac.GetClipboard()
                                                         if clipboard then
                                                           ImGui.UpdateData('shenanigansTxtStatsImport', ImGuiData.Value, clipboard)
                                                           importText = clipboard
                                                         end
                                                       end },
                        { text = 'Import JSON', func = function()
                                                         local jsonImported, msg = mod:processImportedJson(importText)
                                                         ImGui.PushNotification(msg, jsonImported and ImGuiNotificationType.SUCCESS or ImGuiNotificationType.ERROR, 5000)
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
      moddedAchievements = true,
    }
    ImGui.AddElement('shenanigansTabStatsImportExport', '', ImGuiElement.SeparatorText, 'Export')
    for i, v in ipairs({
                        { text = 'Export progression stats?'              , exportBoolean = 'progressionStats'     , helpText = 'Completion marks for built-in characters' },
                        { text = 'Export other stats?'                    , exportBoolean = 'otherStats' },
                        { text = 'Export built-in character achievements?', exportBoolean = 'characterAchievements', helpText = 'Unlocks for built-in characters' },
                        { text = 'Export other built-in achievements?'    , exportBoolean = 'otherAchievements' },
                        { text = 'Export modded achievements?'            , exportBoolean = 'moddedAchievements' },
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
      if Isaac.SetClipboard(mod:getJsonExport(exportBooleans.progressionStats, exportBooleans.otherStats, exportBooleans.characterAchievements, exportBooleans.otherAchievements, exportBooleans.moddedAchievements)) then
        ImGui.PushNotification('Copied JSON to clipboard', ImGuiNotificationType.INFO, 5000)
      end
    end, false)
  end
  
  function mod:clearElements(elements)
    for k, v in pairs(elements) do
      ImGui.RemoveElement(v)
      elements[k] = nil
    end
  end
  
  function mod:processStats(stats, statElements)
    for _, v in ipairs(stats) do
      local stat = v.stat
      local keys = v.keys
      local isProgressionStat = mod:isProgressionStat(keys)
      local intStatId = 'shenanigansIntStat' .. stat
      local intStatText = table.remove(keys, 1)
      local intStatTooltip = isProgressionStat and intStatText .. ' (0=Off,1=Normal,2=Hard)' or intStatText
      ImGui.AddInputInteger('shenanigansTabStats', intStatId, intStatText, nil, 0, 1, 100)
      ImGui.SetTooltip(intStatId, intStatTooltip)
      if #keys > 0 then
        ImGui.SetHelpmarker(intStatId, table.concat(keys, ', '))
      end
      table.insert(keys, 1, intStatText)
      table.insert(statElements, intStatId)
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
  
  function mod:processAchievements(achievements, achievementElements, tab, chkPrefix, sort)
    local gameData = Isaac.GetPersistentGameData()
    local deferredAchievements = {}
    for _, v in ipairs(achievements) do
      v.unlocked = gameData:Unlocked(v.achievement)
      if (sort == 1 and v.unlocked) or (sort == 2 and not v.unlocked) then
        table.insert(deferredAchievements, v)
      else
        mod:processAchievement(v.achievement, v.keys, v.unlocked, achievementElements, tab, chkPrefix)
      end
    end
    for _, v in ipairs(deferredAchievements) do
      mod:processAchievement(v.achievement, v.keys, v.unlocked, achievementElements, tab, chkPrefix)
    end
  end
  
  function mod:processAchievement(achievement, keys, unlocked, achievementElements, tab, chkPrefix)
    local chkAchievementId = chkPrefix .. achievement
    local chkAchievementText = table.remove(keys, 1)
    ImGui.AddCheckbox(tab, chkAchievementId, chkAchievementText, nil, unlocked)
    if #keys > 0 then
      ImGui.SetHelpmarker(chkAchievementId, table.concat(keys, ', '))
    end
    table.insert(keys, 1, chkAchievementText)
    table.insert(achievementElements, chkAchievementId)
    ImGui.AddCallback(chkAchievementId, ImGuiCallback.Render, function()
      if Isaac.GetFrameCount() % 4 == 0 then -- better performance for all 600+ achievements
        local gameData = Isaac.GetPersistentGameData()
        ImGui.UpdateData(chkAchievementId, ImGuiData.Value, gameData:Unlocked(achievement))
      end
    end)
    ImGui.AddCallback(chkAchievementId, ImGuiCallback.Edited, function(b)
      mod:unlockLock(achievement, b)
    end)
  end
  
  mod:setupImGuiMenu()
  mod:AddCallback(ModCallbacks.MC_POST_MODS_LOADED, mod.onModsLoaded)
end