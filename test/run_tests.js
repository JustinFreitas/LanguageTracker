const fs = require('fs');
const path = require('path');
const assert = require('assert');
const { LuaFactory } = require('wasmoon');

async function runTests() {
    console.log("Setting up Lua VM via wasmoon...");
    const luaFactory = new LuaFactory();
    const lua = await luaFactory.createEngine();

    // 1. Mock FGU environment globals
    console.log("Mocking FGU environment globals...");
    
    await lua.doString(`
        Interface = {}
        OptionsManager = {}
        Comm = {}
        DB = {}
        ActorManager = {}
        CombatManager = {}
        StringManager = {}
        LanguageManager = {}
        User = {}
        
        -- Mock User
        function User.isHost() return true end

        -- Mock StringManager
        StringManager.trim = function(s)
            if not s then return "" end
            return s:match("^%s*(.-)%s*$")
        end
        StringManager.isBlank = function(s)
            if type(s) ~= "string" then return true end
            return s:gsub("%s+", "") == ""
        end

        -- Mock OptionsManager
        local options = {}
        function OptionsManager.registerOption2() end
        function OptionsManager.getOption(key)
            return options[key]
        end
        function OptionsManager.setOption(key, val)
            options[key] = val
        end

        -- Mock Comm
        local chatMessages = {}
        function Comm.registerSlashHandler() end
        function Comm.addChatMessage(msg)
            table.insert(chatMessages, msg.text)
        end
        function Comm.deliverChatMessage(msg)
            table.insert(chatMessages, msg.text)
        end
        function Comm.getChatMessages()
            return chatMessages
        end
        function Comm.clearChatMessages()
            chatMessages = {}
        end

        -- Mock CombatManager
        CombatManager.CT_LIST = "combattracker"

        -- Mock LanguageManager
        LanguageManager.CAMPAIGN_LANGUAGE_LIST = "languages"
        LanguageManager.CAMPAIGN_LANGUAGE_LIST_NAME = "name"

        -- Mock Database structure
        dbData = {}
        function DB.setNodeValue(path, val)
            dbData[path] = val
        end
        
        function DB.getValue(node, field, default)
            local nodePath = ""
            if type(node) == "table" and node.path then
                nodePath = node.path
            elseif type(node) == "string" then
                nodePath = node
            end
            
            local fullPath = nodePath .. "." .. field
            if dbData[fullPath] ~= nil then
                return dbData[fullPath]
            end
            return default
        end

        function DB.findNode(nodePath)
            if type(nodePath) == "table" then return nodePath end
            return { path = nodePath }
        end

        local dbChildren = {}
        function DB.setChildren(nodePath, children)
            dbChildren[nodePath] = children
        end

        function DB.getChildren(node, field)
            local nodePath = ""
            if type(node) == "table" and node.path then
                nodePath = node.path
            elseif type(node) == "string" then
                nodePath = node
            end
            
            local fullPath = nodePath
            if field then
                fullPath = nodePath .. "." .. field
            end
            
            local children = dbChildren[fullPath] or {}
            local list = {}
            for k, v in pairs(children) do
                list[k] = { path = fullPath .. "." .. k }
            end
            return list
        end

        -- Mock ActorManager
        local actorMap = {}
        function ActorManager.getActor(nodeCT)
            return actorMap[nodeCT.path]
        end
        function ActorManager.setActor(nodeCTPath, actor)
            actorMap[nodeCTPath] = actor
        end
    `);

    // 2. Load the actual languagetracker script
    console.log("Loading scripts/languagetracker.lua into VM...");
    const luaCodePath = path.join(__dirname, '../scripts/languagetracker.lua');
    const luaCode = fs.readFileSync(luaCodePath, 'utf8');
    
    await lua.doString(luaCode);
    console.log("LanguageTracker loaded successfully inside VM.\n");

    // 3. Define and run test assertions
    console.log("Running Unit Tests...");
    let testsPassed = 0;
    let testsFailed = 0;

    async function runAssert(fnName, expected, luaCodeToRun) {
        try {
            const result = await lua.doString(luaCodeToRun);
            assert.strictEqual(result, expected);
            console.log(`  ✓ PASS: ${fnName} -> got ${result}`);
            testsPassed++;
        } catch (err) {
            console.error(`  ✗ FAIL: ${fnName} -> expected ${expected}, got error or mismatch: ${err.message}`);
            testsFailed++;
        }
    }

    // --- TEST 1: getLanguageTableFromCommaDelimitedString ---
    await runAssert("Comma parsing length", 3, "return #getLanguageTableFromCommaDelimitedString('Common, Elvish, Dwarvish')");
    await runAssert("Comma parsing item 2", "Elvish", "return getLanguageTableFromCommaDelimitedString('Common, Elvish, Dwarvish')[2]");

    // --- TEST 2: addLanguagesToTable adds language and counts it ---
    await lua.doString(`
        local aTable = {}
        local rActor = { sName = "Elminster" }
        local aCampaign = { ["Common"] = 1, ["Elvish"] = 1 }
        addLanguagesToTable(aTable, rActor, aCampaign, {"Common", "Undercommon"})
        
        testTable = aTable
    `);
    await runAssert("addLanguagesToTable count", 2, "local count = 0; for k,v in pairs(testTable) do count = count + 1 end; return count");
    await runAssert("addLanguagesToTable campaign non-campaign check", true, "return testTable['Undercommon'].nonCampaign");
    await runAssert("addLanguagesToTable speaker tracking", "Elminster", "return testTable['Common'].names[1]");

    // --- TEST 3: duplicate speaker prevention ---
    await lua.doString(`
        addLanguagesToTable(testTable, { sName = "Elminster" }, { ["Common"] = 1 }, {"Common"})
    `);
    await runAssert("Duplicate speaker check", 1, "return #testTable['Common'].names");

    // --- TEST 4: getSortedLanguageList sorting ---
    await lua.doString(`
        local unsorted = {
            ["Elvish"] = {},
            ["Common"] = {},
            ["Dwarvish"] = {}
        }
        sortedList = getSortedLanguageList(unsorted)
    `);
    await runAssert("Sorted list length", 3, "return #sortedList");
    await runAssert("Sorted list index 1 name", "Common", "return sortedList[1].language");
    await runAssert("Sorted list index 2 name", "Dwarvish", "return sortedList[2].language");
    await runAssert("Sorted list index 3 name", "Elvish", "return sortedList[3].language");

    // --- TEST 5: processChatCommand execution without parameters (Party only) ---
    await lua.doString(`
        -- Mock database
        DB.setChildren("languages", {
            ["lang1"] = true,
            ["lang2"] = true
        })
        DB.setNodeValue("languages.lang1.name", "Common")
        DB.setNodeValue("languages.lang2.name", "Elvish")
        
        -- Mock CT List containing 2 party members
        DB.setChildren("combattracker", {
            ["entry1"] = true,
            ["entry2"] = true
        })
        DB.setNodeValue("combattracker.entry1.friendfoe", "friend")
        DB.setNodeValue("combattracker.entry2.friendfoe", "friend")
        
        local actor1 = { sCreatureNode = "charsheet.id-00001", sName = "Elminster", sType = "charsheet" }
        local actor2 = { sCreatureNode = "charsheet.id-00002", sName = "Drizzt", sType = "charsheet" }
        ActorManager.setActor("combattracker.entry1", actor1)
        ActorManager.setActor("combattracker.entry2", actor2)
        
        -- Setup database languages for PCs
        DB.setChildren("charsheet.id-00001.languagelist", { ["l1"] = true })
        DB.setNodeValue("charsheet.id-00001.languagelist.l1.name", "Common")
        
        DB.setChildren("charsheet.id-00002.languagelist", { ["l1"] = true, ["l2"] = true })
        DB.setNodeValue("charsheet.id-00002.languagelist.l1.name", "Common")
        DB.setNodeValue("charsheet.id-00002.languagelist.l2.name", "Elvish")
        
        -- Reset options and run command
        OptionsManager.setOption("LANGUAGETRACKER_FRAME_STYLE", "none")
        Comm.clearChatMessages()
        processChatCommand(nil, "")
    `);
    
    // Elminster speaks Common. Drizzt speaks Common and Elvish.
    // Common should be flagged as [all].
    await runAssert("Chat messages generated count", 1, "return #Comm.getChatMessages()");
    await runAssert("Chat message content contains Common [all]", true, "return Comm.getChatMessages()[1]:find('Common %s*%[all%]') ~= nil");
    await runAssert("Chat message content contains Elvish", true, "return Comm.getChatMessages()[1]:find('Elvish %- Drizzt') ~= nil");

    // --- TEST 6: processChatCommand 'all' (Cross-referencing Foe barrier languages) ---
    await lua.doString(`
        -- Add a foe actor speaking Goblin (which the party does not understand)
        DB.setChildren("combattracker", {
            ["entry1"] = true,
            ["entry2"] = true,
            ["entry3"] = true
        })
        DB.setNodeValue("combattracker.entry3.friendfoe", "foe")
        local foeActor = { sCreatureNode = "npc.id-00001", sName = "Goblin Boss", sType = "npc" }
        ActorManager.setActor("combattracker.entry3", foeActor)
        DB.setNodeValue("npc.id-00001.languages", "Goblin, Elvish") -- speaks Goblin and Elvish
        
        Comm.clearChatMessages()
        processChatCommand(nil, "all")
    `);
    
    // Since Goblin is a non-campaign language, it should be marked with an asterisk (*).
    // The party understands Elvish (Drizzt speaks it), so Elvish is NOT a barrier language.
    // Only Goblin is a barrier language.
    await runAssert("Chat message for 'all' contains Goblin*", true, "return Comm.getChatMessages()[1]:find('Goblin%* %- Goblin Boss') ~= nil");
    await runAssert("Chat message does NOT list Elvish as a barrier language", false, "return Comm.getChatMessages()[1]:find('Elvish.*barrier') ~= nil");

    // 4. Print Summary
    console.log(`\nTest Summary: ${testsPassed} passed, ${testsFailed} failed.`);
    
    if (testsFailed > 0) {
        process.exit(1);
    }
}

runTests().catch(err => {
    console.error("Test execution failed: ", err);
    process.exit(1);
});
