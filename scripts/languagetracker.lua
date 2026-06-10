-- This extension contains 5e SRD languages.  For license details see file: Open Gaming License v1.0a.txt

MAX = "max"
LANGUAGETRACKER_FRAME_STYLE = "LANGUAGETRACKER_FRAME_STYLE"
LANGUAGETRACKER_VERBOSE = "LANGUAGETRACKER_VERBOSE"
NONE = "none"
OFF = "off"
USER_ISHOST = false

-- Helper to safely check if a string is blank, preferring the modern StringManager method.
local function isBlankSafe(s)
    if StringManager.isBlank then
        return StringManager.isBlank(s)
    end
    if type(s) ~= "string" then
        return false
    end
    return (string.gsub(s, "%s+", "") == "")
end

-- Helper to safely get an actor from a node/string, preferring the modern getActor method.
local function getActorSafe(v)
    if ActorManager.getActor then
        return ActorManager.getActor(v)
    end
    return ActorManager.resolveActor(v)
end

function onInit()
	local option_header = "option_header_languagetracker"
    local option_val_none = "option_val_none_LANGUAGETRACKER"
	local option_val_off = "option_val_off"
	local option_entry_cycler = "option_entry_cycler"
	OptionsManager.registerOption2(LANGUAGETRACKER_VERBOSE, false, option_header, "option_label_LANGUAGETRACKER_VERBOSE", option_entry_cycler,
	{ baselabel = "option_val_max", baseval = MAX, labels = "option_val_standard|" .. option_val_off, values = "standard|" .. OFF, default = MAX })
    OptionsManager.registerOption2(LANGUAGETRACKER_FRAME_STYLE, false, option_header, "option_label_LANGUAGETRACKER_FRAME_STYLE", option_entry_cycler,
    { baselabel = option_val_none, baseval = NONE, labels = "option_val_chat_LANGUAGETRACKER|option_val_story_LANGUAGETRACKER|option_val_whisper_LANGUAGETRACKER", values = "chat|story|whisper", default = NONE })

    USER_ISHOST = User.isHost()

	if USER_ISHOST then
        Comm.registerSlashHandler("lt", processChatCommand)
        Comm.registerSlashHandler("language", processChatCommand)
        Comm.registerSlashHandler("languagetracker", processChatCommand)
    end
end

-- Records each language spoken by rCurrentActor into aTable, keyed by the clean language name.
-- Each entry tracks the set of speaker names and whether the language is outside the campaign list.
function addLanguagesToTable(aTable, rCurrentActor, aCampaignLanguages, aLanguagesToAdd)
    local sTrimmedName = StringManager.trim(rCurrentActor.sName)
    for _,sLanguage in pairs(aLanguagesToAdd) do
        local language = StringManager.trim(sLanguage)
        -- Skip blanks and "no languages" placeholders like "-", "--", or "none".
        local sBare = string.lower(string.gsub(language, "[%-%s]", ""))
        if language ~= "" and sBare ~= "" and sBare ~= "none" then
            local entry = aTable[language]
            if not entry then
                entry = { names = {}, seen = {}, nonCampaign = not aCampaignLanguages[language] }
                aTable[language] = entry
            end

            -- Guard against the same actor contributing a duplicate name (e.g. listed twice).
            if not entry.seen[sTrimmedName] then
                entry.seen[sTrimmedName] = true
                table.insert(entry.names, sTrimmedName)
            end
        end
    end
end

-- Puts a message in chat. When bGmOnly is true the message stays local to the host (players never see it);
-- otherwise it is broadcast to everyone attached to the host (including the host).
function displayChatMessage(sFormattedText, bGmOnly)
	if isBlankSafe(sFormattedText) then return end

    local sMode = getMode()
	local msg = {font = "msgfont", icon = "languagetracker_icon", secret = false, text = sFormattedText, mode = sMode};

	-- deliverChatMessage() is a broadcast mechanism, addChatMessage() is local only.
	if bGmOnly then
		Comm.addChatMessage(msg)
	else
		Comm.deliverChatMessage(msg)
	end
end

function displayTableIfNonEmpty(aTable)
	aTable = validateTableOrNew(aTable)
	if #aTable > 0 then
		local sDisplay = table.concat(aTable, "\r")
		displayChatMessage(sDisplay, true) -- GM-only: NPC languages must not leak to players.
	end
end

function getCampaignLanguagesTable()
    local aCampaignLanguages = {}
	for _,v in pairs(DB.getChildren(LanguageManager.CAMPAIGN_LANGUAGE_LIST)) do
		local sLang = DB.getValue(v, LanguageManager.CAMPAIGN_LANGUAGE_LIST_NAME, "")
		sLang = StringManager.trim(sLang)
		if (sLang or "") ~= "" then
            aCampaignLanguages[sLang] = 1
		end
	end

    return aCampaignLanguages
end

function getLanguageTableFromCommaDelimitedString(sCommaDelimited)
    local aTable = {}
    for word in string.gmatch(sCommaDelimited, '([^,]+)') do
        local sTrimmedWord = StringManager.trim(word)
        table.insert(aTable, sTrimmedWord)
    end

    return aTable
