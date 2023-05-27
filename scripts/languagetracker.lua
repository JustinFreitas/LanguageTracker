-- This extension contains 5e SRD languages.  For license details see file: Open Gaming License v1.0a.txt

MAX = "max"
LANGUAGETRACKER_VERBOSE = "LANGUAGETRACKER_VERBOSE"
OFF = "off"
USER_ISHOST = false

function onInit()
	local option_header = "option_header_languagetracker"
	local option_val_off = "option_val_off"
	local option_entry_cycler = "option_entry_cycler"
	OptionsManager.registerOption2(LANGUAGETRACKER_VERBOSE, false, option_header, "option_label_LANGUAGETRACKER_VERBOSE", option_entry_cycler,
	{ baselabel = "option_val_max", baseval = MAX, labels = "option_val_standard|" .. option_val_off, values = "standard|" .. OFF, default = MAX })

    USER_ISHOST = User.isHost()

	if USER_ISHOST then
        Comm.registerSlashHandler("lt", processChatCommand)
        Comm.registerSlashHandler("language", processChatCommand)
    end
end

function addLanguagesToTable(aTable, rCurrentActor, aCampaignLanguages, aLanguagesToAdd)
    for _,sLanguage in pairs(aLanguagesToAdd) do
        local language = StringManager.trim(sLanguage)
        if not aCampaignLanguages[language] then
            language = language .. " (non-campaign)"
        end

        local aNames = aTable[language]
        if not aNames then
            aNames = {}
        end

        local sTrimmedName = StringManager.trim(rCurrentActor.sName)
        table.insert(aNames, sTrimmedName)
        aTable[language] = aNames
    end
end

-- Puts a message in chat that is broadcast to everyone attached to the host (including the host) if bSecret is true, otherwise local only.
function displayChatMessage(sFormattedText, bSecret)
	if not sFormattedText then return end

	local msg = {font = "msgfont", icon = "languagetracker_icon", secret = false, text = sFormattedText}

	-- deliverChatMessage() is a broadcast mechanism, addChatMessage() is local only.
	if bSecret then
		Comm.addChatMessage(msg)
	else
		Comm.deliverChatMessage(msg)
	end
end

function displayTableIfNonEmpty(aTable)
	aTable = validateTableOrNew(aTable)
	if #aTable > 0 then
		local sDisplay = table.concat(aTable, "\r")
		displayChatMessage(sDisplay, true) -- TODO: make any 'party' role public, but everything else should be private to not leak npc info.
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

-- Handler for the message to do an attack from a mount.
function insertBlankSeparatorIfNotEmpty(aTable)
	if #aTable > 0 then table.insert(aTable, "") end
end

function insertFormattedTextWithSeparatorIfNonEmpty(aTable, sFormattedText)
	insertBlankSeparatorIfNotEmpty(aTable)
	table.insert(aTable, sFormattedText)
end

function processChatCommand(_, sParams)
    local aCampaignLanguages = getCampaignLanguagesTable()
    local allFriendlyLanguages = {}
	for _,nodeCT in pairs(DB.getChildren(CombatManager.CT_LIST)) do
        if DB.getValue(nodeCT, "friendfoe", "foe") == "friend" or sParams == "all" then
            local rCurrentActor = ActorManager.resolveActor(nodeCT)
            local nodeCharSheet = DB.findNode(rCurrentActor.sCreatureNode)
            local aLanguagesToAdd
            if rCurrentActor.sType == "charsheet" then
                aLanguagesToAdd = getLanguageTableFromDatabaseNodes(nodeCharSheet)
            else
                aLanguagesToAdd = getLanguageTableFromCommaDelimitedString(DB.getValue(nodeCharSheet, "languages", ""))
            end

            addLanguagesToTable(allFriendlyLanguages, rCurrentActor, aCampaignLanguages, aLanguagesToAdd)
        end
    end

    local sortedLanguages = {}
    for s,v in pairs(allFriendlyLanguages) do
        table.insert(sortedLanguages,{language = s, pcs = v})
    end

	table.sort(sortedLanguages, function (a, b) return a.language < b.language end)
    local aOutput = {}
    local scope = "Party"
    if sParams == "all" then
        scope = "All Actor"
    end

    insertFormattedTextWithSeparatorIfNonEmpty(aOutput, "\rLanguageTracker, " .. scope .. " Languages:")
    for _,v in ipairs(sortedLanguages) do
        local pcs = ""
        local bFirstRow = true
        table.sort(v.pcs)
        for _,pc in ipairs(v.pcs) do
            if bFirstRow then
                pcs = pc
                bFirstRow = false
            else
                pcs = pcs .. ", " .. pc
            end
        end

        insertFormattedTextWithSeparatorIfNonEmpty(aOutput, v.language .. " - " .. pcs)
    end

    displayTableIfNonEmpty(aOutput)
end

-- Chat commands that are for host only
function validateTableOrNew(aTable)
	if aTable and type(aTable) == "table" then
		return aTable
	else
		return {}
	end
end
