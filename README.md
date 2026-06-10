# LanguageTracker

https://github.com/JustinFreitas/LanguageTracker

LanguageTracker v1.3, by Justin Freitas

ReadMe and Usage Notes

Shows the languages known by friendly Combat Tracker participants in a GM-only chat
message, sorted alphabetically, with the names of who speaks each. Languages spoken by
every party member are tagged `[all]`, and languages not in the campaign language list are
tagged with `*`.

GM LanguageTracker Chat Commands:

- Party languages (friendly CT actors), alphabetized, with the speakers of each:

  `/lt`
  or
  `/language`
  or
  `/languagetracker`

- Include foes as well. In addition to the combined list, this reports the foe languages
  that **no** party member can understand (the language barrier at the table):

  `/lt all`

Output notes:
- Output is GM-only (local to the host) so NPC/foe languages never leak to players.
- `*` marks a language that is not in the campaign language list.
- `[all]` marks a language spoken by every friendly party member.

Extension name in the selector is 'Feature: LanguageTracker'.

Changelist:
- v1.0 - Initial version.
- v1.2 - Modernize API calls with a getActorSafe helper.
- v1.3 - Modern CoreRPG functions (StringManager.isBlank), getActorSafe helper, chat frame
  styles. Added `[all]` party-wide marker, `*` non-campaign marker, `/lt all` foe
  language-barrier cross-reference, `/languagetracker` alias, and crash fix for combatants
  with a missing source node.
