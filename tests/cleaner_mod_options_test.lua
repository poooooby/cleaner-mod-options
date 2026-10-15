-- Headless suite for cleaner_mod_options. Run from the engine root:
--   luajit mods/cleaner_mod_options/tests/cleaner_mod_options_test.lua
--
-- Asserts the mod's stated effect: the ManagerState mod list hides disabled
-- and other-game mods only while the matching option is ON, staged and
-- TRY HERE ANYWAY mods always stay, headers prune with their mods, and the
-- options screen's INSTALLED count follows the same filter.
package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")

local run = T.sdk.loadMod("mods/cleaner_mod_options", {})
T.eq(#run.errors, 0, "loads clean")
T.eq(run.mod and run.mod.state, "loaded", "state is loaded")

local ManagerState = require("src.mods.ManagerState")

-- shaped like Loader:status() entries: validated manifest + runtime fields
local function manifest(id, cat, state, enabled, games, forced)
  return { id = id, name = id:upper(), category = cat,
           state = state, enabled = enabled,
           games = games or { "red", "blue", "yellow" },
           gen2Forced = forced or false }
end

local function stateWith(avail)
  return setmetatable({ status = { available = avail },
                        game = { mods = run.loader } },
                      { __index = ManagerState })
end

local function setOptions(tbl)
  run.loader.modOptions = run.loader.modOptions or {}
  run.loader.modOptions.cleaner_mod_options = tbl
end

local function ids(rows)
  local out = {}
  for _, r in ipairs(rows) do if r.mod then out[#out + 1] = r.mod.id end end
  return table.concat(out, ",")
end

local function headers(rows)
  local out = {}
  for _, r in ipairs(rows) do if r.header then out[#out + 1] = r.label end end
  return table.concat(out, ",")
end

-- GameVersion.current defaults to "red" headless, so "gold" mods are
-- other-game here
local avail = {
  manifest("alpha", "UI", "loaded", true),                  -- enabled, runs here
  manifest("bravo", "UI", "disabled", false),               -- disabled at boot
  manifest("charlie", "UI", "disabled", true),              -- staged to enable
  manifest("delta", "MECHANIC", "wrong_generation", true, { "gold" }),
  manifest("echo", "MECHANIC", "loaded", true, { "gold" }, true), -- forced here
}

-- defaults: both OFF, the list is vanilla (categories sort, so MECHANIC first)
setOptions(nil)
T.eq(ids(stateWith(avail):modRows()), "delta,echo,alpha,bravo,charlie",
  "both filters OFF: every mod is listed")
T.eq(headers(stateWith(avail):modRows()), "MECHANIC,UI",
  "both filters OFF: vanilla headers")

-- HIDE DISABLED hides the boot-disabled mod; the staged one stays
setOptions({ hide_disabled = "on" })
T.eq(ids(stateWith(avail):modRows()), "delta,echo,alpha,charlie",
  "HIDE DISABLED: bravo hidden, staged charlie kept")

-- HIDE OTHER GAMES hides the gold-only mod; the forced one stays
setOptions({ hide_other_games = "on" })
T.eq(ids(stateWith(avail):modRows()), "echo,alpha,bravo,charlie",
  "HIDE OTHER GAMES: delta hidden, forced echo kept")

-- both ON
setOptions({ hide_disabled = "on", hide_other_games = "on" })
T.eq(ids(stateWith(avail):modRows()), "echo,alpha,charlie",
  "both ON: bravo and delta hidden")

-- a category whose every mod is hidden loses its header
local partial = {
  manifest("alpha", "UI", "loaded", true),
  manifest("delta", "MECHANIC", "wrong_generation", true, { "gold" }),
}
setOptions({ hide_other_games = "on" })
T.eq(headers(stateWith(partial):modRows()), "UI",
  "emptied category header is pruned")
T.eq(ids(stateWith(partial):modRows()), "alpha", "its mods are gone")

-- everything hidden: a placeholder row, never a blank screen
local allHidden = {
  manifest("bravo", "UI", "disabled", false),
  manifest("delta", "MECHANIC", "wrong_generation", true, { "gold" }),
}
setOptions({ hide_disabled = "on", hide_other_games = "on" })
local rows = stateWith(allHidden):modRows()
T.eq(#rows, 1, "all hidden: one placeholder row")
T.eq(rows[1].header and rows[1].label, "ALL MODS HIDDEN (2)",
  "placeholder names the hidden count")

-- no mods installed: the vanilla NO MODS INSTALLED row is untouched
rows = stateWith({}):modRows()
T.eq(#rows, 1, "empty list: one row")
T.eq(rows[1].header and rows[1].label, "NO MODS INSTALLED",
  "vanilla empty-list header kept")

-- the options screen's INSTALLED count follows the same filter (Gen 1/2 hook)
local Runtime = require("src.mods.Runtime")
local game = { modStatus = { available = avail } }
local vanillaRows = { { id = "mods", label = "MODS",
                        value = function() return "VANILLA" end } }
local out = Runtime.call("ui.options.rows",
  function(g, r) return r end, game, vanillaRows)
setOptions({ hide_disabled = "on", hide_other_games = "on" })
T.eq(out[1].value(game), "3 INSTALLED", "count follows the filters")
setOptions(nil)
T.eq(out[1].value(game), "5 INSTALLED", "count is vanilla with filters OFF")

run.release()
T.finish("cleaner_mod_options")
