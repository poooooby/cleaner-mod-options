-- Cleaner Mod Options -- tidies the in-game mod list (START > OPTIONS > MODS).
--
-- Two settings, both OFF out of the box (OPTIONS > MODS > Cleaner Mod
-- Options): HIDE DISABLED hides mods that were disabled at boot, HIDE OTHER
-- GAMES hides mods that cannot run on the game being played. This mod targets
-- every game and is loaded whenever its filters apply, so its own entry --
-- and with it these settings -- can never filter itself away.
--
-- Everything here is a view change over `ManagerState:modRows()`'s returned
-- rows. The loader's `status.available` list is never touched: profiles,
-- staging, load order and the launcher all keep seeing every installed mod.
--
-- Hook points (engine_internals; each degrades to vanilla with a logged
-- warning when an engine update moves it):
--   src/mods/ManagerState.lua modRows()      the list itself, all three gens
--   ui.options.rows hook                     "N INSTALLED" count, Gen 1/2
--   src/ui/game3/option_rows.lua Rows.build  "N INSTALLED" count, Gen 3

-- A mod's own files load as chunks through mod:read; require() cannot see
-- them (same pattern as modern_spawns).
local function loadSibling(mod, name)
  local source = mod:read(name)
  if not source then
    mod.log:error("%s is missing -- reinstall the mod; the list stays vanilla", name)
    return nil
  end
  local chunk, err = load(source, "@" .. (mod.path or "cleaner_mod_options") .. "/" .. name)
  if not chunk then
    mod.log:error("%s failed to compile (%s) -- reinstall the mod", name, tostring(err))
    return nil
  end
  local ok, result = pcall(chunk)
  if not ok then
    mod.log:error("%s errored while loading (%s) -- reinstall the mod", name, tostring(result))
    return nil
  end
  return result
end

-- Patches survive a hot reload through a slot on the engine module: the
-- wrapper is installed once per process, and each (re)load of this entry
-- swaps in a fresh `apply` bound to the live mod api.
local SLOT = "__cleaner_mod_options"