end

function getLanguageTableFromDatabaseNodes(nodeCharSheet)
    local aLanguageTable = {}
    for _,vLanguage in pairs(DB.getChildren(nodeCharSheet, "languagelist")) do
        local sTrimmedLanguage = StringManager.trim(DB.getValue(vLanguage, "name", ""))
        table.insert(aLanguageTable, sTrimmedLanguage)
    end

    return aLanguageTable
end

function getMode()
    local sFrameStyle = OptionsManager.getOption(LANGUAGETRACKER_FRAME_STYLE)
    if sFrameStyle == NONE or sFrameStyle == nil then
        sFrameStyle = ""
    end

    return sFrameStyle
end

-- Inserts a blank line as a visual separator, but only if the table already has content.
function insertBlankSeparatorIfNotEmpty(aTable)
	if #aTable > 0 then table.insert(aTable, "") end
end

function insertFormattedTextWithSeparatorIfNonEmpty(aTable, sFormattedText)
	insertBlankSeparatorIfNotEmpty(aTable)
	table.insert(aTable, sFormattedText)
end

-- Reads the languages for a single CT actor. Returns an empty table if the source node is missing.
function getActorLanguages(rActor)
    local nodeCharSheet = DB.findNode(rActor.sCreatureNode)
    if not nodeCharSheet then
        return {}
    end

    if rActor.sType == "charsheet" then
        return getLanguageTableFromDatabaseNodes(nodeCharSheet)
    end

    return getLanguageTableFromCommaDelimitedString(DB.getValue(nodeCharSheet, "languages", ""))
end

-- Returns a sorted array of { language, entry } pairs from a name-keyed language table.
function getSortedLanguageList(aLanguages)
    local sorted = {}
    for sLanguage, entry in pairs(aLanguages) do
        table.insert(sorted, { language = sLanguage, entry = entry })
    end

    table.sort(sorted, function(a, b) return a.language < b.language end)
    return sorted
end

function processChatCommand(_, sParams)
    local aCampaignLanguages = getCampaignLanguagesTable()
    local aFriendlyLanguages = {}
    local aFoeLanguages = {}
    local nPartyCount = 0
	for _,nodeCT in pairs(DB.getChildren(CombatManager.CT_LIST)) do
        local bFriend = DB.getValue(nodeCT, "friendfoe", "foe") == "friend"
        if bFriend or sParams == "all" then
            local rCurrentActor = getActorSafe(nodeCT)
            if rCurrentActor then
                local aLanguagesToAdd = getActorLanguages(rCurrentActor)
                if bFriend then
                    nPartyCount = nPartyCount + 1
                    addLanguagesToTable(aFriendlyLanguages, rCurrentActor, aCampaignLanguages, aLanguagesToAdd)
                else
                    addLanguagesToTable(aFoeLanguages, rCurrentActor, aCampaignLanguages, aLanguagesToAdd)
                end
            end
        end
    end

    local sortedFriendly = getSortedLanguageList(aFriendlyLanguages)
    local scope = "Party"
    if sParams == "all" then
        scope = "All Actor"
    end

    local aOutput = {}
    local bAnyNonCampaign = false
    insertFormattedTextWithSeparatorIfNonEmpty(aOutput, "LanguageTracker, " .. scope .. " Languages:")
    for _,v in ipairs(sortedFriendly) do
        table.sort(v.entry.names)
        local sLine = v.language
        if v.entry.nonCampaign then
            sLine = sLine .. "*"
            bAnyNonCampaign = true
        end

        -- Flag languages the entire party shares -- the most useful signal at the table.
        if nPartyCount > 1 and #v.entry.names == nPartyCount then
            sLine = sLine .. " [all]"
        end

        insertFormattedTextWithSeparatorIfNonEmpty(aOutput, sLine .. " - " .. table.concat(v.entry.names, ", "))
    end

    -- Cross-reference: which foe languages can NO party member understand?
    if sParams == "all" then
        local aBarrier = {}
        for sLanguage, entry in pairs(aFoeLanguages) do
            if not aFriendlyLanguages[sLanguage] then
                local sLabel = sLanguage
                if entry.nonCampaign then
                    sLabel = sLabel .. "*"
                    bAnyNonCampaign = true
                end
                table.sort(entry.names)
                table.insert(aBarrier, sLabel .. " - " .. table.concat(entry.names, ", "))
            end
        end

        if #aBarrier > 0 then
            table.sort(aBarrier)
            insertFormattedTextWithSeparatorIfNonEmpty(aOutput, "Foe languages the party cannot understand:")
            for _,sLine in ipairs(aBarrier) do
                insertFormattedTextWithSeparatorIfNonEmpty(aOutput, sLine)
            end
        end
    end

    if bAnyNonCampaign then
        insertFormattedTextWithSeparatorIfNonEmpty(aOutput, "* = not in campaign language list")
    end

    displayTableIfNonEmpty(aOutput)
end

-- Returns aTable if it is a valid table, otherwise a fresh empty table.
function validateTableOrNew(aTable)
	if aTable and type(aTable) == "table" then
		return aTable
	else
		return {}
	end
end
