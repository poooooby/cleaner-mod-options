-- Mod Manager option schema for cleaner_mod_options.
--
-- Declared in manifest.json's "options_schema", so the manager can render
-- these rows while the mod is disabled. main.lua hands this SAME file to
-- mod.options:define() at load time (one copy, read twice), which is what
-- gives mod.options:get() its defaults. These rows are the mod's ONLY
-- settings UI (OPTIONS -> MODS -> Cleaner Mod Options); nothing is added to
-- the top-level OPTION screen.
--
-- Both filters default OFF: out of the box the list is vanilla, and because
-- this mod targets every game and is loaded whenever its filters apply, its
-- own entry -- and with it these two switches -- can never be hidden. That
-- makes the toggles themselves the way back to the full list.
return {
  {
    key = "hide_disabled",
    label = "HIDE DISABLED",
    type = "choice",
    default = "off",
    choices = { { "OFF", "off" }, { "ON", "on" } },
    description = "ON: mods that were disabled when the game started are hidden from the MODS list. A mod toggled OFF this session stays visible until restart, so the change can still be undone here. Hidden mods can be re-enabled from the desktop launcher, or by turning this OFF. OFF: every installed mod is listed.",
  },
  {
    key = "hide_other_games",
    label = "HIDE OTHER GAMES",
    type = "choice",
    default = "off",
    choices = { { "OFF", "off" }, { "ON", "on" } },
    description = "ON: mods that cannot run on the game being played (wrong game or generation) are hidden from the MODS list. A mod forced with TRY HERE ANYWAY counts as running here and stays visible. OFF: every installed mod is listed.",
  },
}