return function(mod)
  local MOD_ID = mod.id or "cleaner_mod_options"

  local schema = loadSibling(mod, "options.lua")
  if type(schema) == "table" then mod.options:define(schema) end

  -- A reload that drops this mod (uninstalled, disabled, failed) builds a new
  -- loader without re-running this entry, so the module-level wrappers keep
  -- the old `apply` and its old option values. They filter only while the
  -- game's live loader still has this mod loaded; otherwise the list and
  -- count are vanilla. No game or loader to ask means vanilla too.
  local function isLive(game)
    local loader = type(game) == "table" and game.mods
    local mods = type(loader) == "table" and loader.mods
    local rec = type(mods) == "table" and mods[MOD_ID]
    return type(rec) == "table" and rec.state == "loaded" and not rec.failed
  end

  local warned = {}
  local function warnOnce(key, fmt, ...)
    if warned[key] then return end
    warned[key] = true
    mod.log:warn(fmt, ...)
  end

  local function optOn(key)
    local ok, value = pcall(function() return mod.options:get(key) end)
    return ok and value == "on"
  end

  -- guarded engine requires: a future engine that moves one of these costs
  -- the feature it backs, never a crash
  local function tryRequire(name)
    local ok, result = pcall(require, name)
    if ok and result ~= nil then return result end
    return nil
  end

  local Strings = tryRequire("src.core.Strings")
  local GameVersion = tryRequire("src.core.GameVersion")
  local ModTargets = tryRequire("src.mods.ModTargets")

  local function fmt(s, ...)
    if Strings then return Strings(s, ...) end
    if select("#", ...) > 0 then return s:format(...) end
    return s
  end

  -- A mod flipped since boot is never hidden: hiding the row the player just
  -- toggled would strand the staged change with no way to undo it in-game.
  -- Mirrors ManagerState:isStaged / bootEnabled.
  local function isStaged(m)
    return (m.enabled and true or false) ~= (m.state ~= "disabled")
  end

  -- runs-here for the count sites, which have no ManagerState instance;
  -- same derivation as ManagerState:runsHere. Forced "TRY HERE ANYWAY" mods
  -- count as running here. Unanswerable (modules moved) means visible.
  local function runsHere(m)
    if not (GameVersion and ModTargets) then return true end
    local version = GameVersion.get()
    return ModTargets.runsHere(m, version, GameVersion.generation(version),
                               m.gen2Forced)
  end

  local function hiddenManifest(m, hideDisabled, hideOther)
    if type(m) ~= "table" then return false end
    if hideDisabled and m.state == "disabled" and not isStaged(m) then return true end
    if hideOther and not runsHere(m) then return true end
    return false
  end

  local function countVisible(status)
    local hideDisabled = optOn("hide_disabled")
    local hideOther = optOn("hide_other_games")
    local n = 0
    for _, m in ipairs((status and status.available) or {}) do
      if not hiddenManifest(m, hideDisabled, hideOther) then n = n + 1 end
    end
    return n
  end

  -- ------- the list itself: ManagerState.modRows, shared by all three gens

  -- state is the live ManagerState, so staging and TRY HERE ANYWAY use its
  -- own answers (isStaged, runsHere handle the injected-generation seam)
  local function hiddenRow(state, m, hideDisabled, hideOther)
    if hideDisabled and m.state == "disabled" and not state:isStaged(m) then
      return true
    end
    if hideOther and not state:runsHere(m) then return true end
    return false
  end

  -- Filters the ROWS modRows returned, never status.available. Headers whose
  -- every mod row was hidden are dropped with them; a list filtered down to
  -- nothing gets a placeholder so the screen never goes blank.
  local function filterRows(state, rows, hideDisabled, hideOther)
    local out, hidden, pendingHeader = {}, 0, nil
    for _, row in ipairs(rows) do
      if type(row) ~= "table" then
        out[#out + 1] = row
      elseif row.header then
        pendingHeader = row
      elseif row.mod and hiddenRow(state, row.mod, hideDisabled, hideOther) then
        hidden = hidden + 1
      else
        if pendingHeader then
          out[#out + 1] = pendingHeader
          pendingHeader = nil
        end
        out[#out + 1] = row
      end
    end
    if hidden == 0 then return rows end
    if #out == 0 then
      out[1] = { header = true, label = fmt("ALL MODS HIDDEN (%d)", hidden) }
    end
    return out
  end

  local ManagerState = tryRequire("src.mods.ManagerState")
  if type(ManagerState) == "table" and type(ManagerState.modRows) == "function" then
    local slot = rawget(ManagerState, SLOT)
    if not slot then
      slot = {}
      ManagerState[SLOT] = slot
      local origModRows = ManagerState.modRows
      ManagerState.modRows = function(self, ...)
        local rows = origModRows(self, ...)
        if slot.apply then return slot.apply(self, rows) end
        return rows
      end
    end
    slot.apply = function(state, rows)
      if type(rows) ~= "table" then return rows end
      if not isLive(type(state) == "table" and state.game) then return rows end
      local hideDisabled = optOn("hide_disabled")
      local hideOther = optOn("hide_other_games")
      if not (hideDisabled or hideOther) then return rows end
      local ok, filtered = pcall(filterRows, state, rows, hideDisabled, hideOther)
      if not ok then
        warnOnce("modRows", "mod list filter failed (%s) -- showing the vanilla" ..
          " list; an engine update likely changed ManagerState", tostring(filtered))
        return rows
      end
      return filtered
    end
  else
    warnOnce("ManagerState", "src.mods.ManagerState.modRows not found -- the" ..
      " mod list stays vanilla; an engine update likely moved it")
  end

  -- ------- "N INSTALLED" on the options screen

  -- wraps a mods row's value closure; the vanilla label is the fallback.
  -- `gated` is for wrappers that outlive a reload (see isLive).
  local function wrapCountValue(row, gameOf, gated)
    local origValue = row.value
    row.value = function(ctx, ...)
      local game = gameOf(ctx)
      if not gated or isLive(game) then
        local ok, label = pcall(function()
          return fmt("%d INSTALLED", countVisible(game and game.modStatus))
        end)
        if ok and label ~= nil then return label end
      end
      return origValue(ctx, ...)
    end
  end

  -- Gen 1/2: the supported hook. Rows are rebuilt per menu open, so wrapping
  -- in place never stacks. The hook dies with its loader, so it needs no gate.
  mod.hooks:wrap("ui.options.rows", function(next_, game, rows)
    local out = next_(game, rows)
    if type(out) ~= "table" then return out end
    for _, row in ipairs(out) do
      if type(row) == "table" and row.id == "mods"
        and type(row.value) == "function" then
        wrapCountValue(row, function(g) return g end, false)
        break
      end
    end
    return out
  end)

  -- Gen 3 has no hook at its options rows; wrap the row builder itself.
  if mod.generation == 3 then
    local Rows = tryRequire("src.ui.game3.option_rows")
    if type(Rows) == "table" and type(Rows.build) == "function" then
      local slot = rawget(Rows, SLOT)
      if not slot then
        slot = {}
        Rows[SLOT] = slot
        local origBuild = Rows.build
        Rows.build = function(...)
          local rows = origBuild(...)
          if slot.apply then pcall(slot.apply, rows) end
          return rows
        end
      end
      slot.apply = function(rows)
        for _, row in ipairs(type(rows) == "table" and rows or {}) do
          if type(row) == "table" and row.id == "mods"
            and type(row.value) == "function" then
            wrapCountValue(row, function(c) return c and c.game end, true)
            return
          end
        end
      end
    else
      warnOnce("gen3rows", "src.ui.game3.option_rows.build not found -- the" ..
        " Gen 3 INSTALLED count stays vanilla; an engine update likely moved it")
    end
  end
end
