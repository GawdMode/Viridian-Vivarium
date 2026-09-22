local DEV_SCREEN = "VFR_TILE_MARKER"
local CAPTURE_SCREEN = "VFR_FIELD_NET_CAPTURE"
local VIVARIUM_SCREEN = "VFR_VIVARIUM_SCREEN"
local LOGBOOK_SCREEN = "VFR_LOGBOOK_SCREEN"
local LOGBOOK_DIALOGUE = "VFR_LOGBOOK_DIALOGUE"
local DONATION_SCREEN = "VFR_DONATION_SCREEN"
local DONATE_SCREEN = "VFR_DONATE_SCREEN"
local FIELD_NET = "VFR_FIELD_NET"
local JAXEN_SHOP_SCREEN = "VFR_JAXEN_SHOP"
local FERN_SHOP_SCREEN = "VFR_FERN_SHOP"
local SCENT_SPRAY = "VFR_SCENT_SPRAY"
local FUNGI_SPORES = "VFR_FUNGI_SPORES"
local SPARKLE_BITS = "VFR_SPARKLE_BITS"
local BERRY_SEED = "VFR_BERRY_SEED"
local SHINY_NET = "VFR_SHINY_NET"
local FERTILIZER = "VFR_FERTILIZER"

return function(mod)
  mod.log:info("viridian_vivarium: loading v1.0.0")

  local World = require("src.world.gen2.World")
  local Map = require("src.world.gen2.Map")
  local Permissions = require("src.world.gen2.Permissions")
  local Bag = require("src.inventory.Bag")
  local Screens = require("src.ui.Screens")
  local PartyMenu = require("src.ui.PartyMenu")
  local Sprites = require("src.pokemon.Sprites")
  local SpriteRenderer = require("src.render.SpriteRenderer")
  local Sound = require("src.core.Sound")
  local Clock = require("src.core.gen2.Clock")
  local GbcPalette = require("src.render.GbcPalette")
  local Assets = require("src.render.Assets")
  local Palettes = require("src.world.gen2.Palettes")
  local Chrome = require("src.ui.gen2.Chrome")
  local SummaryMenu = require("src.ui.gen2.SummaryMenu")
  local PhotoStudio = require("src.ui.gen2.PhotoStudio")
  local Gen2BattleState = require("src.ui.gen2.BattleState")
  local BattleAnimView = require("src.ui.gen2.BattleAnimView")
  local Gen2BoxMenu = require("src.ui.gen2.BoxMenu")
  local EvolutionAnim = require("src.ui.gen2.EvolutionAnim")
  local CoreEvolution = require("src.core.gen2.Evolution")
  local TradeAnimView = require("src.ui.gen2.TradeAnim")
  local HallOfFameView = require("src.ui.gen2.HallOfFame")
  local HallOfFameCore = require("src.core.gen2.HallOfFame")
  local MartMenu = require("src.ui.gen2.MartMenu")
  local Boxes = require("src.core.gen2.Boxes")
  local Mail = require("src.core.gen2.Mail")
  local Mon = require("src.battle.gen2.Mon")
  local Catching = require("src.battle.gen2.Catching")
  local Runtime = require("src.mods.Runtime")
  local STATION, ROUTE = "VFR_FIELD_STATION", "ROUTE_2"

  local primeSymbolImage
  local function loadPrimeSymbolImage()
    if primeSymbolImage ~= nil then
      return primeSymbolImage or nil
    end
    local ok, image = pcall(love.graphics.newImage, mod.path .. "/assets/prime_symbol.png")
    if ok and image then
      image:setFilter("nearest", "nearest")
      primeSymbolImage = image
    else
      primeSymbolImage = false
      mod.log:error("Viridian Vivarium: failed to load prime symbol image: %s", tostring(image))
    end
    return primeSymbolImage or nil
  end

  local function drawPrimeSymbolAtTile(tx, ty)
    local image = loadPrimeSymbolImage()
    if not image then return false end
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(image, (tx or 0) * 8, (ty or 0) * 8)
    return true
  end

  local function copy(v)
    if type(v) ~= "table" then return v end
    local o = {}
    for k, x in pairs(v) do o[k] = copy(x) end
    return o
  end

  local maps = mod.game and mod.game.data and mod.game.data.gen2Maps
  if not (maps and maps[ROUTE] and maps.KURTS_HOUSE) then
    mod.log:error("Viridian Vivarium: Route 2 or Kurt's House unavailable")
    return
  end

  local route, kurt = maps[ROUTE], maps.KURTS_HOUSE
  local tilesets = mod.game and mod.game.data and mod.game.data.gen2Tilesets
  local routeTileset = tilesets and tilesets[route.tileset]
  local function bidx(x, y) return y * route.width + x + 1 end

  ---------------------------------------------------------------------------
  -- ROLLBACK BASE: DEV5
  -- Keep DEV5's exterior map edits exactly as they were.  DEV10 does NOT
  -- touch, move, cover, or replace any bushes.
  ---------------------------------------------------------------------------
  local SRC_BX, SRC_BY = 5, 5
  local DST_BX, DST_BY = 1, 4
  local BUILD_W, BUILD_H = 4, 4
  local DOOR_X, DOOR_Y = 7, 13
  local SIGN_X, SIGN_Y = 6, 14

  local routeBlocks = copy(route.blocks or {})
  local originalBlocks = copy(route.blocks or {})
  for dy = 0, BUILD_H - 1 do
    for dx = 0, BUILD_W - 1 do
      local srcIndex = bidx(SRC_BX + dx, SRC_BY + dy)
      local dstIndex = bidx(DST_BX + dx, DST_BY + dy)
      local block = originalBlocks[srcIndex]
      if block ~= nil then routeBlocks[dstIndex] = block end
    end
  end

  -- This is part of DEV5 itself, so preserve it verbatim in the rollback.
  local openBlock = originalBlocks[bidx(DST_BX, DST_BY + BUILD_H)]
      or originalBlocks[bidx(DST_BX + 1, DST_BY + BUILD_H)]
      or originalBlocks[1]
  routeBlocks[bidx(DST_BX, DST_BY)] = openBlock
  routeBlocks[bidx(DST_BX, DST_BY + 1)] = openBlock

  ---------------------------------------------------------------------------
  -- SURGICAL BUSH REMOVAL
  -- The VIV DEV tool identified the unwanted bushes at Route 2 cells
  -- (2,15) and (4,15).  Instead of drawing overlays, clone only the two
  -- containing metatiles and replace each bush cell's 2x2 tile quadrant with
  -- the already-empty ground quadrant from cell (3,15).  This changes the
  -- actual map graphics and collision tiles for exactly those two cells.
  ---------------------------------------------------------------------------
  if routeTileset and routeTileset.blocks then
    local tilesetBlocks = copy(routeTileset.blocks)
    local tilesetCollision = copy(routeTileset.collision or {})

    local function blockCellQuartet(mapBlocks, tilesetBlockRows, cx, cy)
      local bx, by = math.floor(cx / 2), math.floor(cy / 2)
      local blockId = mapBlocks[bidx(bx, by)]
      local row = tilesetBlockRows[(blockId or 0) + 1]
      if not row then return nil end
      local localCellX, localCellY = cx % 2, cy % 2
      local tx0, ty0 = localCellX * 2, localCellY * 2
      return {
        row[ty0 * 4 + tx0 + 1],
        row[ty0 * 4 + tx0 + 2],
        row[(ty0 + 1) * 4 + tx0 + 1],
        row[(ty0 + 1) * 4 + tx0 + 2],
      }
    end

    -- Shared Kanto tileset compatibility:
    -- Dungeon Delvers / Pewter Dungeon uses custom metatile ID 128 for the
    -- restored Pewter Museum doorway.  A tileset registry patch containing a
    -- normal Lua array replaces the whole blocks list, so merely skipping ID
    -- 128 is not enough: VFR must carry the actual doorway row forward in the
    -- blocks array it submits, otherwise its later merge erases the door.
    --
    -- Rebuild the same hybrid block Dungeon Delvers uses: start from the
    -- museum wall metatile at cell (14,7), then transplant the Gym doorway's
    -- lower-left 16x16 quadrant from cell (16,17).  This is harmless when
    -- Dungeon Delvers is absent because block 128 is not referenced by any
    -- vanilla Kanto map.  VFR's own custom Route 2 blocks begin at ID 129.
    local pewter = maps and maps.PEWTER_CITY
    if pewter and pewter.tileset == route.tileset and routeTileset.blocks then
      local function mapBlockIndex(def, cx, cy)
        return math.floor(cy / 2) * def.width + math.floor(cx / 2) + 1
      end
      local museumIndex = mapBlockIndex(pewter, 14, 7)
      local gymIndex = mapBlockIndex(pewter, 16, 17)
      local museumBlockId = pewter.blocks and pewter.blocks[museumIndex]
      local gymDoorBlockId = pewter.blocks and pewter.blocks[gymIndex]
      local museumRow = museumBlockId and routeTileset.blocks[museumBlockId + 1]
      local gymDoorRow = gymDoorBlockId and routeTileset.blocks[gymDoorBlockId + 1]
      if museumRow and gymDoorRow then
        local hybrid = copy(museumRow)
        for _, i in ipairs({9, 10, 13, 14}) do hybrid[i] = gymDoorRow[i] end
        tilesetBlocks[129] = hybrid -- block ID 128, reserved for Dungeon Delvers
      end
    end
    if tilesetBlocks[129] == nil then
      -- Keep the array contiguous even on an unexpected/custom Kanto layout.
      tilesetBlocks[129] = copy(tilesetBlocks[128] or tilesetBlocks[1])
    end
    local nextVfrBlockId = 129

    local function cellCollisionFrom(blockRows, mapBlocks, cx, cy)
      local bx, by = math.floor(cx / 2), math.floor(cy / 2)
      local blockId = mapBlocks[bidx(bx, by)]
      local row = blockRows[(blockId or 0) + 1]
      if not row then return nil end
      return row[(cy % 2) * 2 + (cx % 2) + 1]
    end

    local function replaceCellWithQuartet(cx, cy, quartet, collisionValue)
      local bx, by = math.floor(cx / 2), math.floor(cy / 2)
      local mapIndex = bidx(bx, by)
      local oldBlockId = routeBlocks[mapIndex]
      local oldRow = tilesetBlocks[(oldBlockId or 0) + 1]
      if not oldRow then return false end

      while nextVfrBlockId <= 255 and tilesetBlocks[nextVfrBlockId + 1] ~= nil do
        nextVfrBlockId = nextVfrBlockId + 1
      end
      if nextVfrBlockId > 255 then return false end

      local newRow = copy(oldRow)
      local localCellX, localCellY = cx % 2, cy % 2
      local tx0, ty0 = localCellX * 2, localCellY * 2
      newRow[ty0 * 4 + tx0 + 1] = quartet[1]
      newRow[ty0 * 4 + tx0 + 2] = quartet[2]
      newRow[(ty0 + 1) * 4 + tx0 + 1] = quartet[3]
      newRow[(ty0 + 1) * 4 + tx0 + 2] = quartet[4]

      local blockId = nextVfrBlockId
      tilesetBlocks[blockId + 1] = newRow

      -- Custom metatiles also need a collision row. Start from the target
      -- block's collision and only replace the edited 16x16 cell. This keeps
      -- the rest of Route 2 byte-for-byte equivalent while letting the native
      -- sign behave like a real solid sign tile instead of an NPC sprite.
      local oldCollision = tilesetCollision[(oldBlockId or 0) + 1]
      if oldCollision then
        local newCollision = copy(oldCollision)
        if collisionValue ~= nil then
          newCollision[(cy % 2) * 2 + (cx % 2) + 1] = collisionValue
        end
        tilesetCollision[blockId + 1] = newCollision
      end

      routeBlocks[mapIndex] = blockId
      nextVfrBlockId = blockId + 1
      return true
    end

    local groundQuartet = blockCellQuartet(originalBlocks, routeTileset.blocks, 3, 15)
    local groundCollision = cellCollisionFrom(routeTileset.collision or {}, originalBlocks, 3, 15)
    if groundQuartet then
      replaceCellWithQuartet(2, 15, groundQuartet, groundCollision)
      replaceCellWithQuartet(4, 15, groundQuartet, groundCollision)
    else
      mod.log:error("Viridian Vivarium: could not read ground template cell 3,15")
    end

    -- DEV66: Route 2's actual native sign is the bg_event at (11,9).
    -- Clone that real 16x16 map cell into the Vivarium sign position so it
    -- inherits the same artwork, collision, and player-overlap behavior.
    local nativeSignQuartet = blockCellQuartet(originalBlocks, routeTileset.blocks, 11, 9)
    local nativeSignCollision = cellCollisionFrom(routeTileset.collision or {}, originalBlocks, 11, 9)
    if nativeSignQuartet then
      replaceCellWithQuartet(SIGN_X, SIGN_Y, nativeSignQuartet, nativeSignCollision)
    else
      mod.log:error("Viridian Vivarium: could not read native Route 2 sign cell 11,9")
    end

        mod.content.tilesets:patch(route.tileset, {
      blocks = tilesetBlocks, collision = tilesetCollision,
    })
  else
    mod.log:error("Viridian Vivarium: Route 2 tileset unavailable")
  end

  ---------------------------------------------------------------------------
  -- SPRITES
  -- Terrarium sprites only. The exterior Vivarium sign is a true Route 2
  -- map-cell clone from the native sign at (11,9).
  ---------------------------------------------------------------------------
  for r = 0, 1 do
    for c = 0, 3 do
      local id = "VFR_TERRARIUM_" .. r .. "_" .. c
      mod.content.sprites:register(id, {
        id = id,
        image = mod.path .. "/assets/terrarium_" .. r .. "_" .. c .. ".png",
        frames = 1,
        walker = false,
        trueColor = true,
        spriteType = "STILL_SPRITE",
      })
    end
  end

  ---------------------------------------------------------------------------
  -- INTERIOR: unchanged from DEV5
  ---------------------------------------------------------------------------
  local room = copy(kurt)
  room.id = STATION
  room.label = "ViridianVivarium"
  room.name = "VIRIDIAN VIVARIUM"
  room.index = 1001
  -- Kurt's House normally inherits AZALEA TOWN as its landmark, which raises
  -- the AZALEA TOWN map-name placard on entry. This custom room belongs to
  -- Route 2, so keep its landmark aligned with the exterior instead.
  room.landmark = route.landmark
  room.objects = {}
  room.signs = {}
  room.bgEvents = {}
  room.sceneScripts = {
    [0] = { sceneId = 0, scriptKey = "VFR_VIVARIUM_INTRO_MAIN" },
  }

  local routeWarps = copy(route.warps or {})
  local exteriorWarpIndex = #routeWarps + 1

  room.warps = copy(kurt.warps or {})
  if #room.warps == 0 then
    room.warps = {{ x = 3, y = 7, destMap = ROUTE, destWarp = exteriorWarpIndex }}
  else
    for _, w in ipairs(room.warps) do
      w.destMap = ROUTE
      w.destWarp = exteriorWarpIndex
    end
  end

  local nextIndex = 0
  local TERR_X, TERR_Y = 12, 1
  for r = 0, 1 do
    for c = 0, 3 do
      nextIndex = nextIndex + 1
      room.objects[#room.objects + 1] = {
        index = nextIndex,
        sprite = "VFR_TERRARIUM_" .. r .. "_" .. c,
        x = TERR_X + c,
        y = TERR_Y + r,
        movement = 1,
        vfrRole = "terrarium",
      }
    end
  end

  -- Restoration Project staff.  Their positions mirror the user's mockup:
  -- JAXEN on the left, FERN on the right, facing one another until the intro
  -- pulls the player up from the doorway.
  nextIndex = nextIndex + 1
  local JAXEN_OBJECT_INDEX = nextIndex
  room.objects[#room.objects + 1] = {
    index = JAXEN_OBJECT_INDEX,
    sprite = "SPRITE_FISHING_GURU",
    x = 6, y = 3, movement = 1,
    vfrRole = "jaxen",
  }

  nextIndex = nextIndex + 1
  local FERN_OBJECT_INDEX = nextIndex
  room.objects[#room.objects + 1] = {
    index = FERN_OBJECT_INDEX,
    sprite = "SPRITE_GRANNY",
    x = 9, y = 4, movement = 1,
    vfrRole = "fern",
  }

  -- Native Crystal book sprite, matching the Angler's Cove logbook approach.
  -- JAXEN now stands at (6,3), so the logbook sits one tile right and one
  -- tile down from him, on the adjacent table at (7,4).
  local nativeBook
  local spriteDefs = mod.game and mod.game.data and mod.game.data.gen2Sprites
  if spriteDefs then
    for id, _ in pairs(spriteDefs) do
      if type(id) == "string" and id:find("BOOK", 1, true) then nativeBook = id break end
    end
    if not nativeBook then
      for id, _ in pairs(spriteDefs) do
        if type(id) == "string" and (id:find("NOTE", 1, true) or id:find("POKEDEX", 1, true)) then
          nativeBook = id break
        end
      end
    end
  end
  if nativeBook then
    nextIndex = nextIndex + 1
    room.objects[#room.objects + 1] = {
      index = nextIndex,
      sprite = nativeBook,
      x = 7, y = 4, movement = 1,
      vfrRole = "logbook",
    }
  end

  mod.content.maps:register(STATION, room)

  ---------------------------------------------------------------------------
  -- EXTERIOR: DEV5 + TRUE NATIVE ROUTE 2 SIGN TILE
  ---------------------------------------------------------------------------
  local routeObjects = copy(route.objects or {})
  local maxIndex = 0
  for _, obj in ipairs(routeObjects) do
    if type(obj.index) == "number" and obj.index > maxIndex then maxIndex = obj.index end
  end
  routeWarps[#routeWarps + 1] = {
    x = DOOR_X,
    y = DOOR_Y,
    destMap = STATION,
    destWarp = 1,
  }

  mod.content.maps:patch(ROUTE, {
    blocks = routeBlocks,
    warps = routeWarps,
    objects = routeObjects,
  })

  ---------------------------------------------------------------------------
  -- EXACT CELL SEMANTICS
  -- Route 2 cell (2,15) is visually plain ground after the bush removal, but
  -- its inherited COLL_* value still behaves like a current/warp-style tile
  -- and forces the player downward while standing on it.  Make this ONE cell
  -- ordinary LAND collision (0x00): walkable, no current, no ledge, no warp.
  ---------------------------------------------------------------------------
  if not Map.__vfrDev19CellCollision then
    Map.__vfrDev19CellCollision = true
    local vanillaCellCollision = Map.cellCollision
    function Map:cellCollision(cx, cy)
      if self and self.def and self.def.id == ROUTE
          and cx == 2 and cy == 15 then
        return 0x00
      end
      return vanillaCellCollision(self, cx, cy)
    end
  end

  ---------------------------------------------------------------------------
  -- SURGICAL COLLISION CLEAR
  -- User-marked Route 2 cells: (3,14) and (2,14).
  --
  -- DEV16 tried to loosen Map:isWalkableCell / stepPermitted, but player
  -- movement is ultimately decided by Collision.canMove and the engine's
  -- movement.collision hook.  DEV17 fixes this at that final decision point:
  -- only a TILE collision involving either marked cell is overridden. Bounds
  -- and entity collisions are still respected.
  ---------------------------------------------------------------------------
  mod.hooks:wrap("movement.collision", function(nextFn, allowed, ctx)
    local result = nextFn(allowed, ctx)
    local map = ctx and ctx.map
    local mapId = map and ((map.def and map.def.id) or map.id)
    if mapId ~= ROUTE then return result end

    -- The user wants (4,14) to be solid again.  Block ENTRY to that cell even
    -- when leaving one of our custom walkable cells next to it.
    if ctx.toX == 4 and ctx.toY == 14 then
      ctx.reason = "tile"
      return false
    end

    local function markedDestination(x, y)
      return (x == 3 and y == 14)
          or (x == 2 and y == 14)
          or (x == 4 and y == 15)
          or (x == 2 and y == 15)
          or (x == 3 and y == 15)
    end

    -- Important: only the DESTINATION is whitelisted.  DEV18 also checked
    -- ctx.fromX/fromY, which meant standing on a whitelisted cell accidentally
    -- made every adjacent destination passable (including 4,14).
    if ctx.reason == "tile" and markedDestination(ctx.toX, ctx.toY) then
      ctx.reason = nil
      return true
    end
    return result
  end, 100, "vfr_clear_marked_cells")

  ---------------------------------------------------------------------------
  -- NORMAL WALK-THROUGH CELLS
  -- User-marked cells (4,15) and (2,15) remain walkable. (2,15) is also
  -- normalized above to plain LAND so it has no forced-movement effect.
  -- The ledge guard remains as a belt-and-suspenders fallback for these cells.
  
  ---------------------------------------------------------------------------
  if not Map.__vfrDev18StepPermitted then
    Map.__vfrDev18StepPermitted = true
    local vanillaStepPermitted = Map.stepPermitted
    local normalCells = {
      ["4,15"] = true,
      ["2,15"] = true,
    }
    function Map:stepPermitted(cx, cy, dir)
      if self and self.def and self.def.id == ROUTE then
        local d = Map.DELTA[dir]
        local tx = d and (cx + d[1]) or cx
        local ty = d and (cy + d[2]) or cy
        if normalCells[cx .. "," .. cy] or normalCells[tx .. "," .. ty] then
          return true
        end
      end
      return vanillaStepPermitted(self, cx, cy, dir)
    end
  end

  if not World.__vfrDev18LedgeNeutralized then
    World.__vfrDev18LedgeNeutralized = true
    local vanillaTryLedgeJump = World.tryLedgeJump
    function World:tryLedgeJump(dir)
      local p = self.player
      local map = self.map
      if map and map.id == ROUTE and p then
        if (p.cellX == 4 and p.cellY == 15)
            or (p.cellX == 2 and p.cellY == 15) then
          return false
        end
      end
      return vanillaTryLedgeJump(self, dir)
    end
  end

  ---------------------------------------------------------------------------
  -- FIELD NET + CAPTURE SYSTEM
  ---------------------------------------------------------------------------
  mod.content.items:register(FIELD_NET, {
    id = FIELD_NET,
    name = "FIELD NET",
    price = 0,
    keyItem = true,
    tossable = false,
    canToss = false,
    canSelect = true,
    pocket = "KEY_ITEM",
    pocketId = 2,
    fieldMenu = "ITEMMENU_CLOSE",
    battleMenu = "ITEMMENU_NOUSE",
    description = "Scan nearby grass.<NEXT>Finds hidden PKMN.",
  })

  -- Donation-milestone shop stock.  Consumables live in the ITEM pocket; the
  -- SHINY NET is a passive one-time KEY ITEM upgrade.  Prices are deliberately
  -- easy to tune while the loop is still in DEV.
  mod.content.items:register(SCENT_SPRAY, {
    id = SCENT_SPRAY, name = "SCENT SPRAY", price = 600, pocket = "ITEM",
    tossable = true, canToss = true, canSelect = false,
    fieldMenu = "ITEMMENU_CURRENT", battleMenu = "ITEMMENU_NOUSE",
    description = "Makes grass stir.<NEXT>Lasts 100 steps.",
  })
  mod.content.items:register(FUNGI_SPORES, {
    id = FUNGI_SPORES, name = "FUNGI SPORES", price = 800, pocket = "ITEM",
    tossable = true, canToss = true, canSelect = false,
    fieldMenu = "ITEMMENU_NOUSE", battleMenu = "ITEMMENU_NOUSE",
    description = "Plant in VIV soil.<NEXT>Grows mushrooms.",
  })
  mod.content.items:register(SPARKLE_BITS, {
    id = SPARKLE_BITS, name = "SPARKLE BITS", price = 2500, pocket = "ITEM",
    tossable = true, canToss = true, canSelect = false,
    fieldMenu = "ITEMMENU_NOUSE", battleMenu = "ITEMMENU_NOUSE",
    description = "Scatter in VIV.<NEXT>May change PKMN.",
  })
  mod.content.items:register(BERRY_SEED, {
    id = BERRY_SEED, name = "BERRY SEED", price = 600, pocket = "ITEM",
    tossable = true, canToss = true, canSelect = false,
    fieldMenu = "ITEMMENU_NOUSE", battleMenu = "ITEMMENU_NOUSE",
    description = "Plant in VIV soil.<NEXT>Grows a BERRY.",
  })
  mod.content.items:register(SHINY_NET, {
    id = SHINY_NET, name = "SHINY NET", price = 15000, pocket = "KEY_ITEM",
    pocketId = 2, keyItem = true, tossable = false, canToss = false, canSelect = true,
    -- The SHINY NET is used exactly like the FIELD NET. Its scan has the same
    -- rustling-grass behavior, but each generated target gets boosted shiny odds.
    fieldMenu = "ITEMMENU_CLOSE", battleMenu = "ITEMMENU_NOUSE",
    description = "Scan nearby grass.<NEXT>Better shiny odds.",
  })
  mod.content.items:register(FERTILIZER, {
    id = FERTILIZER, name = "FERTILIZER", price = 1000, pocket = "ITEM",
    tossable = true, canToss = true, canSelect = false,
    fieldMenu = "ITEMMENU_NOUSE", battleMenu = "ITEMMENU_NOUSE",
    description = "Use on VIV plots.<NEXT>Boosts harvest.",
  })

  local SCENT_SPRAY_STEPS = 100
  local SHINY_NET_ODDS = 512
  local SPARKLE_SHINY_CHANCE = 0.10
  local SPARKLE_PRIME_CHANCE = 0.05
  local PRIME_BST_BONUS = 40
  local BERRY_SEED_RESULTS = {
    "BERRY", "PSNCUREBERRY", "PRZCUREBERRY", "BURNT_BERRY", "ICE_BERRY",
    "BITTER_BERRY", "MINT_BERRY", "MIRACLEBERRY", "MYSTERYBERRY", "GOLD_BERRY",
  }

  -- DEV50: the FIELD NET is now a real introduction reward from JAXEN rather
  -- than being silently injected into every save. Existing dev saves that
  -- already own it keep it naturally; new players receive it during the
  -- Vivarium entrance scene.
  local function grantFieldNet(save, game)
    if not (save and save.inventory) then return false end
    if save.inventory[FIELD_NET] then return true end
    local data = (game and game.data) or (mod.game and mod.game.data)
    return Bag.add(save, FIELD_NET, 1, data and data.items)
  end

  mod.content.commands:register("vfr:give_field_net", {
    foreground = true,
    fn = function(_ctx)
      local game = mod.game
      if game and grantFieldNet(game.save, game) then
        pcall(function() Sound.playStereo(game.data, "Sfx_Item") end)
      end
    end,
  })

  mod.content.commands:register("vfr:face_jaxen_left", {
    foreground = true,
    fn = function(_ctx)
      local world = mod.game and mod.game.world
      if not world then return end
      for _, npc in pairs(world.npcPool or {}) do
        if npc and npc.def and npc.def.vfrRole == "jaxen" then
          npc.facing = "left"
          return
        end
      end
    end,
  })

  mod.content.commands:register("vfr:finish_intro", {
    foreground = true,
    fn = function(_ctx)
      mod.save:set("vfrVivariumIntroComplete", true)
      local world = mod.game and mod.game.world
      if world then world.mapScenes[STATION] = 1 end
    end,
  })

  local Font = mod.ui.Font
  local fieldNetBgDay
  local fieldNetBgMorning
  local fieldNetBgNight
  local fieldNetCursor
  pcall(function() fieldNetBgDay = mod.assets:image("assets/field_net_bg_day.png") end)
  pcall(function() fieldNetBgMorning = mod.assets:image("assets/field_net_bg_morning.png") end)
  pcall(function() fieldNetBgNight = mod.assets:image("assets/field_net_bg_night.png") end)
  if not fieldNetBgDay then
    pcall(function() fieldNetBgDay = mod.assets:image("assets/field_net_bg.png") end)
  end
  pcall(function() fieldNetCursor = mod.assets:image("assets/field_net_cursor.png") end)
  pcall(function()
    if fieldNetCursor then fieldNetCursor:setFilter("nearest", "nearest") end
  end)

  local function fieldNetBackground(game)
    local hour
    pcall(function() hour = Clock.hour(game and game.save) end)
    local tod = "DAY"
    local ok, Palettes = pcall(require, "src.world.gen2.Palettes")
    if ok and Palettes and Palettes.clockDaytime then
      tod = Palettes.clockDaytime(hour) or tod
    end
    if tod == "MORN" then return fieldNetBgMorning or fieldNetBgDay or fieldNetBgNight end
    if tod == "NITE" then return fieldNetBgNight or fieldNetBgDay or fieldNetBgMorning end
    return fieldNetBgDay or fieldNetBgMorning or fieldNetBgNight
  end

  -- Reuse Crystal's own overworld Poké Ball sprite for the successful net
  -- capture animation. If an older cache lacks it, draw a tiny fallback ball.
  local fieldNetBallImage, fieldNetBallQuad, fieldNetBallColors
  local fieldNetBallResolved = false
  local function resolveFieldNetBall(game)
    if fieldNetBallResolved then return fieldNetBallImage end
    fieldNetBallResolved = true
    local data = game and game.data or {}
    local def = data.gen2Sprites and data.gen2Sprites.SPRITE_POKE_BALL
    if not (def and def.image) then return nil end
    local ok, img = pcall(Assets.image, def.image)
    if not (ok and img) then return nil end
    pcall(function() img:setFilter("nearest", "nearest") end)
    fieldNetBallImage = img
    local iw, ih = img:getDimensions()
    if iw >= 16 and ih >= 16 then
      local qok, quad = pcall(love.graphics.newQuad, 0, 0, 16, 16, iw, ih)
      if qok then fieldNetBallQuad = quad end
    end
    if data.gen2Palettes then
      fieldNetBallColors = Palettes.spritePalette(data.gen2Palettes, "DAY", def)
    end
    return fieldNetBallImage
  end

  local function drawFieldNetBall(game, x, y, scale)
    scale = scale or 0.75
    local img = resolveFieldNetBall(game)
    if img then
      local function body()
        love.graphics.setColor(1, 1, 1, 1)
        if fieldNetBallQuad then
          love.graphics.draw(img, fieldNetBallQuad, math.floor(x), math.floor(y),
            0, scale, scale, 8, 8)
        else
          local iw, ih = img:getDimensions()
          love.graphics.draw(img, math.floor(x), math.floor(y),
            0, scale, scale, iw / 2, ih / 2)
        end
      end
      if fieldNetBallColors and GbcPalette.available and GbcPalette.available() then
        GbcPalette.with(fieldNetBallColors, body)
      else
        body()
      end
      return true
    end

    -- Compact fallback that still reads as a Poké Ball at Game Boy scale.
    local r = math.max(3, math.floor(6 * scale))
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.circle("fill", x, y, r)
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.circle("line", x, y, r)
    love.graphics.line(x - r, y, x + r, y)
    love.graphics.circle("fill", x, y, math.max(1, math.floor(r / 3)))
    return true
  end

  -- Use each species' actual Crystal front battle sprite in the capture scene.
  -- DEV23 attempted to draw a party-menu icon inside this custom screen and
  -- silently swallowed the rendering failure with pcall, leaving the target
  -- invisible even though its movement/collision state still existed.
  local fieldNetSprites = {}
  local function fieldNetSprite(game, species)
    local cached = fieldNetSprites[species]
    if cached ~= nil then return cached or nil end
    local path = Sprites.path(game.data, species, "front", { kind = "battle" })
    if not path then
      fieldNetSprites[species] = false
      return nil
    end
    local ok, img = pcall(love.graphics.newImage, path)
    if ok and img then
      pcall(function() img:setFilter("nearest", "nearest") end)
      fieldNetSprites[species] = img
      return img
    end
    fieldNetSprites[species] = false
    return nil
  end

  local drawMonColored

  -- Vivarium residents use the lighter-weight overworld/icon representation
  -- rather than full battle sprites.  When Unique Menu Icons is installed, its
  -- species-specific icon sheets are used directly just like Angler's Cove.
  local function crystalDaytime(game)
    local world = game.world or game.overworld
    return (world and world.daytime) or "DAY"
  end

  local function terrariumUniqueIconForSpecies(game, species)
    if not species then return nil end
    local found = mod.find and mod.find("unique_menu_icons") or nil
    if not found then return nil end
    local icons = game and game.data and game.data.gen2Icons
    local iconId = icons and icons.species and icons.species[species]
    if not iconId then return nil end
    if not tostring(iconId):find("ICON_UNIQUE_", 1, true) then return nil end
    local entry = icons.icons and icons.icons[iconId]
    if not (entry and entry.image) then return nil end
    return iconId
  end

  local function makeTerrariumIconSprite(game, iconId, seed, species)
    local icons = game and game.data and game.data.gen2Icons
    local entry = icons and icons.icons and icons.icons[iconId]
    if not (entry and entry.image) then return nil end
    local sprites = game and game.data and game.data.gen2Sprites
    local base = sprites and (sprites.SPRITE_BUG_CATCHER or sprites.SPRITE_MAGIKARP or sprites.SPRITE_POLIWAG)

    local def = {
      id = "TERRARIUM_" .. tostring(iconId),
      image = entry.image,
      frames = entry.frames or 2,
      frameWidth = 16,
      frameHeight = 16,
      walker = false,
      palette = base and base.palette,
      paletteId = (base and base.paletteId) or 0,
    }

    -- Match Angler's Cove 1.4.0 exactly here: once Unique Menu Icons has
    -- registered ICON_UNIQUE_* for a species, its 16x32 PNG is final artwork.
    -- Do NOT route that PNG through SpriteRenderer. Doing so reconstructs the
    -- image as indexed Crystal OBJ data and is what creates the missing/
    -- transparent chunks visible against the terrarium background.
    local uniqueMenuIcon = tostring(iconId or ""):find("ICON_UNIQUE_", 1, true) ~= nil
      and (mod.find and mod.find("unique_menu_icons") ~= nil)

    local renderer
    if uniqueMenuIcon then
      local directPath = entry.image
      local okData, data = pcall(love.image.newImageData, directPath)
      local image = nil
      if okData and data then
        local iw0, ih0 = data:getDimensions()
        local grayscale = true
        for yy = 0, ih0 - 1 do
          for xx = 0, iw0 - 1 do
            local rr, gg, bb, aa = data:getPixel(xx, yy)
            if aa > 0.01 and (math.abs(rr - gg) > 0.01 or math.abs(rr - bb) > 0.01) then
              grayscale = false
              break
            end
          end
          if not grayscale then break end
        end

        -- ORIGINAL UMI mode is grayscale because the normal party menu adds
        -- its OBJ palette later. The terrarium bypasses PartyMenu, so reproduce
        -- that final coloration here. GBC RED / UNIQUE COLORS are already
        -- literal-color RGBA and pass through untouched.
        if grayscale then
          local colors = Palettes.monColors(game.data and game.data.gen2Palettes, species, false)
          if colors then
            local light = colors[2] or colors[1]
            local dark = colors[3] or colors[2] or colors[1]
            if light and dark then
              for yy = 0, ih0 - 1 do
                for xx = 0, iw0 - 1 do
                  local rr, gg, bb, aa = data:getPixel(xx, yy)
                  if aa > 0.01 then
                    local lum = (rr + gg + bb) / 3
                    if lum > 0.80 then
                      data:setPixel(xx, yy, light[1] / 255, light[2] / 255, light[3] / 255, aa)
                    elseif lum > 0.35 then
                      data:setPixel(xx, yy, dark[1] / 255, dark[2] / 255, dark[3] / 255, aa)
                    else
                      data:setPixel(xx, yy, 0, 0, 0, aa)
                    end
                  end
                end
              end
            end
          end
        end

        local okImage, img = pcall(love.graphics.newImage, data)
        if okImage then image = img end
      end

      if image then
        image:setFilter("nearest", "nearest")
        local iw, ih = image:getDimensions()
        local frames = math.max(1, tonumber(entry.frames) or 2)
        local quads = {}
        for i = 0, frames - 1 do
          quads[i] = love.graphics.newQuad(0, i * 16, 16, 16, iw, ih)
        end
        renderer = { frameCount = frames }
        function renderer:getFrameGeometry(frame)
          frame = math.max(0, math.min(frames - 1, tonumber(frame) or 0))
          return { quad = quads[frame], width = 16, height = 16 }
        end
        function renderer:resolveImage() return image end
      else
        mod.log:warn("vivarium: failed direct Unique Menu Icon load for %s", tostring(iconId))
      end
    end

    -- Normal vanilla icons (and a defensive UMI fallback) still use the
    -- Crystal renderer/palette path.
    if not renderer then
      renderer = SpriteRenderer.new(def, seed or ("terrarium:" .. tostring(iconId)))
      local colors = Palettes.monColors(game.data and game.data.gen2Palettes, species, false)
      if colors and renderer.setObjPalette then
        renderer:setObjPalette(colors,
          "terrarium:icon:" .. tostring(species or iconId) .. ":" .. crystalDaytime(game))
      end
    end
    return { id = def.id, def = def, renderer = renderer }
  end

  local terrariumResidentSprites = {}
  local function terrariumResidentSprite(game, species)
    local cached = terrariumResidentSprites[species]
    if cached ~= nil then return cached or nil end
    local icons = game and game.data and game.data.gen2Icons
    local iconId = terrariumUniqueIconForSpecies(game, species)
      or (icons and icons.species and icons.species[species])
    if iconId then
      local sprite = makeTerrariumIconSprite(game, iconId, "terrarium:" .. tostring(species), species)
      terrariumResidentSprites[species] = sprite or false
      if sprite then return sprite end
    end
    terrariumResidentSprites[species] = false
    return nil
  end

  local function drawTerrariumResident(game, species, sprite, x, y, dir, animTime, specimen)
    local renderer = sprite and sprite.renderer
    if not renderer then
      local fallback = fieldNetSprite(game, species)
      local mon = specimen and specimen.mon
      return drawMonColored(game, species, fallback, x, y, 18,
        (mon and mon.shiny) or (specimen and specimen.shiny),
        (mon and mon.vfrPrime) or (specimen and specimen.vfrPrime))
    end
    local frameCount = math.max(1, renderer.frameCount or 1)
    local frame = (frameCount > 1) and (math.floor((animTime or 0) / 0.45) % frameCount) or 0
    local geometry = renderer:getFrameGeometry(frame)
    local image = renderer:resolveImage()
    if not (geometry and geometry.quad and image) then return false end
    local px = math.floor((x or 0) - geometry.width / 2 + 0.5)
    local py = math.floor((y or 0) - geometry.height / 2 + 0.5)
    local mon = specimen and specimen.mon
    local prime = (mon and mon.vfrPrime) or (specimen and specimen.vfrPrime)
    if prime then love.graphics.setColor(1.0, 0.78, 0.24, 1)
    else love.graphics.setColor(1, 1, 1, 1) end
    if (dir or -1) > 0 then
      love.graphics.draw(image, geometry.quad, px + geometry.width, py, 0, -1, 1)
    else
      love.graphics.draw(image, geometry.quad, px, py)
    end
    return true
  end

  ---------------------------------------------------------------------------
  -- CONSERVATION SPECIES REGISTRY
  -- DEV60 centralizes every species used by the Field Net, donation logbook,
  -- and Vivarium.  A species in this registry is eligible for all three loops.
  -- Donation goals are intentionally tiered by rarity: common 30, uncommon 15,
  -- rare 10.  The first six completed COMMON goals drive the alternating
  -- JAXEN/FERN shop-unlock ladder; harder goals open after milestone six.
  ---------------------------------------------------------------------------
  local DONATION_TIER_ORDER = { "common", "uncommon", "rare" }
  local DONATION_TIERS = {
    common = {
      label = "COMMON", goal = 30,
      species = {
        "CATERPIE", "METAPOD", "WEEDLE", "KAKUNA",
        "LEDYBA", "SPINARAK", "PARAS", "VENONAT",
        "ODDISH", "BELLSPROUT", "HOPPIP", "SUNKERN",
      },
    },
    uncommon = {
      label = "UNCOMMON", goal = 15,
      species = {
        "BUTTERFREE", "BEEDRILL", "LEDIAN", "ARIADOS",
        "PARASECT", "VENOMOTH", "SKIPLOOM", "GLOOM",
        "WEEPINBELL", "EXEGGCUTE", "YANMA", "PINECO", "TANGELA",
      },
    },
    rare = {
      label = "RARE", goal = 10,
      species = { "SCYTHER", "PINSIR", "HERACROSS", "SHUCKLE" },
    },
  }

  -- Reusable movement personalities.  Species select one below and may then
  -- override individual fields. WATCH therefore teaches consistent behaviour,
  -- while uncommon/rare species can still demand extra clean net contacts.
  local FIELD_NET_BEHAVIORS = {
    calm = {
      speed = 18, turn = 1.15, watchType = "CALM", movement = "bursty",
      hopDelayMin = 0.48, hopDelayMax = 0.78,
      hopMin = 5, hopMax = 11, hopDuration = 0.13, hopArc = 3,
      evadeChance = 0.04, netHits = 1,
      rustleDuration = 16.0, rustleStyle = "calm",
      hint = "CALM.\nWaits, then hops.",
    },
    jittery = {
      speed = 25, turn = 0.70, watchType = "JITTERY", movement = "jittery",
      hopDelayMin = 0.16, hopDelayMax = 0.31,
      hopMin = 9, hopMax = 18, hopDuration = 0.085, hopArc = 4,
      evadeChance = 0.28, netHits = 2,
      rustleDuration = 10.0, rustleStyle = "jittery",
      hint = "JITTERY.\nSudden darts.",
    },
    still = {
      speed = 6, turn = 1.80, watchType = "STILL", movement = "still",
      hopDelayMin = 1.05, hopDelayMax = 1.65,
      hopMin = 2, hopMax = 5, hopDuration = 0.16, hopArc = 2,
      evadeChance = 0.02, netHits = 1,
      rustleDuration = 20.0, rustleStyle = "still",
      hint = "STILL.\nHardly moves.",
    },
    flutter = {
      speed = 28, turn = 0.62, watchType = "FLUTTER", movement = "flutter",
      hopDelayMin = 0.22, hopDelayMax = 0.46,
      hopMin = 8, hopMax = 17, hopDuration = 0.10, hopArc = 5,
      evadeChance = 0.18, netHits = 2,
      rustleDuration = 12.0, rustleStyle = "calm",
      hint = "FLUTTER.\nDrifts and darts.",
    },
    heavy = {
      speed = 12, turn = 1.25, watchType = "HEAVY", movement = "bursty",
      hopDelayMin = 0.52, hopDelayMax = 0.92,
      hopMin = 4, hopMax = 9, hopDuration = 0.16, hopArc = 2,
      evadeChance = 0.08, netHits = 2,
      rustleDuration = 17.0, rustleStyle = "calm",
      hint = "HEAVY.\nSlow, hard to net.",
    },
    darting = {
      speed = 34, turn = 0.48, watchType = "DARTING", movement = "jittery",
      hopDelayMin = 0.12, hopDelayMax = 0.26,
      hopMin = 12, hopMax = 21, hopDuration = 0.075, hopArc = 4,
      evadeChance = 0.32, netHits = 2,
      rustleDuration = 9.0, rustleStyle = "jittery",
      hint = "DARTING.\nSharp quick hops.",
    },
  }

  -- Per-species tuning. Habitat encounter weights live in a separate table
  -- below so map ecology can change without duplicating capture behaviour.
  local CONSERVATION_SPECIES = {
    CATERPIE   = { behavior = "calm",    levelMin = 3,  levelMax = 7 },
    METAPOD    = { behavior = "still",   levelMin = 5,  levelMax = 9 },
    WEEDLE     = { behavior = "jittery", levelMin = 3,  levelMax = 7 },
    KAKUNA     = { behavior = "still",   levelMin = 5,  levelMax = 9 },
    LEDYBA     = { behavior = "flutter", levelMin = 5,  levelMax = 11 },
    SPINARAK   = { behavior = "jittery", levelMin = 5,  levelMax = 11 },
    PARAS      = { behavior = "heavy",   levelMin = 6,  levelMax = 12 },
    VENONAT    = { behavior = "jittery", levelMin = 8,  levelMax = 14 },
    ODDISH     = { behavior = "calm",    levelMin = 5,  levelMax = 12 },
    BELLSPROUT = { behavior = "calm",    levelMin = 5,  levelMax = 12 },
    HOPPIP     = { behavior = "flutter", levelMin = 5,  levelMax = 12 },
    SUNKERN    = { behavior = "still",   levelMin = 5,  levelMax = 12 },

    BUTTERFREE = { behavior = "flutter", levelMin = 10, levelMax = 16 },
    BEEDRILL   = { behavior = "darting", levelMin = 10, levelMax = 16 },
    LEDIAN     = { behavior = "flutter", levelMin = 12, levelMax = 18 },
    ARIADOS    = { behavior = "darting", levelMin = 12, levelMax = 18 },
    PARASECT   = { behavior = "heavy",   levelMin = 14, levelMax = 20 },
    VENOMOTH   = { behavior = "flutter", levelMin = 14, levelMax = 20 },
    SKIPLOOM   = { behavior = "flutter", levelMin = 12, levelMax = 18 },
    GLOOM      = { behavior = "heavy",   levelMin = 14, levelMax = 20 },
    WEEPINBELL = { behavior = "heavy",   levelMin = 14, levelMax = 20 },
    EXEGGCUTE  = { behavior = "still",   levelMin = 12, levelMax = 20 },
    YANMA      = { behavior = "darting", levelMin = 12, levelMax = 20 },
    PINECO     = { behavior = "still",   levelMin = 10, levelMax = 18 },
    TANGELA    = { behavior = "jittery", levelMin = 16, levelMax = 24 },

    SCYTHER    = { behavior = "darting", levelMin = 18, levelMax = 26,
                   netHits = 3, evadeChance = 0.38 },
    PINSIR     = { behavior = "heavy",   levelMin = 18, levelMax = 26,
                   netHits = 3, evadeChance = 0.24 },
    HERACROSS  = { behavior = "darting", levelMin = 18, levelMax = 26,
                   netHits = 3, evadeChance = 0.34 },
    SHUCKLE    = { behavior = "still",   levelMin = 16, levelMax = 24,
                   netHits = 3, evadeChance = 0.05 },
  }

  -- Attach tier/goal data and build the capture config consumed by the existing
  -- Field Net scene. This keeps one authoritative roster for every subsystem.
  local FIELD_NET_SPECIES = {}
  local DONATION_GOALS = {}
  for _, tierName in ipairs(DONATION_TIER_ORDER) do
    local tier = DONATION_TIERS[tierName]
    for _, species in ipairs(tier.species) do
      local spec = CONSERVATION_SPECIES[species]
      if spec then
        spec.tier = tierName
        spec.goal = tier.goal
        local behavior = FIELD_NET_BEHAVIORS[spec.behavior] or FIELD_NET_BEHAVIORS.calm
        local cfg = copy(behavior)
        for k, v in pairs(spec) do
          if k ~= "tier" and k ~= "goal" and k ~= "behavior" then cfg[k] = v end
        end
        FIELD_NET_SPECIES[species] = cfg
        DONATION_GOALS[#DONATION_GOALS + 1] = {
          species = species, goal = tier.goal, tier = tierName,
        }
      end
    end
  end

  local SHOP_MILESTONES = {
    [1] = { owner = "JAXEN", item = "SCENT SPRAY", key = "scentSpray" },
    [2] = { owner = "FERN",  item = "FUNGI SPORES", key = "fungiSpores" },
    [3] = { owner = "JAXEN", item = "SPARKLE BITS", key = "sparkleBits" },
    [4] = { owner = "FERN",  item = "BERRY SEED", key = "berrySeed" },
    [5] = { owner = "JAXEN", item = "SHINY NET", key = "shinyNet" },
    [6] = { owner = "FERN",  item = "FERTILIZER", key = "fertilizer" },
  }

  ---------------------------------------------------------------------------
  -- ADVANCED CONSERVATION REWARDS
  -- Once the six shop unlocks are available, 30/30 UNCOMMON and 15/15 RARE
  -- goals award species-flavoured vanilla items through JAXEN. Rewards are
  -- queued when a quota is completed and claimed the next time JAXEN is spoken
  -- to, so the Logbook stays the donation hub while JAXEN remains involved.
  ---------------------------------------------------------------------------
  local DONATION_REWARDS = {
    BUTTERFREE = { { "SILVERPOWDER", 1 } },
    BEEDRILL   = { { "POISON_BARB", 1 } },
    LEDIAN     = { { "BRIGHTPOWDER", 1 } },
    ARIADOS    = { { "POISON_BARB", 1 }, { "FULL_HEAL", 2 } },
    PARASECT   = { { "BIG_MUSHROOM", 2 } },
    VENOMOTH   = { { "SILVERPOWDER", 1 }, { "ANTIDOTE", 2 } },
    SKIPLOOM   = { { "MIRACLE_SEED", 1 } },
    GLOOM      = { { "LEAF_STONE", 1 } },
    WEEPINBELL = { { "LEAF_STONE", 1 } },
    EXEGGCUTE  = { { "RARE_CANDY", 3 } },
    YANMA      = { { "QUICK_CLAW", 1 } },
    PINECO     = { { "IRON", 3 } },
    TANGELA    = { { "MIRACLE_SEED", 1 }, { "PP_UP", 2 } },

    SCYTHER    = { { "METAL_COAT", 1 }, { "PROTEIN", 3 } },
    PINSIR     = { { "PROTEIN", 3 }, { "IRON", 3 } },
    HERACROSS  = { { "RARE_CANDY", 3 }, { "PP_UP", 2 } },
    SHUCKLE    = { { "IRON", 3 }, { "CALCIUM", 3 }, { "BERRY", 5 } },
  }

  local RARE_CAPSTONE_KEY = "__RARE_MASTER__"
  local RARE_CAPSTONE_REWARD = {
    { "RARE_CANDY", 5 },
    { "PP_UP", 3 },
    { "NUGGET", 1 },
    { "RED_APRICORN", 1 },
    { "BLU_APRICORN", 1 },
    { "YLW_APRICORN", 1 },
    { "GRN_APRICORN", 1 },
    { "WHT_APRICORN", 1 },
    { "BLK_APRICORN", 1 },
    { "PNK_APRICORN", 1 },
  }

  local function rewardIsPending(dp, key)
    for _, pending in ipairs(dp.rewardPending or {}) do
      if pending == key then return true end
    end
    return false
  end

  local function completedCommonGoals(root)
    local count = 0
    local tier = DONATION_TIERS.common
    for _, species in ipairs(tier.species) do
      if (tonumber((root.donations or {})[species]) or 0) >= tier.goal then
        count = count + 1
      end
    end
    return count
  end

  local function syncDonationProgress(root)
    root.donationProgress = root.donationProgress or {}
    local dp = root.donationProgress
    dp.completed = dp.completed or {}
    dp.shopUnlocks = dp.shopUnlocks or {}
    dp.devTierUnlocks = dp.devTierUnlocks or {}
    dp.rewardClaimed = dp.rewardClaimed or {}
    dp.rewardPending = dp.rewardPending or {}

    local commonCompleted = completedCommonGoals(root)
    dp.commonCompleted = commonCompleted
    dp.advancedUnlocked = commonCompleted >= 6

    -- Shop flags are derived from completed common quotas, so existing saves
    -- remain retroactive even if a future build changes how JAXEN/FERN menus
    -- are presented.
    for i = 1, math.min(6, commonCompleted) do
      local milestone = SHOP_MILESTONES[i]
      if milestone then dp.shopUnlocks[milestone.key] = true end
    end

    for _, tierName in ipairs(DONATION_TIER_ORDER) do
      local tier = DONATION_TIERS[tierName]
      local unlocked = tierName == "common" or dp.advancedUnlocked
      for _, species in ipairs(tier.species) do
        local count = tonumber((root.donations or {})[species]) or 0
        if unlocked and count >= tier.goal then
          dp.completed[species] = true

          -- Advanced goals prepare a one-time JAXEN reward. This detection is
          -- intentionally derived from the saved quota totals so DEV tools and
          -- saves from an earlier build receive their rewards retroactively.
          if tierName ~= "common" and DONATION_REWARDS[species]
              and not dp.rewardClaimed[species]
              and not rewardIsPending(dp, species) then
            dp.rewardPending[#dp.rewardPending + 1] = species
          end
        end
      end
    end

    -- Completing every RARE quota has one additional 1.0 conservation
    -- capstone bundle. It is queued after the individual species reward.
    local allRare = true
    for _, species in ipairs(DONATION_TIERS.rare.species) do
      if (tonumber((root.donations or {})[species]) or 0) < DONATION_TIERS.rare.goal then
        allRare = false
        break
      end
    end
    if allRare and not dp.rewardClaimed[RARE_CAPSTONE_KEY]
        and not rewardIsPending(dp, RARE_CAPSTONE_KEY) then
      dp.rewardPending[#dp.rewardPending + 1] = RARE_CAPSTONE_KEY
    end

    return dp
  end

  local function donationTierUnlocked(root, tierName)
    if tierName == "common" then return true end
    local dp = syncDonationProgress(root)
    -- DEV61: testing overrides let UNCOMMON and RARE be opened independently
    -- without completing six COMMON quotas or disturbing normal progression.
    if dp.devTierUnlocks and dp.devTierUnlocks[tierName] then return true end
    return dp.advancedUnlocked == true
  end

  local function shopUnlocked(root, key)
    local dp = syncDonationProgress(root)
    return (dp.devShopUnlockAll == true)
      or (dp.shopUnlocks and dp.shopUnlocks[key] == true)
  end

  local function donationGoal(species)
    return CONSERVATION_SPECIES[species]
  end

  local function vivariumRoot(game)
    game.save.modData = game.save.modData or {}
    game.save.modData.viridian_vivarium = game.save.modData.viridian_vivarium or {}
    local root = game.save.modData.viridian_vivarium
    root.donations = root.donations or {}
    root.donationProgress = root.donationProgress or {}
    root.fieldNet = root.fieldNet or { caught = {}, total = 0, specimens = {} }
    root.fieldNet.caught = root.fieldNet.caught or {}
    root.fieldNet.specimens = root.fieldNet.specimens or {}
    root.fieldNet.nextSpecimenId = tonumber(root.fieldNet.nextSpecimenId) or 1
    -- DEV44 is the first build with individual specimen records. Preserve
    -- catches made in older dev builds by turning their aggregate counts into
    -- legacy Lv.1 specimen records once.
    if not root.fieldNet.specimenMigrationDone then
      for species, count in pairs(root.fieldNet.caught) do
        for _ = 1, math.max(0, tonumber(count) or 0) do
          root.fieldNet.specimens[#root.fieldNet.specimens + 1] = {
            id = root.fieldNet.nextSpecimenId, species = species, level = 1,
            legacy = true,
          }
          root.fieldNet.nextSpecimenId = root.fieldNet.nextSpecimenId + 1
        end
      end
      root.fieldNet.specimenMigrationDone = true
    end
    root.vivarium = root.vivarium or { capacity = 5, residents = {}, lightsOn = true }
    root.vivarium.capacity = tonumber(root.vivarium.capacity) or 5
    root.vivarium.residents = root.vivarium.residents or {}
    if root.vivarium.lightsOn == nil then root.vivarium.lightsOn = true end
    root.vivarium.nextResidentId = tonumber(root.vivarium.nextResidentId) or 1
    root.vivarium.plots = root.vivarium.plots or {}
    for i = 1, 3 do
      root.vivarium.plots[i] = root.vivarium.plots[i] or {
        cropType = nil, item = nil, harvestItem = nil, fertilized = false,
        progress = 0, waterMinutes = 0, lastStamp = nil,
      }
      if root.vivarium.plots[i].fertilized == nil then root.vivarium.plots[i].fertilized = false end
    end
    syncDonationProgress(root)
    return root
  end

  local function donationRewardBundle(key)
    if key == RARE_CAPSTONE_KEY then return RARE_CAPSTONE_REWARD end
    return DONATION_REWARDS[key]
  end

  local function donationRewardTitle(key)
    if key == RARE_CAPSTONE_KEY then return "RARE PROJECT" end
    return tostring(key or "PROJECT")
  end

  local function itemRewardLabel(game, itemId)
    local def = game and game.data and game.data.items and game.data.items[itemId]
    return tostring((def and def.name) or itemId or "ITEM"):gsub("_", " ")
  end

  local function grantDonationReward(game, key)
    local bundle = donationRewardBundle(key)
    if not (game and game.save and bundle) then
      return false, { "No reward is\nready." }
    end

    -- Rewards can contain several different items. Snapshot both inventory and
    -- bag ordering, then roll everything back if even one item will not fit.
    local inventoryBefore = copy(game.save.inventory or {})
    local orderBefore = copy(game.save.bagOrder or {})
    for _, row in ipairs(bundle) do
      if not Bag.add(game.save, row[1], row[2] or 1, game.data) then
        game.save.inventory = inventoryBefore
        game.save.bagOrder = orderBefore
        return false, {
          "Your PACK needs\nmore room.",
          "Come back after\nyou make space.",
        }
      end
    end

    local root = vivariumRoot(game)
    local dp = root.donationProgress
    dp.rewardClaimed[key] = true
    for i, pending in ipairs(dp.rewardPending or {}) do
      if pending == key then
        table.remove(dp.rewardPending, i)
        break
      end
    end

    local pages = {}
    if key == RARE_CAPSTONE_KEY then
      pages[#pages + 1] = "All RARE goals\nare complete!"
      pages[#pages + 1] = "JAXEN: That's a\nhuge achievement."
    else
      pages[#pages + 1] = donationRewardTitle(key) .. " reward\nreceived!"
    end
    for _, row in ipairs(bundle) do
      pages[#pages + 1] = ("Received %d\n%s!"):format(
        tonumber(row[2]) or 1, itemRewardLabel(game, row[1]))
    end
    pcall(function() Sound.playStereo(game.data, "Sfx_Item") end)
    return true, pages
  end

  local function nextDonationReward(root)
    local dp = syncDonationProgress(root)
    return dp.rewardPending and dp.rewardPending[1] or nil
  end

  local function vfrDevData(save)
    save.modData = save.modData or {}
    save.modData.viridian_vivarium_dev =
      save.modData.viridian_vivarium_dev or { marks = {} }
    local state = save.modData.viridian_vivarium_dev
    state.marks = state.marks or {}
    return state
  end

  -- JAXEN / FERN shops use Crystal's native Mart flow. Stock expands from the
  -- six COMMON-quota milestones; VIV DEV can temporarily expose all stock.
  local function makeVfrMart(game, shelf, owner)
    if #shelf == 0 then
      return mod.ui.ListMenu.new(game, owner, {
        { label = "NO STOCK YET", value = "none" },
      }, {
        footer = "Complete project quotas.",
        onChoose = function(_item, menu) menu:close() end,
      })
    end
    local mart = MartMenu.new(game, {
      save = game.save, items = game.data and game.data.items,
      marts = { lists = { shelf } }, martType = "STANDARD", martId = 0,
      text = game.world and game.world.text,
      onClose = function() game.stack:pop() end,
    })
    mart:enterBuy()
    mart.leaveBuy = function(self)
      self.isOpaque = nil
      if self.onClose then self.onClose() end
    end
    -- SHINY NET is a one-time purchasable upgraded net. Standard marts normally let
    -- every item select a quantity, so pin this key item to one and refuse a
    -- second purchase even before the shop is reopened.
    local function ownsShinyNet(self)
      local inv = self.save and self.save.inventory or {}
      local root = self.game and vivariumRoot(self.game)
      return (tonumber(inv[SHINY_NET]) or 0) > 0
          or (root and root.upgrades and root.upgrades.shinyNet == true)
    end

    local vanillaOffer = mart.offerToBuy
    function mart:offerToBuy()
      local entry = self:selected()
      if entry and entry.id == SHINY_NET then
        if ownsShinyNet(self) then
          self:say({ { "The SHINY NET", "is already yours." } })
          return
        end
        self.qtyItem, self.qty, self.qtyMax = entry, 1, 1
        self.phase = "buyQuantity"
        return
      end
      return vanillaOffer(self)
    end

    local vanillaCompletePurchase = mart.completePurchase
    function mart:completePurchase(total)
      local entry = self.qtyItem
      local wasShinyNet = entry and entry.id == SHINY_NET
      vanillaCompletePurchase(self, total)
      if wasShinyNet and ((self.save.inventory or {})[SHINY_NET] or 0) > 0 then
        local root = vivariumRoot(self.game)
        root.upgrades = root.upgrades or {}
        root.upgrades.shinyNet = true
      end
    end

    -- Keep the one-time upgrade visible after purchase, but replace its price
    -- with SOLD. This makes the completed milestone obvious without inviting
    -- the player to buy a second copy.
    local vanillaDrawBuyList = mart.drawBuyList
    function mart:drawBuyList()
      vanillaDrawBuyList(self)
      if not ownsShinyNet(self) then return end
      for row = 1, 4 do
        local i = row + (self.scroll or 0)
        local entry = self.entries and self.entries[i]
        if entry and entry.id == SHINY_NET then
          local ty = 4 + (row - 1) * 2 + 1
          love.graphics.setColor(1, 1, 1, 1)
          love.graphics.rectangle("fill", 10 * 8, ty * 8, 7 * 8, 8)
          love.graphics.setColor(0, 0, 0, 1)
          Chrome.print("SOLD", 12, ty)
        end
      end
    end

    return mart
  end

  mod.content.screens:register(JAXEN_SHOP_SCREEN, {
    new = function(game)
      local root = vivariumRoot(game)
      local shelf = {}
      if shopUnlocked(root, "scentSpray") then shelf[#shelf + 1] = SCENT_SPRAY end
      if shopUnlocked(root, "sparkleBits") then shelf[#shelf + 1] = SPARKLE_BITS end
      if shopUnlocked(root, "shinyNet") then
        shelf[#shelf + 1] = SHINY_NET
      end
      return makeVfrMart(game, shelf, "JAXEN")
    end,
  })

  mod.content.screens:register(FERN_SHOP_SCREEN, {
    new = function(game)
      local root = vivariumRoot(game)
      local shelf = {}
      if shopUnlocked(root, "fungiSpores") then shelf[#shelf + 1] = FUNGI_SPORES end
      if shopUnlocked(root, "berrySeed") then shelf[#shelf + 1] = BERRY_SEED end
      if shopUnlocked(root, "fertilizer") then shelf[#shelf + 1] = FERTILIZER end
      return makeVfrMart(game, shelf, "FERN")
    end,
  })

  local function donateOwnedMon(game, row)
    local save = game and game.save
    if not (save and row) then return false, "Donation failed." end

    local mon
    if row.source == "box" then
      local box = (save.boxes and save.boxes[row.boxIndex]) or {}
      mon = box[row.slot]
    else
      mon = save.party and save.party[row.partyIndex]
    end
    if not mon or mon.isEgg then return false, "Can't donate\nthat POKEMON." end

    local spec = donationGoal(mon.species)
    if not spec then return false, "Not a project\nspecies." end

    local root = vivariumRoot(game)
    if not donationTierUnlocked(root, spec.tier) then
      return false, "Harder goals are\nnot open yet."
    end

    local current = tonumber(root.donations[mon.species]) or 0
    if current >= spec.goal then
      return false, "That quota is\ncomplete."
    end

    if row.source ~= "box" then
      local party = save.party or {}
      if Mail.monHoldsMail(mon) then return false, "Remove MAIL first." end
      if (mon.hp or 0) > 0 and Boxes.healthyCount(party) <= 1 then
        return false, "Keep one healthy\nPKMN with you."
      end
    end

    local beforeCommon = completedCommonGoals(root)
    if row.source == "box" then
      local ok = Boxes.release(save, row.boxIndex, row.slot)
      if not ok then return false, "That POKEMON is\nno longer there." end
    else
      table.remove(save.party, row.partyIndex)
      Mail.removeSlot(save, row.partyIndex)
    end

    root.donations[mon.species] = math.min(spec.goal, current + 1)
    local completedNow = current < spec.goal and root.donations[mon.species] >= spec.goal
    local dp = syncDonationProgress(root)

    local milestone
    if completedNow and spec.tier == "common" and dp.commonCompleted > beforeCommon
        and dp.commonCompleted <= 6 then
      milestone = SHOP_MILESTONES[dp.commonCompleted]
    end

    return true, {
      species = mon.species, count = root.donations[mon.species], goal = spec.goal,
      tier = spec.tier, completed = completedNow, milestone = milestone,
      advancedUnlocked = dp.advancedUnlocked,
    }
  end

  local VIV_WEEK_MINUTES = 7 * 24 * 60
  local VIV_PLANT_MATURE = 24 * 60
  local VIV_WATER_DURATION = 8 * 60

  local function vivariumClockStamp(save)
    return ((Clock.weekday(save) or 0) * 1440 + (Clock.minutes(save) or 0)) % VIV_WEEK_MINUTES
  end

  local function vivariumElapsedMinutes(nowStamp, oldStamp)
    if oldStamp == nil then return 0 end
    local delta = (tonumber(nowStamp) or 0) - (tonumber(oldStamp) or 0)
    if delta < 0 then delta = delta + VIV_WEEK_MINUTES end
    return math.max(0, delta)
  end

  local function syncVivariumPlots(game, habitat)
    local now = vivariumClockStamp(game.save)
    for _, plot in ipairs(habitat.plots or {}) do
      if plot and plot.item then
        local last = plot.lastStamp
        if last == nil then
          plot.lastStamp = now
        else
          local delta = vivariumElapsedMinutes(now, last)
          if delta > 0 then
            local lightFactor = 1.0
            if plot.cropType == "plant" and habitat.lightsOn then lightFactor = 2.0 end
            if plot.cropType == "fungus" and not habitat.lightsOn then lightFactor = 2.0 end
            local waterLeft = math.max(0, tonumber(plot.waterMinutes) or 0)
            local wet = math.min(delta, waterLeft)
            local dry = math.max(0, delta - wet)
            -- Watering is a modest +25% additive boost instead of multiplying
            -- the light bonus. With plant lights ON, 8 watered hours count as
            -- 18 effective hours (75% of a 24h crop), not a full maturation.
            local effective = (dry * lightFactor) + (wet * (lightFactor + 0.25))
            plot.progress = math.min(VIV_PLANT_MATURE, (tonumber(plot.progress) or 0) + effective)
            plot.waterMinutes = math.max(0, waterLeft - delta)
            plot.lastStamp = now
          end
        end
      else
        plot.lastStamp = now
      end
    end
    return now
  end

  local function fastForwardVivariumTime(game, hours)
    local save = game and game.save
    if not save then return false end
    local minutes = Clock.minutes(save) or 0
    local day = Clock.weekday(save) or 0
    local total = minutes + math.floor((tonumber(hours) or 0) * 60)
    local dayAdvance = math.floor(total / 1440)
    local target = total % 1440
    Clock.setTime(save, math.floor(target / 60), target % 60)
    Clock.setWeekday(save, (day + dayAdvance) % 7)
    return true
  end

  local function fieldNetSave(game)
    return vivariumRoot(game).fieldNet
  end

  local function recordFieldNetCatch(game, species)
    local root = vivariumRoot(game)
    local s = root.fieldNet
    s.total = (s.total or 0) + 1
    s.caught[species] = (s.caught[species] or 0) + 1
    s.lastCatch = species
  end

  local function placeOwnedMon(game, mon, emitCatch)
    local save = game and game.save
    if not (save and mon) then return false, "NO SAVE DATA" end
    save.party = save.party or {}
    save.pokedex = save.pokedex or { seen = {}, caught = {} }
    save.pokedex.seen = save.pokedex.seen or {}
    save.pokedex.caught = save.pokedex.caught or {}
    save.pokedex.owned = save.pokedex.owned or {}

    Mon.stampOT(save, mon)
    local destination, boxIndex = "party", nil
    if #save.party < Boxes.PARTY_SIZE then
      save.party[#save.party + 1] = mon
    else
      local startBox = tonumber(save.currentBox) or 1
      for step = 0, Boxes.NUM_BOXES - 1 do
        local idx = ((startBox - 1 + step) % Boxes.NUM_BOXES) + 1
        if not Boxes.isFull(save, idx) then boxIndex = idx break end
      end
      if not boxIndex then return false, "PC BOXES FULL" end
      local box = Boxes.box(save, boxIndex)
      table.insert(box, 1, mon)
      Boxes.enterBox(mon)
      destination = "box"
    end

    local wasNew = not (save.pokedex.caught[mon.species] or save.pokedex.owned[mon.species])
    save.pokedex.seen[mon.species] = true
    save.pokedex.caught[mon.species] = true
    save.pokedex.owned[mon.species] = true
    if emitCatch then
      Runtime.emit("pokemon.caught", {
        mon = mon, species = mon.species, isNew = wasNew,
        ball = "FIELD_NET", destination = destination, game = game,
      })
    end
    return true, destination, boxIndex
  end

  local function makeFieldNetMon(game, species, level, sourceMap, world, forcedShiny)
    local opts = forcedShiny and { shiny = true } or nil
    local mon = Mon.new(game.data, species, tonumber(level) or 1, opts)
    if not mon then return nil end
    mon.vfrFieldNetCaught = true
    local save = game.save
    Mon.stampOT(save, mon)
    pcall(function()
      Catching.stampCaughtData(mon, {
        save = save, version = save and save.version,
        level = mon.level,
        map = (world and world.map and (world.map.def or world.map)) or nil,
        timeOfDay = world and world.daytime,
        playerGender = save and save.player and save.player.gender,
      })
    end)
    mon.vfrSourceMap = sourceMap
    return mon
  end

  local function storeFieldNetCatch(game, species, level, sourceMap, world, forcedShiny)
    local mon = makeFieldNetMon(game, species, level, sourceMap, world, forcedShiny)
    if not mon then return false, "COULDN'T CREATE POKEMON" end
    local ok, destination, boxIndex = placeOwnedMon(game, mon, true)
    if ok then recordFieldNetCatch(game, species) end
    return ok, destination, boxIndex, mon
  end

  local function pokemonHasType(game, species, wanted)
    local def = game and game.data and game.data.pokemon and game.data.pokemon[species]
    for _, t in ipairs((def and def.types) or {}) do
      if t == wanted then return true end
    end
    return false
  end

  local function vivariumRole(game, species)
    if pokemonHasType(game, species, "BUG") then return "bug" end
    if pokemonHasType(game, species, "GRASS") then return "plant" end
    return "other"
  end

  local function isVivariumSpecies(_game, species)
    -- One authoritative rule: every conservation/donation species is also a
    -- valid Vivarium resident. Species outside the Field Net roster stay out.
    return CONSERVATION_SPECIES[species] ~= nil
  end

  -- Battle/front/back/menu Pokémon art uses shade 0 as its white/background
  -- color. Keep that entry pure white just like vanilla mon palettes; tinting
  -- it gold creates the ugly rectangular yellow box around opaque battle pics.
  -- Only the actual ink shades are converted to the Prime gold ramp.
  local PRIME_GOLD_COLORS = {
    { 255, 255, 255 }, { 248, 208, 72 }, { 184, 120, 24 }, { 72, 48, 16 },
  }

  ---------------------------------------------------------------------------
  -- PRIME GLOBAL PALETTE BRIDGE
  -- Prime already persists as a mon flag and keeps its shiny behavior. DEV77
  -- makes the gold Prime palette follow that record through the normal Gen 2
  -- rendering paths instead of limiting gold coloration to the Vivarium.
  --
  -- We use a very small render context around the engine's existing draw
  -- methods rather than replacing those screens. While a Prime mon is being
  -- drawn, Palettes.monColors returns PRIME_GOLD_COLORS. Outside that call,
  -- vanilla/shiny palette resolution is untouched.
  ---------------------------------------------------------------------------
  local primePaletteDepth = 0
  local vanillaMonColors = Palettes.monColors
  if not Palettes.__vfrPrimePalette then
    Palettes.__vfrPrimePalette = true
    Palettes.__vfrVanillaMonColors = vanillaMonColors
    function Palettes.monColors(data, speciesId, shiny)
      if primePaletteDepth > 0 then return PRIME_GOLD_COLORS end
      return Palettes.__vfrVanillaMonColors(data, speciesId, shiny)
    end
  else
    vanillaMonColors = Palettes.__vfrVanillaMonColors or vanillaMonColors
  end

  local function withPrimePalette(mon, fn, ...)
    if not (mon and mon.vfrPrime) then return fn(...) end
    primePaletteDepth = primePaletteDepth + 1
    local result = fn(...)
    primePaletteDepth = math.max(0, primePaletteDepth - 1)
    return result
  end

  local function patchPrimeRenderers()
    if not Gen2BattleState.__vfrPrimePalette then
      Gen2BattleState.__vfrPrimePalette = true
      local vanilla = Gen2BattleState.drawPic
      function Gen2BattleState:drawPic(mon, back)
        return withPrimePalette(mon, vanilla, self, mon, back)
      end
    end

    if not BattleAnimView.__vfrPrimePalette then
      BattleAnimView.__vfrPrimePalette = true
      local vanilla = BattleAnimView.objPalette
      function BattleAnimView:objPalette(name, battle)
        local mon
        if name == "PAL_BATTLE_OB_ENEMY" then mon = battle and battle.enemy end
        if name == "PAL_BATTLE_OB_PLAYER" then mon = battle and battle.player end
        return withPrimePalette(mon, vanilla, self, name, battle)
      end
    end

    if not SummaryMenu.__vfrPrimePalette then
      SummaryMenu.__vfrPrimePalette = true
      local vanilla = SummaryMenu.drawPic
      function SummaryMenu:drawPic(...)
        return withPrimePalette(self.mon, vanilla, self, ...)
      end
    end

    if not Gen2BoxMenu.__vfrPrimePalette then
      Gen2BoxMenu.__vfrPrimePalette = true
      local vanilla = Gen2BoxMenu.drawPic
      function Gen2BoxMenu:drawPic(mon)
        return withPrimePalette(mon, vanilla, self, mon)
      end
    end

    if not PhotoStudio.__vfrPrimePalette then
      PhotoStudio.__vfrPrimePalette = true
      local vanilla = PhotoStudio.drawPic
      function PhotoStudio:drawPic(...)
        return withPrimePalette(self.mon, vanilla, self, ...)
      end
    end

    if not EvolutionAnim.__vfrPrimePalette then
      EvolutionAnim.__vfrPrimePalette = true
      local vanillaPic = EvolutionAnim.drawPic
      function EvolutionAnim:drawPic(...)
        local mon = (self.showNew and self.evolved) or self.mon
        return withPrimePalette(mon, vanillaPic, self, ...)
      end
      local vanillaBalls = EvolutionAnim.drawBalls
      function EvolutionAnim:drawBalls(...)
        local mon = self.evolved or self.mon
        return withPrimePalette(mon, vanillaBalls, self, ...)
      end
    end

    if not TradeAnimView.__vfrPrimePalette then
      TradeAnimView.__vfrPrimePalette = true
      local vanillaPic = TradeAnimView.drawPic
      function TradeAnimView:drawPic(record, offset)
        return withPrimePalette(record, vanillaPic, self, record, offset)
      end
      local vanillaIcon = TradeAnimView.drawIcon
      function TradeAnimView:drawIcon(record, x, y)
        return withPrimePalette(record, vanillaIcon, self, record, x, y)
      end
    end

    if not HallOfFameView.__vfrPrimePalette then
      HallOfFameView.__vfrPrimePalette = true
      local vanilla = HallOfFameView.monColors
      function HallOfFameView:monColors(mon)
        return withPrimePalette(mon, vanilla, self, mon)
      end
    end

    -- The vanilla HOF record stores shininess but not arbitrary custom fields.
    -- Preserve the Prime flag when a team is inducted so later PC viewing can
    -- still render that historical Pokémon gold.
    if not HallOfFameCore.__vfrPrimePalette then
      HallOfFameCore.__vfrPrimePalette = true
      local vanillaBuildParty = HallOfFameCore.buildParty
      function HallOfFameCore.buildParty(save, party)
        local entry = vanillaBuildParty(save, party)
        if not (entry and entry.mons) then return entry end
        local outIndex = 1
        for _, mon in ipairs(party or {}) do
          if outIndex > #entry.mons then break end
          if mon and mon.species ~= "EGG" and not mon.isEgg and not mon.egg then
            if mon.vfrPrime then entry.mons[outIndex].vfrPrime = true end
            outIndex = outIndex + 1
          end
        end
        return entry
      end
    end
  end

  patchPrimeRenderers()

  local function primeBaseStats(base)
    local keys = { "hp", "attack", "defense", "speed", "specialAttack", "specialDefense" }
    local total = 0
    for _, key in ipairs(keys) do total = total + math.max(1, tonumber(base and base[key]) or 1) end
    local out, used, fractions = copy(base or {}), 0, {}
    for _, key in ipairs(keys) do
      local value = math.max(1, tonumber(base and base[key]) or 1)
      local raw = PRIME_BST_BONUS * value / math.max(1, total)
      local add = math.floor(raw)
      out[key] = value + add
      used = used + add
      fractions[#fractions + 1] = { key = key, frac = raw - add, base = value }
    end
    table.sort(fractions, function(a, b)
      if a.frac ~= b.frac then return a.frac > b.frac end
      return a.base > b.base
    end)
    local left = PRIME_BST_BONUS - used
    for i = 1, left do
      local row = fractions[((i - 1) % #fractions) + 1]
      out[row.key] = (out[row.key] or 1) + 1
    end
    return out
  end

  local function refreshPrimeStats(mon, data)
    if not (mon and mon.vfrPrime) then return mon end
    local def = data and data.pokemon and data.pokemon[mon.species]
    if not (def and def.baseStats) then return mon end
    Mon.syncIdentity(mon, data)
    local fainted = (tonumber(mon.hp) or 0) <= 0
    local oldMax = tonumber(mon.maxHp) or tonumber(mon.stats and mon.stats.hp) or 1
    local missing = math.max(0, oldMax - (tonumber(mon.hp) or oldMax))
    local stats = Mon.stats(primeBaseStats(def.baseStats), mon.dvs, mon.level or 1, mon.statExp)
    mon.stats, mon.maxHp = stats, stats.hp
    if fainted then mon.hp = 0 else mon.hp = math.max(1, math.min(stats.hp, stats.hp - missing)) end
    return mon
  end

  if not Mon.__vfrPrimeStats then
    Mon.__vfrPrimeStats = true
    local vanillaRefreshStats = Mon.refreshStats
    local vanillaGainExperience = Mon.gainExperience
    function Mon.refreshStats(mon, data)
      if mon and mon.vfrPrime then return refreshPrimeStats(mon, data) end
      return vanillaRefreshStats(mon, data)
    end
    function Mon.gainExperience(mon, amount, data)
      if not (mon and mon.vfrPrime) then return vanillaGainExperience(mon, amount, data) end
      local def = data and data.pokemon and data.pokemon[mon.species]
      local fainted = (tonumber(mon.hp) or 0) <= 0
      local missing = math.max(0, (tonumber(mon.maxHp) or 1) - (tonumber(mon.hp) or 0))
      if def and def.baseStats then
        local vanillaStats = Mon.stats(def.baseStats, mon.dvs, mon.level or 1, mon.statExp)
        mon.stats, mon.maxHp = vanillaStats, vanillaStats.hp
        if fainted then mon.hp = 0 else mon.hp = math.max(1, vanillaStats.hp - missing) end
      end
      local result = vanillaGainExperience(mon, amount, data)
      refreshPrimeStats(mon, data)
      return result
    end
  end

  ---------------------------------------------------------------------------
  -- SHINY / PRIME EVOLUTION INHERITANCE
  -- Gen 2's Evolution.apply rebuilds the evolved Pokémon through Mon.new.
  -- Natural shinies survive because their DVs re-roll as shiny, but forced
  -- shinies (SHINY NET / SPARKLE BITS) can otherwise lose mon.shiny.
  --
  -- Preserve the explicit shiny bit for every evolution candidate, preserve
  -- vfrPrime, and immediately recalc Prime stats against the NEW species.
  -- This works across full chains such as Caterpie -> Metapod -> Butterfree.
  ---------------------------------------------------------------------------
  if CoreEvolution and CoreEvolution.MON_FIELDS then
    -- Let Evolution.apply's generic carry-forward pass copy the explicit
    -- shiny flag before it emits pokemon.evolved.
    CoreEvolution.MON_FIELDS.shiny = nil
  end

  if CoreEvolution and not CoreEvolution.__vfrEvolutionInheritance then
    CoreEvolution.__vfrEvolutionInheritance = true
    local vanillaEvolutionApply = CoreEvolution.apply
    function CoreEvolution.apply(data, mon, entry)
      local keepShiny = mon and mon.shiny == true
      local keepPrime = mon and mon.vfrPrime == true
      local evolved = vanillaEvolutionApply(data, mon, entry)
      if not evolved then return evolved end

      if keepShiny or keepPrime then
        evolved.shiny = true
      end
      if keepPrime then
        evolved.vfrPrime = true
        refreshPrimeStats(evolved, data)
      end
      return evolved
    end
  end

  drawMonColored = function(game, species, image, x, y, maxSize, shiny, prime)
    if not image then return false end
    local pw, ph = image:getDimensions()
    local scale = math.min(1, (maxSize or 26) / math.max(1, pw),
                              (maxSize or 26) / math.max(1, ph))
    local dw, dh = pw * scale, ph * scale
    local function body()
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(image,
        math.floor(x - dw / 2), math.floor(y - dh / 2),
        0, scale, scale)
    end
    local palData = game and game.data and game.data.gen2Palettes
    local colors = prime and PRIME_GOLD_COLORS or Palettes.monColors(palData, species, shiny and true or false)
    if colors and GbcPalette.available and GbcPalette.available() then
      GbcPalette.with(colors, body)
    else
      body()
    end
    return true
  end

  local function wrapMenuText(textValue, maxChars, maxLines)
    local words = {}
    for w in tostring(textValue or ""):gmatch("%S+") do words[#words + 1] = w end
    local lines, line = {}, ""
    maxChars = maxChars or 16
    maxLines = maxLines or 2
    for i, word in ipairs(words) do
      local candidate = (line == "") and word or (line .. " " .. word)
      if #candidate <= maxChars then
        line = candidate
      else
        if line ~= "" then lines[#lines + 1] = line end
        line = word
        if #lines >= maxLines - 1 then break end
      end
    end
    if #lines < maxLines and line ~= "" then lines[#lines + 1] = line end
    return lines
  end

  local function drawWrappedTwoLines(textValue, x, y, maxChars)
    local lines = wrapMenuText(textValue, maxChars or 16, 2)
    if lines[1] then Font.draw(lines[1], x, y) end
    if lines[2] then Font.draw(lines[2], x, y + 10) end
  end


  -- Draw only the vanilla textbox border tiles, without Font.drawBox's white
  -- interior fill. This lets the catch background sit directly under the
  -- black frame so the frame itself masks/cuts the art cleanly.
  local function drawBoxBorderOnly(tx, ty, tw, th)
    local B = Font.BORDER
    love.graphics.setColor(0, 0, 0, 1)
    Font.drawCode(B.tl, tx * 8, ty * 8)
    Font.drawCode(B.tr, (tx + tw - 1) * 8, ty * 8)
    Font.drawCode(B.bl, tx * 8, (ty + th - 1) * 8)
    Font.drawCode(B.br, (tx + tw - 1) * 8, (ty + th - 1) * 8)
    for i = 1, tw - 2 do
      Font.drawCode(B.h, (tx + i) * 8, ty * 8)
      Font.drawCode(B.h, (tx + i) * 8, (ty + th - 1) * 8)
    end
    for j = 1, th - 2 do
      Font.drawCode(B.v, tx * 8, (ty + j) * 8)
      Font.drawCode(B.v, (tx + tw - 1) * 8, (ty + j) * 8)
    end
  end

  mod.content.screens:register(CAPTURE_SCREEN, {
    new = function(game, opts)
      opts = opts or {}
      local species = opts.species or "CATERPIE"
      local cfg = FIELD_NET_SPECIES[species] or FIELD_NET_SPECIES.CATERPIE

      -- Tile-aligned layout modeled after the user's mockup.
      local TOP_TX, TOP_TY, TOP_TW, TOP_TH = 1, 0, 18, 3
      local SCENE_TX, SCENE_TY, SCENE_TW, SCENE_TH = 1, 3, 18, 10
      local LEFT_TX, LEFT_TY, LEFT_TW, LEFT_TH = 1, 13, 9, 5
      local RIGHT_TX, RIGHT_TY, RIGHT_TW, RIGHT_TH = 10, 13, 9, 5
      -- Gameplay stays in the normal inner 128x64 area.  The art itself is
      -- expanded a few pixels into the border tile's WHITE padding, but stops
      -- before the actual black frame stroke.  This gives the larger image the
      -- user wanted without needing scissor/stencil tricks and without drawing
      -- over the black border.
      local SCENE_X, SCENE_Y = (SCENE_TX + 1) * 8, (SCENE_TY + 1) * 8
      local SCENE_W, SCENE_H = (SCENE_TW - 2) * 8, (SCENE_TH - 2) * 8
      local ART_X, ART_Y = SCENE_TX * 8 + 5, SCENE_TY * 8 + 5
      local ART_W, ART_H = SCENE_TW * 8 - 10, SCENE_TH * 8 - 10
      local MENU_ITEMS = { "CATCH", "WATCH", "LEAVE" }

      local state = {
        game = game,
        world = opts.world,
        isOpaque = false,
        species = species,
        sourceMap = opts.map,
        level = tonumber(opts.level) or math.random(cfg.levelMin or 3, cfg.levelMax or 5),
        shiny = opts.shiny and true or false,
        bg = fieldNetBackground(game),
        mode = "menu", -- menu | watch | catch
        menuIndex = 1,
        timer = 11.0, -- deliberately hidden from the UI
        attempts = 0,
        netX = SCENE_X + SCENE_W * 0.67,
        netY = SCENE_Y + SCENE_H * 0.72,
        targetX = SCENE_X + SCENE_W * 0.50,
        targetY = SCENE_Y + SCENE_H * 0.50,
        vx = 0,
        vy = 0,
        turnTimer = cfg.turn,
        moveTimer = 0.42,
        hopTime = nil,
        hopDuration = nil,
        hopFromX = nil, hopFromY = nil,
        hopToX = nil, hopToY = nil,
        swingTimer = 0,
        missTimer = 0,
        hitTimer = 0,
        netHits = 0,
        spookTimer = 0,
        runTimer = 0,
        catchAnim = nil,
        catchX = nil,
        catchY = nil,
        result = nil,
        bob = 0,
      }

      local function clamp(v, lo, hi)
        if v < lo then return lo end
        if v > hi then return hi end
        return v
      end

      local function rangef(lo, hi)
        lo, hi = tonumber(lo) or 0, tonumber(hi) or tonumber(lo) or 0
        return lo + love.math.random() * math.max(0, hi - lo)
      end

      local function beginSpeciesHop(self, forced)
        local dist = rangef(cfg.hopMin or 5, cfg.hopMax or 12)
        if forced then dist = dist * 1.35 end
        if cfg.movement == "still" and not forced and love.math.random() < 0.55 then
          dist = dist * 0.35
        end
        local angle = love.math.random() * math.pi * 2
        local dx = math.cos(angle) * dist
        local dy = math.sin(angle) * dist * 0.70
        self.hopFromX, self.hopFromY = self.targetX, self.targetY
        self.hopToX = clamp(self.targetX + dx, SCENE_X + 9, SCENE_X + SCENE_W - 9)
        self.hopToY = clamp(self.targetY + dy, SCENE_Y + 9, SCENE_Y + SCENE_H - 9)
        self.hopTime = 0
        self.hopDuration = math.max(0.05, (cfg.hopDuration or 0.12) * (forced and 0.78 or 1.0))
      end

      local function scheduleNextSpeciesHop(self)
        local delay = rangef(cfg.hopDelayMin or 0.35, cfg.hopDelayMax or 0.70)
        if self.spookTimer > 0 then delay = delay * 0.48 end
        self.moveTimer = delay
      end

      local function close(self)
        if game.stack and game.stack.pop then game.stack:pop() end
      end

      local function startCatch(self)
        self.mode = "catch"
        self.timer = 11.0
        self.attempts = 0
        self.result = nil
        self.runTimer = 0
        self.catchAnim = nil
        self.catchX = nil
        self.catchY = nil
        self.missTimer = 0
        self.hitTimer = 0
        self.netHits = 0
        self.spookTimer = 0
        self.swingTimer = 0
        self.netX = SCENE_X + SCENE_W * 0.70
        self.netY = SCENE_Y + SCENE_H * 0.76
        -- Every encounter begins in the middle so the player gets one clean
        -- look before its species-specific WATCH movement starts.
        self.targetX = SCENE_X + SCENE_W * 0.50
        self.targetY = SCENE_Y + SCENE_H * 0.50
        self.hopTime = nil
        self.moveTimer = 0.42
      end

      local function beginRun(self)
        if self.result then return end
        self.result = "escaped"
        self.runTimer = 0.45
        pcall(function() Sound.play(game.data, "Sfx_Run") end)
      end

      function state:update(dt)
        dt = tonumber(dt) or (1 / 60)
        if dt <= 0 or dt > 0.1 then dt = 1 / 60 end
        self.bob = self.bob + dt
        local input = game.input

        if self.mode == "menu" then
          if input and (input:wasPressed("b") or input:wasPressed("start")) then
            close(self)
            return
          end
          if input and input:wasPressed("up") then
            self.menuIndex = self.menuIndex - 1
            if self.menuIndex < 1 then self.menuIndex = #MENU_ITEMS end
          elseif input and input:wasPressed("down") then
            self.menuIndex = self.menuIndex + 1
            if self.menuIndex > #MENU_ITEMS then self.menuIndex = 1 end
          elseif input and input:wasPressed("a") then
            if self.menuIndex == 1 then
              startCatch(self)
            elseif self.menuIndex == 2 then
              if self.world and self.world.showText then
                self.world:showText(cfg.hint or "It seems ordinary.")
              end
            else
              close(self)
            end
          end
          return
        end

        -- Catch minigame.
        if self.catchAnim then
          self.catchAnim = self.catchAnim + dt
          if self.catchAnim >= 0.62 then
            self.catchAnim = nil
            local ok, destination, boxIndex = storeFieldNetCatch(
              game, self.species, self.level, self.sourceMap, self.world, self.shiny)
            if ok then
              self.result = "caught"
              self.catchDestination = destination
              self.catchBox = boxIndex
              pcall(function() Sound.play(game.data, "Sfx_CaughtMon") end)
            else
              self.result = "storage_full"
              self.catchError = destination
              pcall(function() Sound.play(game.data, "Sfx_Wrong") end)
            end
          end
          return
        end

        if self.result and self.runTimer <= 0 then
          if input and (input:wasPressed("a") or input:wasPressed("b")
              or input:wasPressed("start")) then
            local caughtMessage
            if self.result == "caught" then
              if self.catchDestination == "party" then
                caughtMessage = tostring(self.species) .. " added to\nyour party!"
              elseif self.catchDestination == "box" and self.catchBox then
                caughtMessage = tostring(self.species) .. " sent to\nBOX " .. tostring(self.catchBox) .. "!"
              end
            end
            close(self)
            if caughtMessage and self.world and self.world.showText then
              self.world:showText(caughtMessage)
            end
          end
          return
        end

        if input and (input:wasPressed("b") or input:wasPressed("start")) then
          close(self)
          return
        end

        self.timer = math.max(0, self.timer - dt)
        self.swingTimer = math.max(0, self.swingTimer - dt)
        self.missTimer = math.max(0, self.missTimer - dt)
        self.hitTimer = math.max(0, self.hitTimer - dt)
        self.spookTimer = math.max(0, self.spookTimer - dt)
        if self.timer <= 0 and not self.result then beginRun(self) end

        if self.runTimer > 0 then
          self.runTimer = math.max(0, self.runTimer - dt)
          self.targetX = self.targetX + 120 * dt
          self.targetY = self.targetY - 80 * dt
          return
        end

        local moveSpeed = 84
        if input then
          if input:isDown("left") then self.netX = self.netX - moveSpeed * dt end
          if input:isDown("right") then self.netX = self.netX + moveSpeed * dt end
          if input:isDown("up") then self.netY = self.netY - moveSpeed * dt end
          if input:isDown("down") then self.netY = self.netY + moveSpeed * dt end
        end
        self.netX = clamp(self.netX, SCENE_X + 7, SCENE_X + SCENE_W - 7)
        self.netY = clamp(self.netY, SCENE_Y + 7, SCENE_Y + SCENE_H - 7)

        -- Field Net targets move in readable but discontinuous hops rather than
        -- gliding on a predictable vector. WATCH reveals which cadence to expect.
        if self.hopTime ~= nil then
          self.hopTime = self.hopTime + dt
          local t = math.min(1, self.hopTime / math.max(0.01, self.hopDuration or 0.1))
          local smooth = t * t * (3 - 2 * t)
          self.targetX = self.hopFromX + (self.hopToX - self.hopFromX) * smooth
          self.targetY = self.hopFromY + (self.hopToY - self.hopFromY) * smooth
            - math.sin(t * math.pi) * (cfg.hopArc or 3)
          if t >= 1 then
            self.targetX, self.targetY = self.hopToX, self.hopToY
            self.hopTime = nil
            scheduleNextSpeciesHop(self)
          end
        else
          self.moveTimer = (self.moveTimer or 0) - dt
          if self.moveTimer <= 0 then beginSpeciesHop(self, false) end
        end

        if input and input:wasPressed("a") and self.swingTimer <= 0 and not self.result then
          self.attempts = self.attempts + 1
          self.swingTimer = 0.18
          local dx = math.abs(self.netX - self.targetX)
          local dy = math.abs((self.netY - 2) - self.targetY)
          if dx <= 10 and dy <= 9 then
            -- Being lined up is necessary, but skittish/harder species can still
            -- dodge the hoop. Some species also require more than one clean net
            -- contact before they are secured.
            if love.math.random() < (cfg.evadeChance or 0) then
              self.missTimer = 0.58
              self.spookTimer = 0.95
              beginSpeciesHop(self, true)
              pcall(function() Sound.play(game.data, "Sfx_Wrong") end)
            else
              self.netHits = (self.netHits or 0) + 1
              local required = math.max(1, tonumber(cfg.netHits) or 1)
              if self.netHits >= required then
                -- Freeze the target where the final net contact landed, then
                -- shrink it into a Poké Ball before the caught-mon fanfare.
                self.catchAnim = 0
                self.catchX = self.targetX
                self.catchY = self.targetY
                self.hopTime = nil
                self.vx, self.vy = 0, 0
                pcall(function() Sound.play(game.data, "Sfx_BallPoof") end)
              else
                self.hitTimer = 0.62
                self.spookTimer = 1.0
                beginSpeciesHop(self, true)
                pcall(function() Sound.play(game.data, "Tink") end)
              end
            end
          else
            self.missTimer = 0.58
            self.spookTimer = 0.85
            beginSpeciesHop(self, true)
            pcall(function() Sound.play(game.data, "Sfx_Wrong") end)
          end
        end
      end

      function state:draw()
        -- isOpaque=false lets StateStack draw the normal overworld beneath us.
        -- Do NOT call World:draw() again here: doing so inside the UI transform
        -- produces the giant/zoomed duplicate seen in DEV34.
        love.graphics.setColor(0, 0, 0, 1)

        -- Vanilla-style tile boxes instead of hand-drawn rectangles.
        Font.drawBox(TOP_TX, TOP_TY, TOP_TW, TOP_TH)
        Font.draw(self.species, (TOP_TX + 1) * 8, (TOP_TY + 1) * 8)
        -- DEV61: right-align the level inside the top box. The old fixed x=112
        -- put the final glyph into the right border for two-digit levels.
        local levelText = ("Lv.%d"):format(self.level)
        local levelRight = (TOP_TX + TOP_TW - 1) * 8
        Font.draw(levelText, levelRight - (#levelText * 8), (TOP_TY + 1) * 8)

        -- Draw the vanilla box normally, then enlarge the background into the
        -- box tile's white inner padding. It remains inside the black stroke.
        love.graphics.setColor(0, 0, 0, 1)
        Font.drawBox(SCENE_TX, SCENE_TY, SCENE_TW, SCENE_TH)
        local sceneBg = self.bg or fieldNetBackground(game)
        if sceneBg then
          love.graphics.setColor(1, 1, 1, 1)
          local bw, bh = sceneBg:getDimensions()
          love.graphics.draw(sceneBg, ART_X, ART_Y, 0, ART_W / bw, ART_H / bh)
        end

        -- Pokémon: static on initial encounter screen, moving in catch mode.
        local px, py
        if self.mode == "catch" then
          px, py = self.targetX, self.targetY
        else
          px = SCENE_X + SCENE_W * 0.50
          py = SCENE_Y + SCENE_H * 0.50 + math.sin(self.bob * 2.3) * 1.2
        end

        local monPic = fieldNetSprite(game, self.species)
        if self.catchAnim then
          local p = math.min(1, self.catchAnim / 0.62)
          local bx, by = self.catchX or px, self.catchY or py
          -- First beat: the mon flashes/folds down; second beat: only the ball
          -- remains. Scaling the battle pic toward zero gives the same read as
          -- the capture "suck-in" without pulling in the whole battle animator.
          if p < 0.72 then
            local shrink = math.max(0.08, 1 - (p / 0.72) * 0.92)
            local flicker = (math.floor(self.catchAnim * 24) % 2) == 0
            if not flicker or p < 0.18 then
              drawMonColored(game, self.species, monPic, bx, by, 27 * shrink, self.shiny, false)
            end
          end
          if p >= 0.18 then
            local ballScale = math.min(0.85, 0.35 + (p - 0.18) * 0.9)
            drawFieldNetBall(game, bx, by, ballScale)
          end
        elseif self.result == "caught" then
          -- Successful catch: the Pokémon is gone; leave the closed ball as
          -- the visual confirmation beside the CAUGHT status.
          drawFieldNetBall(game, self.catchX or px, self.catchY or py, 0.8)
        elseif not (self.result == "escaped" and self.runTimer <= 0) then
          -- During RUN, stop drawing once its center reaches the inside edge
          -- so it disappears behind the side border instead of popping outside.
          local visible = true
          if self.result == "escaped" then
            visible = px < (SCENE_X + SCENE_W - 5)
          end
          if visible then
            if not drawMonColored(game, self.species, monPic, px, py, 27, self.shiny, false) then
              love.graphics.setColor(0, 0, 0, 1)
              love.graphics.rectangle("fill", math.floor(px - 4), math.floor(py - 4), 8, 8)
            end
          end
        end

        love.graphics.setColor(0, 0, 0, 1)
        Font.drawBox(LEFT_TX, LEFT_TY, LEFT_TW, LEFT_TH)
        Font.drawBox(RIGHT_TX, RIGHT_TY, RIGHT_TW, RIGHT_TH)

        local ys = { 112, 120, 128 }
        local cursorIndex = self.mode == "menu" and self.menuIndex or 1
        for i, item in ipairs(MENU_ITEMS) do
          if i == cursorIndex then Chrome.cursor(2, 14 + (i - 1)) end
          -- Five-letter commands are 40px wide; x=24 centers them in the
          -- widened 72px left command box while leaving the cursor gutter.
          Font.draw(item, 24, ys[i])
        end

        if self.mode == "catch" then
          -- Net only exists once CATCH has actually been selected.
          if not self.result and not self.catchAnim then
            local nx, ny = math.floor(self.netX), math.floor(self.netY)
            if fieldNetCursor then
              love.graphics.setColor(1, 1, 1, 1)
              local swing = self.swingTimer > 0
              local rot = swing and -0.30 or 0
              local scale = swing and 0.86 or 0.80
              love.graphics.draw(fieldNetCursor, nx, ny + (swing and 2 or 0),
                rot, scale, scale,
                fieldNetCursor:getWidth() / 2,
                fieldNetCursor:getHeight() / 2)
            end
          end

          love.graphics.setColor(0, 0, 0, 1)
          local status
          if self.result == "caught" then status = "CAUGHT"
          elseif self.result == "storage_full" then status = "PC FULL"
          elseif self.result == "escaped" then status = "RAN!"
          elseif self.missTimer > 0 then status = "MISS!"
          elseif self.hitTimer > 0 then status = "AGAIN!" end
          if status then
            -- Right box spans x=80..152. Center 8px glyph text within it.
            local widths = { CAUGHT = 48, ["PC FULL"] = 56, ["MISS!"] = 40, ["RAN!"] = 32, ["AGAIN!"] = 48 }
            local sw = widths[status] or (#status * 8)
            Font.draw(status, 80 + math.floor((72 - sw) / 2), 120)
          end
        end
      end

      return state
    end,
  })

  ---------------------------------------------------------------------------
  -- VIVARIUM LOGBOOK
  -- Manual-page UI patterned after Angler's Cove: no autoscroll, two lines per
  -- page, and a persistent donation tally that the later JAXEN system can use.
  ---------------------------------------------------------------------------
  mod.content.screens:register(LOGBOOK_DIALOGUE, {
    new = function(game, opts)
      opts = opts or {}
      local pages = opts.pages or { "..." }
      local state = { game = game, pages = pages, page = 1, isOpaque = false }

      local function closeDialogue()
        if type(opts.onClose) == "function" then pcall(opts.onClose) end
        game.stack:pop()
      end

      function state:update()
        if game.input:wasPressed("b") then
          Sound.play(game.data, "Press_AB")
          closeDialogue()
        elseif game.input:wasPressed("a") then
          Sound.play(game.data, "Press_AB")
          if self.page < #self.pages then
            self.page = self.page + 1
          else
            closeDialogue()
          end
        end
      end

      function state:draw()
        Chrome.box(0, 12, 20, 6)
        local page = self.pages[self.page] or ""
        local a, b = page:match("([^\n]*)\n?(.*)")
        Chrome.print(a or "", 1, 14)
        if b and b ~= "" then Chrome.print(b, 1, 16) end
        if self.page < #self.pages then Chrome.print("▼", 18, 17) end
      end

      return state
    end,
  })

  mod.content.screens:register(DONATION_SCREEN, {
    new = function(game)
      local state = {
        game = game, tierIndex = 1, cursor = 1, top = 1, isOpaque = false,
      }
      local visibleRows = 4

      local function tierInfo(self)
        local name = DONATION_TIER_ORDER[self.tierIndex] or "common"
        return name, DONATION_TIERS[name]
      end

      local function clampView(self)
        local _, tier = tierInfo(self)
        local count = #(tier and tier.species or {})
        if count < 1 then self.cursor, self.top = 1, 1 return end
        if self.cursor < 1 then self.cursor = count end
        if self.cursor > count then self.cursor = 1 end
        if self.cursor < self.top then self.top = self.cursor end
        if self.cursor >= self.top + visibleRows then
          self.top = self.cursor - visibleRows + 1
        end
        local maxTop = math.max(1, count - visibleRows + 1)
        self.top = math.max(1, math.min(self.top, maxTop))
      end

      local function switchTier(self, delta)
        self.tierIndex = self.tierIndex + delta
        if self.tierIndex < 1 then self.tierIndex = #DONATION_TIER_ORDER end
        if self.tierIndex > #DONATION_TIER_ORDER then self.tierIndex = 1 end
        self.cursor, self.top = 1, 1
      end

      function state:update()
        local input = game.input
        if input:wasPressed("b") then
          Sound.play(game.data, "Press_AB")
          game.stack:pop()
        elseif input:wasPressed("left") then
          Sound.play(game.data, "Tink")
          switchTier(self, -1)
        elseif input:wasPressed("right") then
          Sound.play(game.data, "Tink")
          switchTier(self, 1)
        else
          local root = vivariumRoot(game)
          local tierName, tier = tierInfo(self)
          if donationTierUnlocked(root, tierName) then
            if input:wasPressed("up") then
              Sound.play(game.data, "Tink")
              self.cursor = self.cursor - 1
              clampView(self)
            elseif input:wasPressed("down") then
              Sound.play(game.data, "Tink")
              self.cursor = self.cursor + 1
              clampView(self)
            elseif input:wasPressed("a") then
              local species = tier and tier.species[self.cursor]
              if species then
                Sound.play(game.data, "Press_AB")
                local count = tonumber(root.donations[species]) or 0
                if count >= tier.goal then
                  mod.ui.push(game, LOGBOOK_DIALOGUE, {
                    pages = { species .. " quota\nis complete." },
                  })
                else
                  mod.ui.push(game, DONATE_SCREEN, { species = species })
                end
              end
            end
          end
        end
      end

      function state:draw()
        local root = vivariumRoot(game)
        local tierName, tier = tierInfo(self)
        local unlocked = donationTierUnlocked(root, tierName)
        Chrome.box(1, 1, 18, 16)
        Chrome.print("DONATIONS", 6, 2)
        Chrome.print((tier.label .. " " .. tier.goal), 3, 4)

        if not unlocked then
          Chrome.print("LOCKED", 7, 7)
          Chrome.print("Finish 6 COMMON", 2, 10)
          Chrome.print("goals first.", 4, 12)
        else
          Chrome.print("SPECIES", 3, 5)
          Chrome.print("GIVEN", 13, 5)
          for row = 0, visibleRows - 1 do
            local idx = self.top + row
            local species = tier.species[idx]
            if species then
              local y = 7 + row * 2
              if idx == self.cursor then Chrome.cursor(2, y) end
              Chrome.print(species, 3, y)
              local count = math.min(tier.goal, tonumber(root.donations[species]) or 0)
              Chrome.print(("%d/%d"):format(count, tier.goal), 13, y)
            end
          end
          if self.top > 1 then Chrome.print("▲", 18, 6) end
          if self.top + visibleRows - 1 < #tier.species then Chrome.print("▼", 18, 14) end
        end
        if unlocked then
          Chrome.print("L/R:TIER", 2, 15)
          Chrome.print("A:DONATE B:BACK", 2, 16)
        else
          Chrome.print("L/R:TIER", 2, 16)
          Chrome.print("B:BACK", 12, 16)
        end
      end

      return state
    end,
  })

  ---------------------------------------------------------------------------
  -- LOGBOOK DONATION HANDOFF
  -- The Logbook owns conservation submissions in DEV63. Selecting a species
  -- quota opens this filtered PARTY/PC picker, keeping JAXEN and FERN free to
  -- become dedicated clerks as their milestone stock is implemented.
  ---------------------------------------------------------------------------
  mod.content.screens:register(DONATE_SCREEN, {
    new = function(game, opts)
      opts = opts or {}
      local speciesFilter = opts.species
      local state = {
        game = game, cursor = 1, top = 1, mode = "list", confirmIndex = 2,
        messages = nil, messageIndex = 1, isOpaque = false,
        speciesFilter = speciesFilter,
      }
      local visibleRows = 5

      local function candidates()
        local root = vivariumRoot(game)
        local save = game.save or {}
        local rows = {}

        -- Storage comes first so repeated donations naturally consume boxed
        -- extras before touching the player's active team.
        for boxIndex = 1, Boxes.NUM_BOXES do
          local box = (save.boxes and save.boxes[boxIndex]) or {}
          for slot, mon in ipairs(box) do
            local spec = mon and not mon.isEgg and donationGoal(mon.species) or nil
            if spec and (not speciesFilter or mon.species == speciesFilter)
                and donationTierUnlocked(root, spec.tier) then
              local count = tonumber(root.donations[mon.species]) or 0
              if count < spec.goal then
                rows[#rows + 1] = {
                  source = "box", boxIndex = boxIndex, slot = slot,
                  species = mon.species, level = tonumber(mon.level) or 1,
                  count = count, goal = spec.goal,
                }
              end
            end
          end
        end

        for partyIndex, mon in ipairs(save.party or {}) do
          local spec = mon and not mon.isEgg and donationGoal(mon.species) or nil
          if spec and (not speciesFilter or mon.species == speciesFilter)
              and donationTierUnlocked(root, spec.tier) then
            local count = tonumber(root.donations[mon.species]) or 0
            if count < spec.goal then
              rows[#rows + 1] = {
                source = "party", partyIndex = partyIndex, species = mon.species,
                level = tonumber(mon.level) or 1, count = count, goal = spec.goal,
              }
            end
          end
        end
        return rows
      end

      local function clampView(self, count)
        count = math.max(0, tonumber(count) or 0)
        if count == 0 then self.cursor, self.top = 1, 1 return end
        if self.cursor < 1 then self.cursor = count end
        if self.cursor > count then self.cursor = 1 end
        if self.cursor < self.top then self.top = self.cursor end
        if self.cursor >= self.top + visibleRows then self.top = self.cursor - visibleRows + 1 end
        self.top = math.max(1, math.min(self.top, math.max(1, count - visibleRows + 1)))
      end

      local function beginMessage(self, pages)
        self.messages = pages or { "..." }
        self.messageIndex = 1
        self.mode = "message"
      end

      function state:update()
        local input = game.input
        if self.mode == "message" then
          if input:wasPressed("a") or input:wasPressed("b") then
            Sound.play(game.data, "Press_AB")
            if self.messageIndex < #(self.messages or {}) then
              self.messageIndex = self.messageIndex + 1
            else
              self.mode, self.messages = "list", nil
              local rows = candidates()
              clampView(self, #rows)
            end
          end
          return
        end

        local rows = candidates()
        clampView(self, #rows)

        if self.mode == "confirm" then
          if input:wasPressed("b") then
            Sound.play(game.data, "Press_AB")
            self.mode = "list"
          elseif input:wasPressed("up") or input:wasPressed("down")
              or input:wasPressed("left") or input:wasPressed("right") then
            Sound.play(game.data, "Tink")
            self.confirmIndex = self.confirmIndex == 1 and 2 or 1
          elseif input:wasPressed("a") then
            Sound.play(game.data, "Press_AB")
            if self.confirmIndex == 2 then
              self.mode = "list"
              return
            end
            local row = rows[self.cursor]
            if not row then self.mode = "list" return end
            local ok, result = donateOwnedMon(game, row)
            if not ok then
              beginMessage(self, { tostring(result or "Donation failed.") })
              return
            end
            pcall(function() Sound.playStereo(game.data, result.completed and "Sfx_Item" or "Tink") end)
            local pages = {
              (result.species .. " donated.\n" .. result.count .. "/" .. result.goal),
            }
            if result.completed then
              pages[#pages + 1] = result.species .. " quota\ncomplete!"
              if result.tier ~= "common" then
                pages[#pages + 1] = "JAXEN has a\nreward for you."
              end
            end
            if result.milestone then
              pages[#pages + 1] = result.milestone.owner .. " has new\nstock!"
              pages[#pages + 1] = result.milestone.item .. " is\nnow for sale."
              if result.milestone == SHOP_MILESTONES[6] then
                pages[#pages + 1] = "UNCOMMON and\nRARE goals open!"
              end
            end
            beginMessage(self, pages)
          end
          return
        end

        if input:wasPressed("b") then
          Sound.play(game.data, "Press_AB")
          game.stack:pop()
        elseif input:wasPressed("up") then
          Sound.play(game.data, "Tink")
          self.cursor = self.cursor - 1
          clampView(self, #rows)
        elseif input:wasPressed("down") then
          Sound.play(game.data, "Tink")
          self.cursor = self.cursor + 1
          clampView(self, #rows)
        elseif input:wasPressed("a") and #rows > 0 then
          Sound.play(game.data, "Press_AB")
          self.confirmIndex = 2
          self.mode = "confirm"
        end
      end

      function state:draw()
        local rows = candidates()
        clampView(self, #rows)
        Chrome.box(1, 1, 18, 16)
        if self.speciesFilter then
          Chrome.print("DONATE", 7, 2)
          local sx = math.max(2, 10 - math.floor(#self.speciesFilter / 2))
          Chrome.print(self.speciesFilter, sx, 4)
        else
          Chrome.print("DONATIONS", 6, 2)
        end

        if self.mode == "message" then
          local page = (self.messages or {})[self.messageIndex] or "..."
          local a, b = page:match("([^\n]*)\n?(.*)")
          Chrome.print(a or "", 2, 7)
          if b and b ~= "" then Chrome.print(b, 2, 9) end
          if self.messageIndex < #(self.messages or {}) then Chrome.print("▼", 17, 13) end
          Chrome.print("A/B", 8, 15)
          return
        end

        if #rows == 0 then
          Chrome.print("No eligible", 4, 8)
          Chrome.print("PKMN in PARTY/PC.", 2, 10)
          Chrome.print("B:BACK", 12, 16)
          return
        end

        if not self.speciesFilter then
          Chrome.print("SPECIES", 3, 4)
          Chrome.print("GOAL", 13, 4)
        end
        for row = 0, visibleRows - 1 do
          local idx = self.top + row
          local item = rows[idx]
          if item then
            local y = 6 + row * 2
            if idx == self.cursor and self.mode == "list" then Chrome.cursor(2, y) end
            if self.speciesFilter then
              local where = item.source == "box" and ("BOX " .. tostring(item.boxIndex)) or "PARTY"
              Chrome.print(where, 3, y)
              Chrome.print(("Lv.%d"):format(item.level), 12, y)
            else
              Chrome.print(item.species, 3, y)
              Chrome.print(("%d/%d"):format(item.count, item.goal), 13, y)
            end
          end
        end
        if self.top > 1 then Chrome.print("▲", 18, 5) end
        if self.top + visibleRows - 1 < #rows then Chrome.print("▼", 18, 15) end
        Chrome.print("A:DONATE", 2, 16)
        Chrome.print("B:BACK", 12, 16)

        if self.mode == "confirm" then
          local item = rows[self.cursor]
          Chrome.box(3, 5, 14, 8)
          Chrome.print("DONATE", 7, 6)
          Chrome.print(item and item.species or "POKEMON", 5, 8)
          if self.confirmIndex == 1 then Chrome.cursor(6, 10) else Chrome.cursor(6, 12) end
          Chrome.print("YES", 7, 10)
          Chrome.print("NO", 7, 12)
        end
      end

      return state
    end,
  })

  mod.content.screens:register(LOGBOOK_SCREEN, {
    new = function(game)
      local options = { "PROJECT", "DONATIONS", "TERRARIUM" }
      local state = { game = game, cursor = 1, isOpaque = false }

      local function projectPages()
        local root = vivariumRoot(game)
        local done = math.min(6, completedCommonGoals(root))
        return {
          "PROJECT:\nRestore VIRIDIAN.",
          "FIELD NET:\nUse near grass.",
          "Watch for grass\nto start rustling.",
          "Walk into the\nrustling patch.",
          "Find BUGS and\nplant POKEMON.",
          "BALL catches can\nhelp us too.",
          "Donate extras\nthrough LOGBOOK.",
          "COMMON goals\nneed 30 each.",
          ("SHOP GOALS:\n%d/6 complete."):format(done),
          "Each goal adds\nnew shop stock.",
          "Finish 6 goals\nfor harder goals.",
          "UNCOMMON: 15.\nRARE: 10 each.",
          "Talk to FERN.\nShe grows plants.",
        }
      end

      local function terrariumPages()
        return {
          "TERRARIUM:\nCare for PKMN.",
          "START opens the\nresident menu.",
          "LIGHTS ON help\nplants grow.",
          "LIGHTS OFF help\nmushrooms grow.",
          "Plant BERRIES in\nthe three plots.",
          "SEEDS and SPORES\nuse plots too.",
          "SQUIRT BOTTLE\nspeeds growth.",
          "FERTILIZER can\nboost harvests.",
          "SPARKLE BITS work\non residents.",
        }
      end

      function state:update()
        local input = game.input
        if input:wasPressed("b") then
          Sound.play(game.data, "Press_AB")
          game.stack:pop()
        elseif input:wasPressed("up") then
          Sound.play(game.data, "Tink")
          self.cursor = self.cursor - 1
          if self.cursor < 1 then self.cursor = #options end
        elseif input:wasPressed("down") then
          Sound.play(game.data, "Tink")
          self.cursor = self.cursor + 1
          if self.cursor > #options then self.cursor = 1 end
        elseif input:wasPressed("a") then
          Sound.play(game.data, "Press_AB")
          if self.cursor == 2 then
            mod.ui.push(game, DONATION_SCREEN)
          else
            local pages = self.cursor == 1 and projectPages() or terrariumPages()
            mod.ui.push(game, LOGBOOK_DIALOGUE, { pages = pages })
          end
        end
      end

      function state:draw()
        Chrome.box(1, 2, 18, 10)
        Chrome.print("LOGBOOK", 7, 3)
        for i, label in ipairs(options) do
          local y = 5 + (i - 1) * 2
          Chrome.print(label, 4, y)
          if self.cursor == i then Chrome.cursor(3, y) end
        end
      end

      return state
    end,
  })

  ---------------------------------------------------------------------------
  -- VIVARIUM RESIDENT MANAGEMENT
  -- DEV46 deliberately mirrors Angler's Cove's aquarium viewer structure:
  -- habitat art owns the upper 120px, a thin native footer owns the bottom,
  -- START opens a centered management panel, and add/remove lists use the same
  -- Crystal-style overlay/menu rhythm instead of a stack of permanent boxes.
  ---------------------------------------------------------------------------
  local vivariumLightsOnImage, vivariumLightsOffImage
  pcall(function()
    vivariumLightsOnImage = mod.assets:image("assets/terrarium_lights_on.png")
    if vivariumLightsOnImage then vivariumLightsOnImage:setFilter("nearest", "nearest") end
  end)
  pcall(function()
    vivariumLightsOffImage = mod.assets:image("assets/terrarium_lights_off.png")
    if vivariumLightsOffImage then vivariumLightsOffImage:setFilter("nearest", "nearest") end
  end)

  local plotUnwateredImage, plotWateredImage, plantGrowingImage, plantMatureImage
  local shroomGrowingImage, shroomMatureImage
  pcall(function()
    plotUnwateredImage = mod.assets:image("assets/plot_unwatered.png")
    plotWateredImage = mod.assets:image("assets/plot_watered.png")
    plantGrowingImage = mod.assets:image("assets/plant_growing.png")
    plantMatureImage = mod.assets:image("assets/plant_mature.png")
    shroomGrowingImage = mod.assets:image("assets/shroom_growing.png")
    shroomMatureImage = mod.assets:image("assets/shroom_mature.png")
    for _, img in ipairs({ plotUnwateredImage, plotWateredImage, plantGrowingImage,
        plantMatureImage, shroomGrowingImage, shroomMatureImage }) do
      if img then img:setFilter("nearest", "nearest") end
    end
  end)

  -- Ambient terrarium motes use Crystal's actual Razor Leaf artwork rather
  -- than procedural particles. In the vanilla PLANT battle-animation sheet,
  -- tiles 0-3 are the four Razor Leaf turn frames (the two Razor Leaf
  -- framesets reference exactly those four tiles), so we can reuse them here
  -- without drawing replacement art.
  local terrariumMoveEffectCache
  local function terrariumMoveEffect(game)
    if terrariumMoveEffectCache ~= nil then
      return terrariumMoveEffectCache ~= false and terrariumMoveEffectCache or nil
    end
    local data = game and game.data
    local anims = data and (data.gen2BattleAnims or data.battle_anims)
    local gfx = anims and anims.gfx
    if not gfx then terrariumMoveEffectCache = false return nil end

    local chosen = gfx.BATTLE_ANIM_GFX_PLANT
    if not chosen then
      for name, row in pairs(gfx) do
        if tostring(name):upper():find("PLANT", 1, true) and row and row.image then
          chosen = row
          break
        end
      end
    end
    if not (chosen and chosen.image) then terrariumMoveEffectCache = false return nil end

    local ok, image = pcall(Assets.image, chosen.image)
    if not (ok and image) then terrariumMoveEffectCache = false return nil end
    pcall(function() image:setFilter("nearest", "nearest") end)
    local iw, ih = image:getDimensions()
    local wide = math.max(1, tonumber(chosen.wide) or math.floor(iw / 8))
    local quads = {}
    -- Razor Leaf uses PLANT tiles 0,1,2,3. Keep the exact Game Boy frames.
    for tile = 0, 3 do
      local tx = tile % wide
      local ty = math.floor(tile / wide)
      if tx * 8 + 8 <= iw and ty * 8 + 8 <= ih then
        quads[#quads + 1] = love.graphics.newQuad(tx * 8, ty * 8, 8, 8, iw, ih)
      end
    end
    if #quads == 0 then terrariumMoveEffectCache = false return nil end
    terrariumMoveEffectCache = { image = image, quads = quads }
    return terrariumMoveEffectCache
  end

  -- Bright leafy GBC ramp for Razor Leaf particles. The move's own 2bpp pixels
  -- remain the artwork; only its palette is supplied here.
  local TERRARIUM_LEAF_COLORS = {
    { 224, 248, 184 }, { 136, 216, 96 }, { 56, 144, 64 }, { 16, 72, 40 },
  }

  local function specimenLabel(specimen)
    if not specimen then return "---" end
    return ("%s  Lv%d"):format(specimen.species or "?", tonumber(specimen.level) or 1)
  end

  mod.content.screens:register(VIVARIUM_SCREEN, {
    new = function(game, opts)
      opts = opts or {}
      local root = vivariumRoot(game)
      local habitat = root.vivarium
      local legacyStorage = root.fieldNet.specimens
      local W, H, UI_Y = 160, 144, 120

      local self = {
        game = game,
        world = opts.world,
        isOpaque = true,
        mode = "view", -- view | manage | add | remove | message
        cursor = 1,
        message = nil,
        messageReturn = "manage",
        movers = {},
        particles = {},
        sparkles = {},
        sparkleTimer = 0,
        sparklePending = nil,
        selectedPlot = nil,
        infoIndex = nil,
      }

      syncVivariumPlots(game, habitat)

      local function close()
        if game.stack and game.stack.pop then game.stack:pop() end
      end

      local function showMessage(msg, returnMode)
        self.message = msg
        self.messageReturn = returnMode or "manage"
        self.mode = "message"
      end

      local function specimenMon(specimen)
        return specimen and specimen.mon or nil
      end

      local function restoreSpecimenMon(specimen)
        if not specimen or not CONSERVATION_SPECIES[specimen.species] then return nil end
        local mon = specimen.mon
        if not mon then
          mon = Mon.new(game.data, specimen.species, tonumber(specimen.level) or 1)
          if mon then
            Mon.stampOT(game.save, mon)
            specimen.mon = mon
          end
        end
        if not mon then return nil end

        specimen.species = mon.species or specimen.species
        specimen.level = tonumber(mon.level) or tonumber(specimen.level) or 1
        if specimen.vfrPrime then
          mon.vfrPrime = true
          mon.shiny = true
        elseif specimen.shiny then
          mon.shiny = true
        end
        if mon.vfrPrime then
          specimen.vfrPrime = true
          specimen.shiny = true
          mon.shiny = true
          refreshPrimeStats(mon, game.data)
        elseif mon.shiny then
          specimen.shiny = true
        end
        return mon
      end

      local function addCandidates()
        local rows = {}
        for partyIndex, mon in ipairs((game.save and game.save.party) or {}) do
          if mon and not mon.isEgg and isVivariumSpecies(game, mon.species) then
            rows[#rows + 1] = {
              source = "party", partyIndex = partyIndex, mon = mon,
              species = mon.species, level = mon.level,
            }
          end
        end
        -- Keep old DEV44-46 specimen saves usable without duplicating new catches.
        for storageIndex, specimen in ipairs(legacyStorage or {}) do
          rows[#rows + 1] = {
            source = "legacy", storageIndex = storageIndex,
            species = specimen.species, level = specimen.level,
            legacySpecimen = specimen,
          }
        end
        return rows
      end

      local function berryCandidates()
        local rows = {}
        local inv = (game.save and game.save.inventory) or {}
        for id, qty in pairs(inv) do
          local plantable = tostring(id):find("BERRY", 1, true) ~= nil
            or id == BERRY_SEED or id == FUNGI_SPORES
          if (tonumber(qty) or 0) > 0 and plantable and id ~= "BERRY_JUICE" then
            local def = game.data and game.data.items and game.data.items[id]
            local label = (def and def.name) or tostring(id):gsub("_", " ")
            rows[#rows + 1] = { id = id, qty = qty, label = tostring(label) }
          end
        end
        table.sort(rows, function(a, b) return a.label < b.label end)
        return rows
      end

      local function fertilizerCount()
        return tonumber(((game.save or {}).inventory or {})[FERTILIZER]) or 0
      end

      local function sparkleCount()
        return tonumber(((game.save or {}).inventory or {})[SPARKLE_BITS]) or 0
      end

      local function hasSquirtBottle()
        return (((game.save or {}).inventory or {}).SQUIRTBOTTLE or 0) > 0
      end

      local function plotIsMature(plot)
        return plot and plot.item and (tonumber(plot.progress) or 0) >= VIV_PLANT_MATURE
      end

      local function anyOccupiedPlot()
        for _, plot in ipairs(habitat.plots or {}) do if plot.item then return true end end
        return false
      end

      local function maturePlotRows()
        local rows = {}
        for i, plot in ipairs(habitat.plots or {}) do
          if plotIsMature(plot) then rows[#rows + 1] = { plotIndex = i, plot = plot } end
        end
        return rows
      end

      local START_POSITIONS = {
        { 20, 54 }, { 138, 65 }, { 28, 82 }, { 128, 91 }, { 80, 99 },
      }

      local function refreshMovers()
        local old = self.movers or {}
        local fresh = {}
        for i, specimen in ipairs(habitat.residents) do
          local m = old[i] or {}
          m.specimen = specimen
          m.role = vivariumRole(game, specimen.species)
          m.anim = m.anim or (love.math.random() * 10)
          local pos = START_POSITIONS[i] or { 80, 80 }
          if m.role == "bug" then
            -- Bugs favor the side vines/trunks and crawl vertically.
            m.side = m.side or ((i % 2 == 0) and "right" or "left")
            m.anchorX = (m.side == "left") and (16 + (i % 2) * 8) or (144 - (i % 2) * 8)
            m.x = m.x or m.anchorX
            m.y = m.y or (32 + ((i * 17) % 64))
            m.baseSpeed = math.max(5, math.min(13, ((FIELD_NET_SPECIES[specimen.species] or {}).speed or 14) * 0.42))
            m.vx = 0
            m.vy = m.vy or ((i % 2 == 0) and m.baseSpeed or -m.baseSpeed)
          elseif m.role == "plant" then
            -- Grass types stay low and roam the clearing horizontally.
            m.x = m.x or pos[1]
            m.y = m.y or (91 + ((i * 7) % 14))
            m.baseSpeed = 8 + (i % 4)
            m.vx = m.vx or ((i % 2 == 0) and -m.baseSpeed or m.baseSpeed)
            m.vy = 0
          else
            m.x = m.x or pos[1]
            m.y = m.y or pos[2]
            m.baseSpeed = 5
            m.vx = m.vx or ((i % 2 == 0) and -5 or 5)
            m.vy = m.vy or 1
          end
          fresh[i] = m
        end
        self.movers = fresh
      end
      refreshMovers()

      -- Razor Leaf particles now fall naturally from above, land on the grass
      -- briefly, then disappear and respawn overhead.
      local function resetLeaf(p, initial)
        p.x = 8 + love.math.random() * 144
        p.floorY = 98 + love.math.random() * 12
        p.y = initial and (-4 + love.math.random() * (p.floorY + 4))
          or (-8 - love.math.random() * 34)
        p.vx = (love.math.random() * 2 - 1) * 1.3
        p.vy = 5.2 + love.math.random() * 4.2
        p.phase = love.math.random() * 10
        p.scale = 0.78 + love.math.random() * 0.28
        p.rest = 0
      end
      for i = 1, 7 do
        local leaf = {}
        resetLeaf(leaf, true)
        self.particles[i] = leaf
      end

      local function manageOptions()
        syncVivariumPlots(game, habitat)
        local options = {}
        if #habitat.residents < habitat.capacity and #addCandidates() > 0 then
          options[#options + 1] = { id = "add", label = "ADD" }
        end
        if #habitat.residents > 0 then
          options[#options + 1] = { id = "remove", label = "REMOVE" }
          options[#options + 1] = { id = "info", label = "VIEW INFO" }
        end
        options[#options + 1] = { id = "plant", label = "PLANT" }
        if hasSquirtBottle() and anyOccupiedPlot() then
          options[#options + 1] = { id = "water", label = "WATER" }
        end
        if fertilizerCount() > 0 and anyOccupiedPlot() then
          options[#options + 1] = { id = "fertilize", label = "FERTILIZE" }
        end
        if sparkleCount() > 0 and #habitat.residents > 0 then
          options[#options + 1] = { id = "sparkle", label = "SPARKLE" }
        end
        if #maturePlotRows() > 0 then
          options[#options + 1] = { id = "harvest", label = "HARVEST" }
        end
        options[#options + 1] = { id = "cancel", label = "CANCEL" }
        return options
      end

      local function addSelected()
        local rows = addCandidates()
        if #rows == 0 then showMessage("No eligible\nPKMN in party.", "manage") return end
        if #habitat.residents >= habitat.capacity then showMessage("VIVARIUM is\nfull.", "manage") return end
        self.cursor = math.max(1, math.min(self.cursor, #rows))
        local row = rows[self.cursor]
        local specimen
        if row.source == "party" then
          local party = game.save.party or {}
          local mon = party[row.partyIndex]
          if not mon then showMessage("That PKMN is\nno longer there.", "manage") return end
          if Mail.monHoldsMail(mon) then showMessage("Remove MAIL first.", "manage") return end
          if (mon.hp or 0) > 0 and Boxes.healthyCount(party) <= 1 then
            showMessage("Keep one healthy\nPKMN with you.", "manage")
            return
          end
          table.remove(party, row.partyIndex)
          Mail.removeSlot(game.save, row.partyIndex)
          specimen = {
            id = habitat.nextResidentId,
            species = mon.species, level = mon.level, mon = mon,
            shiny = mon.shiny and true or nil,
            vfrPrime = mon.vfrPrime and true or nil,
          }
          habitat.nextResidentId = habitat.nextResidentId + 1
        else
          local old = table.remove(legacyStorage, row.storageIndex)
          specimen = old or { species = row.species, level = row.level }
          specimen.id = specimen.id or habitat.nextResidentId
          habitat.nextResidentId = math.max(habitat.nextResidentId + 1, (tonumber(specimen.id) or 0) + 1)
        end
        habitat.residents[#habitat.residents + 1] = specimen
        refreshMovers()
        showMessage((specimen.species or "POKEMON") .. " was added.", "manage")
      end

      local function removeSelected()
        if #habitat.residents == 0 then showMessage("VIVARIUM is\nempty.", "manage") return end
        self.cursor = math.max(1, math.min(self.cursor, #habitat.residents))
        local specimen = habitat.residents[self.cursor]
        local mon = restoreSpecimenMon(specimen)
        if not mon then showMessage("Couldn't restore\nthat POKEMON.", "manage") return end
        local ok, destination, boxIndex = placeOwnedMon(game, mon, false)
        if not ok then showMessage("Party and PC\nare full.", "remove") return end
        table.remove(habitat.residents, self.cursor)
        refreshMovers()
        local dest = destination == "box" and ("BOX " .. tostring(boxIndex or "")) or "PARTY"
        showMessage((specimen.species or "POKEMON") .. " returned to " .. dest .. ".", "manage")
      end

      local function plantSelectedBerry()
        local rows = berryCandidates()
        local idx = tonumber(self.selectedPlot) or 1
        local plot = habitat.plots[idx]
        if not plot or plot.item then showMessage("That plot is\nalready in use.", "manage") return end
        if #rows == 0 then showMessage("You have no\nBERRIES.", "manage") return end
        self.cursor = math.max(1, math.min(self.cursor, #rows))
        local row = rows[self.cursor]
        if not row then return end
        syncVivariumPlots(game, habitat)
        Bag.remove(game.save, row.id, 1)
        plot.cropType = (row.id == FUNGI_SPORES) and "fungus" or "plant"
        plot.item = row.id
        if row.id == BERRY_SEED then
          plot.harvestItem = BERRY_SEED_RESULTS[love.math.random(#BERRY_SEED_RESULTS)]
        elseif row.id == FUNGI_SPORES then
          plot.harvestItem = (love.math.random(100) <= 20) and "BIG_MUSHROOM" or "TINYMUSHROOM"
        else
          plot.harvestItem = row.id
        end
        plot.fertilized = false
        plot.progress = 0
        plot.waterMinutes = 0
        plot.lastStamp = vivariumClockStamp(game.save)
        showMessage(row.label .. " planted in PLOT " .. tostring(idx) .. ".", "manage")
      end

      local function waterPlots()
        if not hasSquirtBottle() then showMessage("You need the\nSQUIRT BOTTLE.", "manage") return end
        syncVivariumPlots(game, habitat)
        local count = 0
        for _, plot in ipairs(habitat.plots or {}) do
          if plot.item then
            plot.waterMinutes = VIV_WATER_DURATION
            plot.lastStamp = vivariumClockStamp(game.save)
            count = count + 1
          end
        end
        if count == 0 then showMessage("Nothing needs\nwatering.", "manage") return end
        pcall(function() Sound.play(game.data, "Sfx_WaterGun") end)
        showMessage("All planted plots\nwere watered.", "manage")
      end

      local function fertilizeSelected()
        local idx = tonumber(self.cursor) or 1
        local plot = habitat.plots[idx]
        if not (plot and plot.item) then showMessage("That plot is\nempty.", "fertilize") return end
        if plot.fertilized then showMessage("Plot already\nfertilized.", "fertilize") return end
        if fertilizerCount() < 1 then showMessage("You have no\nFERTILIZER.", "manage") return end
        Bag.remove(game.save, FERTILIZER, 1)
        plot.fertilized = true
        pcall(function() Sound.playStereo(game.data, "Sfx_Item") end)
        showMessage("PLOT " .. tostring(idx) .. " was\nfertilized.", "manage")
      end

      local function ensureSpecimenMon(specimen)
        return restoreSpecimenMon(specimen)
      end

      local function shuffledResidentIndices()
        local order = {}
        for i = 1, #habitat.residents do order[i] = i end
        for i = #order, 2, -1 do
          local j = love.math.random(i)
          order[i], order[j] = order[j], order[i]
        end
        return order
      end

      -- One use showers the whole habitat. Every eligible resident gets a roll,
      -- but the first successful transformation ends the pass so a single bag
      -- of Sparkle Bits can never transform more than one resident.
      local function rollSparkleResult()
        local dev = vfrDevData(game.save)
        local forced = dev.nextSparkleResult
        dev.nextSparkleResult = nil
        local order = shuffledResidentIndices()

        if forced == "prime" then
          -- Prefer a shiny resident for a faithful shiny -> PRIME test. If there
          -- isn't one, allow the DEV override to create PRIME directly.
          for _, idx in ipairs(order) do
            local specimen = habitat.residents[idx]
            local mon = ensureSpecimenMon(specimen)
            if mon and not (mon.vfrPrime or specimen.vfrPrime)
                and (mon.shiny or specimen.shiny) then
              return { index = idx, kind = "prime" }
            end
          end
          for _, idx in ipairs(order) do
            local specimen = habitat.residents[idx]
            local mon = ensureSpecimenMon(specimen)
            if mon and not (mon.vfrPrime or specimen.vfrPrime) then
              return { index = idx, kind = "prime" }
            end
          end
        elseif forced == "shiny" then
          for _, idx in ipairs(order) do
            local specimen = habitat.residents[idx]
            local mon = ensureSpecimenMon(specimen)
            if mon and not (mon.vfrPrime or specimen.vfrPrime)
                and not (mon.shiny or specimen.shiny) then
              return { index = idx, kind = "shiny" }
            end
          end
        end

        for _, idx in ipairs(order) do
          local specimen = habitat.residents[idx]
          local mon = ensureSpecimenMon(specimen)
          if mon and not (mon.vfrPrime or specimen.vfrPrime) then
            if mon.shiny or specimen.shiny then
              if love.math.random() < SPARKLE_PRIME_CHANCE then
                return { index = idx, kind = "prime" }
              end
            elseif love.math.random() < SPARKLE_SHINY_CHANCE then
              return { index = idx, kind = "shiny" }
            end
          end
        end
        return nil
      end

      local function resolveSparkleResult(result)
        if not result then
          showMessage("The SPARKLE BITS\nfaded away...", "manage")
          return
        end
        local specimen = habitat.residents[result.index]
        local mon = ensureSpecimenMon(specimen)
        if not (specimen and mon) then
          showMessage("The SPARKLE BITS\nfaded away...", "manage")
          return
        end
        if result.kind == "prime" then
          mon.shiny = true
          mon.vfrPrime = true
          specimen.shiny = true
          specimen.vfrPrime = true
          refreshPrimeStats(mon, game.data)
          showMessage((specimen.species or "POKEMON") .. " became\nPRIME!", "manage")
        else
          mon.shiny = true
          specimen.shiny = true
          showMessage((specimen.species or "POKEMON") .. " shed its skin!\nIt's SHINY!", "manage")
        end
      end

      local function beginSparkle()
        if #habitat.residents == 0 then
          showMessage("The VIVARIUM is\nempty.", "manage")
          return
        end
        if sparkleCount() < 1 then
          showMessage("You have no\nSPARKLE BITS.", "manage")
          return
        end
        Bag.remove(game.save, SPARKLE_BITS, 1)
        self.sparklePending = rollSparkleResult()
        self.sparkles = {}
        for i = 1, 18 do
          self.sparkles[i] = {
            x = 8 + love.math.random() * 144,
            y = -8 - love.math.random() * 34,
            speed = 24 + love.math.random() * 18,
            drift = (love.math.random() * 2 - 1) * 4,
            phase = love.math.random() * 10,
          }
        end
        self.sparkleTimer = 2.6
        self.mode = "sparkle_anim"
        pcall(function() Sound.playStereo(game.data, "Sfx_Item") end)
      end

      local function harvestSelected()
        local rows = maturePlotRows()
        if #rows == 0 then showMessage("Nothing is ready\nto harvest.", "manage") return end
        self.cursor = math.max(1, math.min(self.cursor, #rows))
        local row = rows[self.cursor]
        local plot = row and row.plot
        if not plot or not plot.item then return end
        local item = plot.harvestItem or plot.item
        local qty = 1
        if plot.fertilized == true then qty = love.math.random(1, 3) end
        if not Bag.add(game.save, item, qty, game.data) then
          showMessage("PACK needs room\nfor the harvest.", "harvest")
          return
        end
        local def = game.data and game.data.items and game.data.items[item]
        local label = tostring((def and def.name) or item):gsub("_", " ")
        pcall(function() Sound.playStereo(game.data, "Sfx_Item") end)
        habitat.plots[row.plotIndex] = { cropType = nil, item = nil, harvestItem = nil, fertilized = false, progress = 0, waterMinutes = 0, lastStamp = vivariumClockStamp(game.save) }
        showMessage("Harvested " .. tostring(qty) .. " " .. label .. ".", "manage")
      end

      local function setLights(on)
        syncVivariumPlots(game, habitat)
        habitat.lightsOn = on and true or false
        pcall(function() Sound.play(game.data, "Sfx_SwitchPockets") end)
      end

      function self:update(dt)
        dt = tonumber(dt) or (1 / 60)
        if dt <= 0 or dt > 0.1 then dt = 1 / 60 end
        local input = game.input

        for _, p in ipairs(self.particles) do
          p.phase = p.phase + dt
          if (p.rest or 0) > 0 then
            p.rest = math.max(0, p.rest - dt)
            if p.rest <= 0 then resetLeaf(p, false) end
          else
            p.x = p.x + p.vx * dt + math.sin(p.phase * 1.25) * 0.35 * dt
            p.y = p.y + p.vy * dt
            if p.x < 5 then p.x = 5 p.vx = math.abs(p.vx) end
            if p.x > 155 then p.x = 155 p.vx = -math.abs(p.vx) end
            if p.y >= (p.floorY or 106) then
              p.y = p.floorY or 106
              p.vx, p.vy = 0, 0
              p.rest = 1.0 + love.math.random() * 1.0
            end
          end
        end

        for _, m in ipairs(self.movers) do
          m.anim = (m.anim or 0) + dt
          local active = (m.role == "bug" and not habitat.lightsOn)
            or (m.role == "plant" and habitat.lightsOn)
          -- The preferred lighting state is the resident's normal/lively
          -- baseline speed. The opposite lighting state is deliberately much
          -- calmer; no extra boost is applied to the lively state.
          local factor = active and 0.60 or 0.20
          if m.role == "bug" then
            m.y = m.y + m.vy * dt * factor
            m.x = (m.anchorX or m.x) + math.sin(m.anim * 0.9) * 1.5
            if m.y < 24 then m.y = 24 m.vy = math.abs(m.vy) end
            if m.y > 106 then m.y = 106 m.vy = -math.abs(m.vy) end
          elseif m.role == "plant" then
            m.x = m.x + m.vx * dt * factor
            m.y = 94 + math.sin(m.anim * 0.7 + (m.x or 0) * 0.02) * 3
            if m.x < 18 then m.x = 18 m.vx = math.abs(m.vx) end
            if m.x > 142 then m.x = 142 m.vx = -math.abs(m.vx) end
          else
            m.x = m.x + m.vx * dt * factor
            m.y = m.y + m.vy * dt * factor
            if m.x < 14 then m.x = 14 m.vx = math.abs(m.vx) end
            if m.x > 146 then m.x = 146 m.vx = -math.abs(m.vx) end
            if m.y < 48 then m.y = 48 m.vy = math.abs(m.vy) end
            if m.y > 108 then m.y = 108 m.vy = -math.abs(m.vy) end
          end
        end

        if self.mode == "sparkle_anim" then
          self.sparkleTimer = math.max(0, (tonumber(self.sparkleTimer) or 0) - dt)
          for _, bit in ipairs(self.sparkles or {}) do
            bit.phase = (bit.phase or 0) + dt
            bit.x = bit.x + (bit.drift or 0) * dt + math.sin(bit.phase * 2.1) * 0.35
            bit.y = bit.y + (bit.speed or 28) * dt
            if bit.y > 116 then
              bit.y = -4 - love.math.random() * 18
              bit.x = 8 + love.math.random() * 144
            end
          end
          if self.sparkleTimer <= 0 then
            local result = self.sparklePending
            self.sparklePending = nil
            self.sparkles = {}
            resolveSparkleResult(result)
          end
          return
        end

        if self.mode == "view" then
          if input and input:wasPressed("start") then
            self.mode = "manage" self.cursor = 1
          elseif input and input:wasPressed("a") then
            setLights(not habitat.lightsOn)
          elseif input and input:wasPressed("b") then
            close()
          end
          return
        end

        if self.mode == "message" then
          if input and (input:wasPressed("a") or input:wasPressed("b") or input:wasPressed("start")) then
            self.mode = self.messageReturn or "manage"
            self.message = nil
            self.cursor = 1
          end
          return
        end

        if self.mode == "manage" then
          local options = manageOptions()
          if input and input:wasPressed("b") then self.mode = "view" self.cursor = 1 return end
          if input and input:wasPressed("up") then
            self.cursor = self.cursor - 1
            if self.cursor < 1 then self.cursor = #options end
          elseif input and input:wasPressed("down") then
            self.cursor = self.cursor + 1
            if self.cursor > #options then self.cursor = 1 end
          elseif input and input:wasPressed("a") then
            local opt = options[self.cursor]
            if opt and opt.id == "add" then self.mode = "add" self.cursor = 1
            elseif opt and opt.id == "remove" then self.mode = "remove" self.cursor = 1
            elseif opt and opt.id == "info" then self.mode = "info_select" self.cursor = 1
            elseif opt and opt.id == "plant" then
              self.mode = "plot_select" self.cursor = 1
            elseif opt and opt.id == "water" then waterPlots()
            elseif opt and opt.id == "fertilize" then self.mode = "fertilize" self.cursor = 1
            elseif opt and opt.id == "sparkle" then beginSparkle()
            elseif opt and opt.id == "harvest" then self.mode = "harvest" self.cursor = 1
            else self.mode = "view" self.cursor = 1 end
          end
          return
        end

        if self.mode == "plot_select" then
          if input and input:wasPressed("b") then self.mode = "manage" self.cursor = 1 return end
          if input and input:wasPressed("up") then
            self.cursor = self.cursor - 1
            if self.cursor < 1 then self.cursor = 3 end
          elseif input and input:wasPressed("down") then
            self.cursor = self.cursor + 1
            if self.cursor > 3 then self.cursor = 1 end
          elseif input and input:wasPressed("a") then
            local plot = habitat.plots[self.cursor]
            if plot and plot.item then
              showMessage("Plot already\nplanted.", "plot_select")
            elseif #berryCandidates() == 0 then
              showMessage("You don't have\nanything to plant.", "plot_select")
            else
              self.selectedPlot = self.cursor
              self.mode = "berry"
              self.cursor = 1
            end
          end
          return
        end

        if self.mode == "info" then
          if input and (input:wasPressed("a") or input:wasPressed("b") or input:wasPressed("start")) then
            self.mode = "info_select"
            self.cursor = self.infoIndex or 1
          end
          return
        end

        local list
        if self.mode == "add" then list = addCandidates()
        elseif self.mode == "remove" then list = habitat.residents
        elseif self.mode == "info_select" then list = habitat.residents
        elseif self.mode == "berry" then list = berryCandidates()
        elseif self.mode == "fertilize" then list = habitat.plots
        elseif self.mode == "harvest" then list = maturePlotRows()
        else list = {} end
        if input and input:wasPressed("b") then
          if self.mode == "berry" then self.mode = "plot_select" self.cursor = self.selectedPlot or 1
          else self.mode = "manage" self.cursor = 1 end
          return
        end
        if #list == 0 then self.mode = "manage" self.cursor = 1 return end
        if input and input:wasPressed("up") then
          self.cursor = self.cursor - 1
          if self.cursor < 1 then self.cursor = #list end
        elseif input and input:wasPressed("down") then
          self.cursor = self.cursor + 1
          if self.cursor > #list then self.cursor = 1 end
        elseif input and input:wasPressed("a") then
          if self.mode == "add" then addSelected()
          elseif self.mode == "remove" then removeSelected()
          elseif self.mode == "info_select" then
            self.infoIndex = self.cursor
            self.mode = "info"
            self.cursor = 1
          elseif self.mode == "berry" then plantSelectedBerry()
          elseif self.mode == "fertilize" then fertilizeSelected()
          elseif self.mode == "harvest" then harvestSelected() end
        end
      end

      local function drawMoveParticles()
        local fx = terrariumMoveEffect(game)
        if not fx then return end
        local quads = fx.quads
        local function paintLeaves()
          love.graphics.setColor(1, 1, 1, 1)
          for i, p in ipairs(self.particles) do
            local qi = ((math.floor(p.phase * 0.75) + i - 1) % #quads) + 1
            love.graphics.draw(fx.image, quads[qi], math.floor(p.x), math.floor(p.y),
              0, p.scale, p.scale, 4, 4)
          end
        end
        if GbcPalette.available and GbcPalette.available() then
          GbcPalette.with(TERRARIUM_LEAF_COLORS, paintLeaves)
        else
          love.graphics.setColor(0.55, 0.95, 0.42, 1)
          for i, p in ipairs(self.particles) do
            local qi = ((math.floor(p.phase * 0.75) + i - 1) % #quads) + 1
            love.graphics.draw(fx.image, quads[qi], math.floor(p.x), math.floor(p.y),
              0, p.scale, p.scale, 4, 4)
          end
        end
        love.graphics.setColor(1, 1, 1, 1)
      end

      local function drawHabitat()
        love.graphics.clear(0.03, 0.09, 0.08, 1)
        love.graphics.setColor(1, 1, 1, 1)
        local image = habitat.lightsOn and vivariumLightsOnImage or vivariumLightsOffImage
        if image then love.graphics.draw(image, 0, 0)
        else love.graphics.rectangle("fill", 0, 0, W, UI_Y) end

        syncVivariumPlots(game, habitat)

        for _, m in ipairs(self.movers) do
          local specimen = m.specimen
          local sprite = terrariumResidentSprite(game, specimen.species)
          if not drawTerrariumResident(game, specimen.species, sprite, m.x, m.y, m.vx, m.anim, specimen) then
            local pic = fieldNetSprite(game, specimen.species)
            drawMonColored(game, specimen.species, pic, m.x, m.y, 18,
              (specimen.mon and specimen.mon.shiny) or specimen.shiny,
              (specimen.mon and specimen.mon.vfrPrime) or specimen.vfrPrime)
          end
        end

        -- Soil/crop plots sit above residents so low-roaming Grass Pokémon can
        -- pass behind the plots instead of drawing over them.
        local plotX = { 56, 80, 104 }
        local plotY = 102
        for i, plot in ipairs(habitat.plots or {}) do
          local x = plotX[i] or (56 + (i - 1) * 24)
          local progress = tonumber(plot.progress) or 0
          if plot.item and progress >= VIV_PLANT_MATURE then
            local mature = (plot.cropType == "fungus") and shroomMatureImage or plantMatureImage
            if mature then love.graphics.draw(mature, x - 8, plotY - 8) end
          elseif plot.item and progress >= (VIV_PLANT_MATURE * 0.5) then
            local growing = (plot.cropType == "fungus") and shroomGrowingImage or plantGrowingImage
            if growing then love.graphics.draw(growing, x - 8, plotY - 8) end
          else
            local soil = ((tonumber(plot.waterMinutes) or 0) > 0) and plotWateredImage or plotUnwateredImage
            if soil then love.graphics.draw(soil, x - 8, plotY - 8) end
          end
        end

        -- Ambient leaves stay above habitat objects.
        drawMoveParticles()
        -- Sparkle Bits mimic Angler's Cove's falling PokéFlakes, except no
        -- resident chases/eats them: the whole habitat is showered at once.
        if #(self.sparkles or {}) > 0 then
          for i, bit in ipairs(self.sparkles) do
            if (i % 2) == 0 then
              love.graphics.setColor(1.00, 0.82, 0.18, 1)
            else
              love.graphics.setColor(1.00, 0.58, 0.08, 1)
            end
            local x, y = math.floor(bit.x + 0.5), math.floor(bit.y + 0.5)
            if (i % 3) == 0 then
              love.graphics.rectangle("fill", x, y, 1, 2)
            else
              love.graphics.rectangle("fill", x, y, 2, 1)
            end
          end
          love.graphics.setColor(1, 1, 1, 1)
        end
      end

      local function drawFooter()
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.rectangle("fill", 0, UI_Y, W, H - UI_Y)
        love.graphics.setColor(0, 0, 0, 1)
        love.graphics.rectangle("fill", 0, UI_Y, W, 2)
        -- Match Angler's Cove's aquarium footer placement exactly.
        love.graphics.push()
        love.graphics.translate(0, -3)
        Chrome.print("START:MANAGE", 1, 16)
        love.graphics.pop()
        Chrome.print(habitat.lightsOn and "A:LIGHTSOFF" or "A:LIGHTON", 1, 17)
        Chrome.print("B:EXIT", 13, 17)
      end

      local function rowLabel(row)
        local mon = row and row.mon
        local species = tostring((mon and mon.species) or (row and row.species) or "?")
        if #species > 9 then species = species:sub(1, 9) end
        local level = (mon and mon.level) or (row and row.level) or 1
        return ("%s Lv%d"):format(species, tonumber(level) or 1)
      end

      local function plotCropLabel(plot)
        if not (plot and plot.item) then return "EMPTY" end
        local label
        if plot.item == FUNGI_SPORES then label = "FUNGI"
        elseif plot.item == BERRY_SEED then label = "SEED"
        else
          local def = game.data and game.data.items and game.data.items[plot.item]
          label = tostring((def and def.name) or plot.item):upper():gsub("_", " ")
          label = label:gsub(" BERRY", ""):gsub("BERRY", "")
          label = label:gsub("^%s+", ""):gsub("%s+$", "")
          if label == "" then label = "BERRY" end
        end
        if plot.fertilized then label = label .. "*" end
        if #label > 7 then label = label:sub(1, 7) end
        return label
      end

      local function drawListPanel(title, list, actionLabel)
        Chrome.box(1, 1, 18, 14)
        Chrome.print(title, 3, 2)
        local visibleRows = 4
        local firstVisible = 1
        if self.cursor > visibleRows then firstVisible = self.cursor - visibleRows + 1 end
        local maxFirst = math.max(1, #list - visibleRows + 1)
        if firstVisible > maxFirst then firstVisible = maxFirst end
        for slot = 1, math.min(visibleRows, #list) do
          local i = firstVisible + slot - 1
          local row = list[i]
          if self.cursor == i then Chrome.cursor(2, 4 + (slot - 1) * 2) end
          Chrome.print(rowLabel(row), 3, 4 + (slot - 1) * 2)
        end
        if firstVisible > 1 then Chrome.print("▲", 17, 3) end
        if firstVisible + visibleRows - 1 < #list then Chrome.print("▼", 17, 12) end
        Chrome.print("A:" .. actionLabel .. " B:BACK", 2, 13)
      end

      local function drawPlotSelectPanel(title, action)
        Chrome.box(2, 2, 16, 13)
        Chrome.print(title, 4, 3)
        syncVivariumPlots(game, habitat)
        for i = 1, 3 do
          local plot = habitat.plots[i]
          local y = 5 + (i - 1) * 2
          if self.cursor == i then Chrome.cursor(3, y) end
          local state = plotCropLabel(plot)
          Chrome.print(("PLOT %d"):format(i), 4, y)
          Chrome.print(state, 10, y)
        end
        Chrome.print("A:OK B:BACK", 4, 12)
      end

      local function drawBerryPanel()
        local rows = berryCandidates()
        Chrome.box(1, 1, 18, 15)
        Chrome.print("PLANT WHICH?", 4, 2)
        Chrome.print("PLOT " .. tostring(self.selectedPlot or 1), 7, 3)
        local visible = 4
        local first = math.max(1, math.min(self.cursor - 1, math.max(1, #rows - visible + 1)))
        for slot = 1, visible do
          local idx = first + slot - 1
          local row = rows[idx]
          if row then
            local y = 5 + (slot - 1) * 2
            if idx == self.cursor then Chrome.cursor(2, y) end
            local label = row.label
            if #label > 11 then label = label:sub(1, 11) end
            Chrome.print(label, 3, y)
            local qty = tonumber(row.qty) or 0
            local qtyText = qty > 99 and "x99+" or ("x" .. tostring(qty))
            Chrome.print(qtyText, 13, y)
          end
        end
        Chrome.print("A:PLANT B:BACK", 3, 14)
      end

      local function drawHarvestPanel()
        local rows = maturePlotRows()
        Chrome.box(2, 2, 16, 13)
        Chrome.print("HARVEST", 6, 3)
        for i, row in ipairs(rows) do
          if i <= 3 then
            local y = 5 + (i - 1) * 2
            if self.cursor == i then Chrome.cursor(3, y) end
            Chrome.print(("P%d %s"):format(row.plotIndex, plotCropLabel(row.plot)), 4, y)
          end
        end
        Chrome.print("A:TAKE B:BACK", 3, 12)
      end

      local function drawResidentInfoPanel()
        local specimen = habitat.residents[self.infoIndex or 1]
        Chrome.box(2, 2, 16, 13)
        Chrome.print("RESIDENT INFO", 4, 3)
        if specimen then
          local species = tostring(specimen.species or "POKEMON")
          if #species > 12 then species = species:sub(1, 12) end
          local level = tonumber((specimen.mon and specimen.mon.level) or specimen.level) or 1
          local role = vivariumRole(game, specimen.species)
          local roleText = role == "bug" and "BUG" or (role == "plant" and "PLANT" or "OTHER")
          local pref = role == "bug" and "DARK" or (role == "plant" and "LIGHT" or "EITHER")
          local watch = FIELD_NET_SPECIES[specimen.species]
          Chrome.print(species, 4, 5)
          local mon = specimen.mon
          local isPrime = ((mon and mon.vfrPrime) or specimen.vfrPrime) and true or false
          local isShiny = ((mon and mon.shiny) or specimen.shiny) and true or false
          local form = isPrime and "PRIME" or (isShiny and "SHINY" or "NORMAL")
          Chrome.print("LEVEL " .. tostring(level), 4, 7)
          Chrome.print("FORM " .. tostring(form), 4, 8)
          Chrome.print("ROLE " .. roleText, 4, 9)
          Chrome.print("LIKES " .. pref, 4, 10)
          if watch and watch.watchType then
            local wt = tostring(watch.watchType)
            if #wt > 8 then wt = wt:sub(1, 8) end
            Chrome.print("WATCH " .. wt, 4, 11)
          end
        end
        Chrome.print("A/B:BACK", 6, 12)
      end

      function self:draw()
        drawHabitat()
        if self.mode == "view" then
          drawFooter()
        elseif self.mode == "manage" then
          local options = manageOptions()
          Chrome.box(3, 0, 14, 18)
          Chrome.print("VIVARIUM", 6, 1)
          Chrome.print("RES " .. tostring(#habitat.residents) .. "/" .. tostring(habitat.capacity), 6, 3)
          Chrome.print("PARTY " .. tostring(#((game.save and game.save.party) or {})), 6, 4)
          local visibleRows = 6
          local first = 1
          if self.cursor > visibleRows then first = self.cursor - visibleRows + 1 end
          local maxFirst = math.max(1, #options - visibleRows + 1)
          if first > maxFirst then first = maxFirst end
          for slot = 1, math.min(visibleRows, #options) do
            local i = first + slot - 1
            local y = 6 + (slot - 1) * 2
            if self.cursor == i then Chrome.cursor(4, y) end
            Chrome.print(options[i].label, 5, y)
          end
          if first > 1 then Chrome.print("▲", 15, 5) end
          if first + visibleRows - 1 < #options then Chrome.print("▼", 15, 17) end
        elseif self.mode == "add" then
          drawListPanel("ADD WHICH?", addCandidates(), "ADD")
        elseif self.mode == "remove" then
          drawListPanel("REMOVE WHICH?", habitat.residents, "REMOVE")
        elseif self.mode == "info_select" then
          drawListPanel("VIEW WHICH?", habitat.residents, "VIEW")
        elseif self.mode == "info" then
          drawResidentInfoPanel()
        elseif self.mode == "plot_select" then
          drawPlotSelectPanel("CHOOSE PLOT", "SELECT")
        elseif self.mode == "berry" then
          drawBerryPanel()
        elseif self.mode == "fertilize" then
          drawPlotSelectPanel("FERTILIZE", "USE")
        elseif self.mode == "harvest" then
          drawHarvestPanel()
        elseif self.mode == "message" then
          Chrome.box(1, 5, 18, 7)
          Chrome.printWrapped(tostring(self.message or ""), 2, 6, 16, 4)
          Chrome.print("A/B", 9, 11)
        end
        love.graphics.setColor(1, 1, 1, 1)
      end

      return self
    end,
  })

  ---------------------------------------------------------------------------
  -- FIELD NET OVERWORLD SEARCH
  -- Using the FIELD NET scans nearby tall grass instead of immediately opening
  -- the capture screen. Successful scans leave up to three temporary shaking-
  -- grass clues. Walking INTO a rustling tile starts the catching minigame.
  ---------------------------------------------------------------------------
  local vfrGrassProfiles = {}

  local function vfrGrassProfile(targetMap)
    local ts = targetMap and targetMap.tileset
    if not ts then return { tiles = {}, sigs = {} } end
    if vfrGrassProfiles[ts] then return vfrGrassProfiles[ts] end
    local profile = { tiles = {}, sigs = {} }
    if ts.blocks and ts.collision then
      for blockIndex, block in ipairs(ts.blocks) do
        local coll = ts.collision[blockIndex]
        if block and coll then
          for cy = 0, 1 do
            for cx = 0, 1 do
              if Permissions.isGrass(coll[cy * 2 + cx + 1]) then
                local q = {}
                local tileX, tileY = cx * 2, cy * 2
                for yy = 0, 1 do
                  for xx = 0, 1 do
                    local tile = block[(tileY + yy) * 4 + (tileX + xx) + 1]
                    q[#q + 1] = tile
                    profile.tiles[tile] = true
                  end
                end
                profile.sigs[table.concat(q, ",")] = true
              end
            end
          end
        end
      end
    end
    vfrGrassProfiles[ts] = profile
    return profile
  end

  local function vfrVisualCellTiles(targetMap, cx, cy)
    if not (targetMap and targetMap.inBounds and targetMap:inBounds(cx, cy)
        and targetMap.tileAt) then return nil end
    local q = {}
    for yy = 0, 1 do
      for xx = 0, 1 do
        local tile = targetMap:tileAt(cx * 2 + xx, cy * 2 + yy)
        if tile == nil then return nil end
        q[#q + 1] = tile
      end
    end
    return q
  end

  local function vfrIsNetGrass(targetMap, cx, cy)
    if not (targetMap and targetMap.inBounds and targetMap:inBounds(cx, cy)) then
      return false
    end
    if targetMap.isGrassCell and targetMap:isGrassCell(cx, cy) then return true end
    local q = vfrVisualCellTiles(targetMap, cx, cy)
    if not q then return false end
    local profile = vfrGrassProfile(targetMap)
    if profile.sigs[table.concat(q, ",")] then return true end
    local score = 0
    for _, tile in ipairs(q) do
      if profile.tiles[tile] then score = score + 1 end
    end
    return score >= 2
  end

  local function vfrRustles(world)
    world.vfrFieldNetRustles = world.vfrFieldNetRustles or {}
    return world.vfrFieldNetRustles
  end

  local function vfrRustleAt(world, cx, cy)
    if not (world and world.map) then return nil, nil end
    local list = world.vfrFieldNetRustles or {}
    for i, r in ipairs(list) do
      if r.map == world.map.id and r.x == cx and r.y == cy and (r.ttl or 0) > 0 then
        return r, i
      end
    end
    return nil, nil
  end

  local function vfrRemoveRustle(world, index)
    local list = world and world.vfrFieldNetRustles
    if list and index then table.remove(list, index) end
  end

  ---------------------------------------------------------------------------
  -- HABITAT ENCOUNTER TABLES
  -- Percent-style weights total 100 within each base habitat. Time-of-day
  -- modifiers are applied afterward and re-normalized by weighted selection.
  -- The roster remains the same authoritative 29-species conservation list.
  ---------------------------------------------------------------------------
  local FIELD_NET_HABITATS = {
    meadow = {
      CATERPIE=12, WEEDLE=12, HOPPIP=11, BELLSPROUT=9, ODDISH=9,
      LEDYBA=6, SPINARAK=6, SUNKERN=7, PARAS=5, METAPOD=4, KAKUNA=4,
      VENONAT=4, YANMA=3, BUTTERFREE=2, BEEDRILL=2, LEDIAN=1,
      ARIADOS=1, SKIPLOOM=2,
    },
    dense = {
      CATERPIE=6, WEEDLE=6, PARAS=8, VENONAT=7, METAPOD=7, KAKUNA=7,
      ODDISH=4, BELLSPROUT=4, PINECO=6, EXEGGCUTE=6, BUTTERFREE=5,
      BEEDRILL=5, VENOMOTH=4, LEDIAN=4, ARIADOS=4, PARASECT=3,
      GLOOM=3, WEEPINBELL=3, SCYTHER=3, PINSIR=3, HERACROSS=2,
    },
    wetland = {
      HOPPIP=12, ODDISH=10, BELLSPROUT=9, PARAS=7, VENONAT=7, SUNKERN=7,
      YANMA=9, SKIPLOOM=8, TANGELA=7, PARASECT=5, BUTTERFREE=3,
      GLOOM=5, WEEPINBELL=5, LEDYBA=2, SPINARAK=2, HERACROSS=2,
    },
    rough = {
      PARAS=9, PINECO=11, VENONAT=7, BELLSPROUT=6, ODDISH=6, SHUCKLE=6,
      LEDYBA=4, SPINARAK=4, HOPPIP=4, TANGELA=7, HERACROSS=5, SCYTHER=4,
      PINSIR=4, YANMA=4, ARIADOS=5, PARASECT=5, WEEDLE=3, BEEDRILL=4,
      METAPOD=1, KAKUNA=1,
    },
    kanto = {
      CATERPIE=9, WEEDLE=9, HOPPIP=6, ODDISH=6, BELLSPROUT=6, VENONAT=6,
      PARAS=5, METAPOD=4, KAKUNA=4, EXEGGCUTE=5, TANGELA=4, SCYTHER=3,
      PINSIR=3, HERACROSS=3, SUNKERN=3, LEDYBA=3, SPINARAK=3,
      BUTTERFREE=4, BEEDRILL=4, PINECO=4, YANMA=3, SHUCKLE=3,
    },
  }

  local VFR_DENSE_MAPS = {
    ILEX_FOREST=true, NATIONAL_PARK=true, VIRIDIAN_FOREST=true,
  }
  local VFR_WETLAND_MAPS = {
    ROUTE_32=true, ROUTE_35=true, ROUTE_43=true, LAKE_OF_RAGE=true,
    ROUTE_44=true, ROUTE_12=true, ROUTE_13=true, ROUTE_14=true,
  }
  local VFR_ROUGH_MAPS = {
    ROUTE_3=true, ROUTE_4=true, ROUTE_9=true, ROUTE_10=true,
    ROUTE_27=true, ROUTE_28=true, ROUTE_33=true, ROUTE_42=true,
    ROUTE_45=true, ROUTE_46=true, MT_SILVER_OUTSIDE=true,
  }
  local VFR_KANTO_WOODLAND_MAPS = {
    ROUTE_1=true, ROUTE_2=true, ROUTE_5=true, ROUTE_6=true, ROUTE_7=true,
    ROUTE_8=true, ROUTE_11=true, ROUTE_15=true, ROUTE_16=true, ROUTE_17=true,
    ROUTE_18=true, ROUTE_22=true, ROUTE_24=true, ROUTE_25=true,
  }

  local function vfrHabitatForMap(mapId)
    mapId = tostring(mapId or "")
    if VFR_DENSE_MAPS[mapId] then return "dense" end
    if VFR_WETLAND_MAPS[mapId] then return "wetland" end
    if VFR_ROUGH_MAPS[mapId] then return "rough" end
    if VFR_KANTO_WOODLAND_MAPS[mapId] then return "kanto" end
    -- Any other grassy route uses the general meadow ecology.  The grass scan
    -- itself still prevents Field Net encounters on maps without tall grass.
    return "meadow"
  end

  local function vfrAuditConservationRoster()
    local pokemon = mod.game and mod.game.data and mod.game.data.pokemon or {}
    local count, issues = 0, 0
    for _, tierName in ipairs(DONATION_TIER_ORDER) do
      local tier = DONATION_TIERS[tierName]
      for _, species in ipairs(tier.species) do
        count = count + 1
        local habitatFound = false
        for _, weights in pairs(FIELD_NET_HABITATS) do
          if (tonumber(weights[species]) or 0) > 0 then habitatFound = true break end
        end
        if not pokemon[species] then
          issues = issues + 1
          mod.log:error("VFR DEV79 roster: missing Pokemon data for %s", species)
        end
        if not CONSERVATION_SPECIES[species] or not FIELD_NET_SPECIES[species] then
          issues = issues + 1
          mod.log:error("VFR DEV79 roster: missing Field Net config for %s", species)
        end
        if not habitatFound then
          issues = issues + 1
          mod.log:error("VFR DEV79 roster: %s has no habitat encounter weight", species)
        end
      end
    end
    if count ~= 29 then
      issues = issues + 1
      mod.log:error("VFR DEV79 roster: expected 29 species, found %d", count)
    end
    if issues == 0 then
      mod.log:info("VFR DEV79 roster audit: all 29 conservation species OK")
    end
  end

  vfrAuditConservationRoster()

  local function vfrTodMultiplier(species, tod)
    -- Time of day should guide hunting rather than hard-gate it.
    if tod == "NITE" then
      if species == "SPINARAK" or species == "ARIADOS" then return 1.50 end
      if species == "ODDISH" or species == "VENONAT" or species == "PARAS" then return 1.15 end
      if species == "LEDYBA" or species == "LEDIAN" then return 0.70 end
      if species == "BUTTERFREE" then return 0.75 end
    elseif tod == "MORN" then
      if species == "LEDYBA" or species == "LEDIAN" then return 1.50 end
      if species == "BUTTERFREE" then return 1.25 end
      if species == "SPINARAK" or species == "ARIADOS" then return 0.65 end
      if species == "YANMA" then return 1.15 end
    else -- DAY
      if species == "LEDYBA" or species == "LEDIAN" then return 1.25 end
      if species == "BUTTERFREE" then return 1.20 end
      if species == "SPINARAK" or species == "ARIADOS" then return 0.75 end
      if species == "YANMA" then return 1.10 end
    end
    return 1.0
  end

  local function vfrChooseSpecies(world)
    local habitat = vfrHabitatForMap(world and world.map and world.map.id)
    local weights = FIELD_NET_HABITATS[habitat] or FIELD_NET_HABITATS.meadow
    local tod = crystalDaytime(world and world.game or mod.game)
    local total = 0
    for species, weight in pairs(weights) do
      if FIELD_NET_SPECIES[species] then
        total = total + weight * vfrTodMultiplier(species, tod)
      end
    end
    if total <= 0 then
      local cfg = FIELD_NET_SPECIES.CATERPIE
      return "CATERPIE", cfg, math.random(cfg.levelMin or 3, cfg.levelMax or 7), habitat
    end

    local roll = love.math.random() * total
    local chosen = "CATERPIE"
    for species, weight in pairs(weights) do
      if FIELD_NET_SPECIES[species] then
        roll = roll - weight * vfrTodMultiplier(species, tod)
        if roll <= 0 then chosen = species break end
      end
    end
    local cfg = FIELD_NET_SPECIES[chosen] or FIELD_NET_SPECIES.CATERPIE
    return chosen, cfg, math.random(cfg.levelMin or 3, cfg.levelMax or 7), habitat
  end

  local function vfrCollectNearbyGrass(world, radius)
    local out = {}
    local player, map = world and world.player, world and world.map
    if not (player and map) then return out end
    radius = radius or 4
    for dy = -radius, radius do
      for dx = -radius, radius do
        local dist = math.abs(dx) + math.abs(dy)
        if dist > 0 and dist <= radius + 1 then
          local x, y = player.cellX + dx, player.cellY + dy
          if vfrIsNetGrass(map, x, y) then
            out[#out + 1] = { map = map.id, x = x, y = y }
          end
        end
      end
    end
    return out
  end

  local function vfrShuffle(list)
    for i = #list, 2, -1 do
      local j = math.random(i)
      list[i], list[j] = list[j], list[i]
    end
  end

  local function vfrRollShinyNet()
    -- The SHINY NET is an active alternative to the FIELD NET. Only scans
    -- started with the SHINY NET receive this 1-in-512 forced-shiny roll.
    return love.math.random(1, SHINY_NET_ODDS) == 1
  end

  local function queueFieldNet(world, shinyBoost)
    local player, map = world.player, world.map
    if not (player and map) then
      world.vfrFieldNetPending = { kind = "message",
        text = "FIELD NET won't\nwork here." }
      return
    end

    local grass = vfrCollectNearbyGrass(world, 4)
    if #grass == 0 then
      world.vfrFieldNetPending = { kind = "message",
        text = "No tall grass is\nnearby." }
      return
    end

    -- A new sweep replaces the previous clues instead of stacking endlessly.
    world.vfrFieldNetRustles = {}

    -- Normally one quarter of searches find nothing. SCENT SPRAY reduces that
    -- dry-roll chance to 5% for its duration without changing species rarity.
    local netState = vivariumRoot(world.game).fieldNet
    local scented = (tonumber(netState.scentSteps) or 0) > 0
    local noRustleChance = scented and 5 or 25
    local roll = math.random(100)
    if roll <= noRustleChance then
      world.vfrFieldNetPending = { kind = "message",
        text = "Nothing stirred\nnearby." }
      return
    end

    local countRoll = math.random(100)
    local wanted = countRoll <= 65 and 1 or (countRoll <= 92 and 2 or 3)
    wanted = math.min(wanted, #grass, 3)
    vfrShuffle(grass)

    local list = vfrRustles(world)
    local dev = vfrDevData(world.game.save)
    local forceScanShiny = dev.nextNetShiny == true
    dev.nextNetShiny = nil
    for i = 1, wanted do
      local cell = grass[i]
      local species, cfg, level, habitat = vfrChooseSpecies(world)
      list[#list + 1] = {
        map = cell.map, x = cell.x, y = cell.y,
        species = species, level = level,
        shiny = forceScanShiny or (shinyBoost and vfrRollShinyNet()) or false,
        style = cfg.rustleStyle or "calm", habitat = habitat,
        ttl = cfg.rustleDuration or 14.0,
        phase = love.math.random() * 2,
        shiftTimer = (cfg.rustleStyle == "jittery") and (2.2 + love.math.random() * 1.5) or nil,
      }
    end
    world.vfrFieldNetPending = { kind = "scan", count = #list }
  end

  local function vfrTickRustles(world, dt)
    local list = world and world.vfrFieldNetRustles
    local map = world and world.map
    if not (list and map) then return end
    dt = tonumber(dt) or (1 / 60)
    for i = #list, 1, -1 do
      local r = list[i]
      if r.map ~= map.id then
        table.remove(list, i)
      else
        r.ttl = (r.ttl or 0) - dt
        r.phase = (r.phase or 0) + dt
        if r.ttl <= 0 then
          table.remove(list, i)
        elseif r.style == "jittery" then
          r.shiftTimer = (r.shiftTimer or 2.5) - dt
          if r.shiftTimer <= 0 then
            local candidates = {
              { r.x + 1, r.y }, { r.x - 1, r.y },
              { r.x, r.y + 1 }, { r.x, r.y - 1 },
            }
            vfrShuffle(candidates)
            for _, c in ipairs(candidates) do
              local occupied = vfrRustleAt(world, c[1], c[2])
              if not occupied and vfrIsNetGrass(map, c[1], c[2]) then
                r.x, r.y = c[1], c[2]
                break
              end
            end
            r.shiftTimer = 2.2 + love.math.random() * 1.8
          end
        end
      end
    end
  end

  -- Draw the engine's own Crystal shaking-grass sprite over active clues. This
  -- uses the same camera/zoom path as the overworld, so the grass itself reads
  -- as rustling rather than as a detached UI marker.
  if not World.__vfrFieldNetRustleOverlay then
    World.__vfrFieldNetRustleOverlay = true
    local vanillaDrawGroundVfr = World.drawGround
    function World:drawGround(s)
      vanillaDrawGroundVfr(self, s)
      local list = self.vfrFieldNetRustles or {}
      if #list == 0 or not (self.camera and self.drawGrassShake) then return end
      local ox = math.floor(-(self.camera.x or 0) * s)
      local oy = math.floor(-(self.camera.y or 0) * s)
      for _, r in ipairs(list) do
        if self.map and r.map == self.map.id and (r.ttl or 0) > 0 then
          local visible = true
          if r.style == "still" then
            visible = ((r.phase or 0) % 1.5) < 0.45
          end
          if visible then
            local speed = r.style == "jittery" and 110 or (r.style == "still" and 28 or 62)
            local fake = {
              grassShake = true, moving = true,
              px = r.x * 16, py = r.y * 16,
              stepFrames = 16,
              progress = math.floor((r.phase or 0) * speed) % 16,
            }
            self:drawGrassShake(fake, ox, oy, s)
          end
        end
      end
    end
  end

  -- A rustling Field Net tile owns the landing. Suppress the ordinary grass
  -- encounter roll on that exact cell so walking into the clue always opens
  -- the net minigame rather than occasionally starting a vanilla wild battle.
  if not World.__vfrFieldNetRustleEncounterGuard then
    World.__vfrFieldNetRustleEncounterGuard = true
    local vanillaTryWildEncounterVfr = World.tryWildEncounter
    function World:tryWildEncounter(...)
      if self.player and vfrRustleAt(self, self.player.cellX, self.player.cellY) then
        return false
      end
      return vanillaTryWildEncounterVfr(self, ...)
    end
  end

  if not World.__vfrFieldNetRustleTick then
    World.__vfrFieldNetRustleTick = true
    local vanillaStepVfr = World.step
    function World:step(...)
      local result = vanillaStepVfr(self, ...)

      -- Consume SCENT SPRAY by landed overworld steps, not real-time frames.
      if self.stepFinished and self.game and self.game.save then
        local netState = vivariumRoot(self.game).fieldNet
        local left = tonumber(netState.scentSteps) or 0
        if left > 0 then netState.scentSteps = math.max(0, left - 1) end
      end

      -- DEV67: the player now investigates a clue simply by walking onto it.
      -- This runs only on the landing frame so standing on the cell cannot
      -- reopen the minigame after it has been consumed.
      if self.stepFinished and self.player and self.map
          and not self.battleActive and not self:busy() then
        local rustle, rustleIndex = vfrRustleAt(self, self.player.cellX, self.player.cellY)
        if rustle then
          vfrRemoveRustle(self, rustleIndex)
          pcall(function() Sound.playStereo(self.game.data, "Sfx_GrassRustle") end)
          Screens.push(self.game, CAPTURE_SCREEN, {
            world = self, species = rustle.species, level = rustle.level,
            shiny = rustle.shiny,
            map = rustle.map, x = rustle.x, y = rustle.y,
          })
        end
      end

      vfrTickRustles(self, 1 / 60)
      return result
    end
  end

  mod.events:on("map.entered", function()
    local world = mod.game and mod.game.world
    if world then world.vfrFieldNetRustles = {} end
  end)

  local function restoreOverworldAfterItemMenu(world)
    if not world then return end
    world.fade = nil
    world.fadeLevel = nil
    world.fadeWhiten = nil
    world.fadeHold = nil
    world.mapSetup = nil
  end

  local function dispatchFieldNet(world)
    local pending = world and world.vfrFieldNetPending
    if not pending then return end
    world.vfrFieldNetPending = nil
    restoreOverworldAfterItemMenu(world)
    if pending.kind == "capture" then
      pending.world = world
      Screens.push(world.game, CAPTURE_SCREEN, pending)
    elseif pending.kind == "scan" then
      pcall(function() Sound.playStereo(world.game.data, "Sfx_GrassRustle") end)
    else
      world:showText(pending.text or "Nothing happened.")
    end
  end

  local function useScentSpray(world)
    if not (world and world.game and world.game.save) then return "nowhere" end
    if world.battleActive or world:busy() then return "nowhere" end
    local netState = vivariumRoot(world.game).fieldNet
    if (tonumber(netState.scentSteps) or 0) > 0 then
      world.vfrScentSprayPending = "The scent is still\nstrong nearby."
      return "scent_active"
    end
    if (tonumber(world.game.save.inventory and world.game.save.inventory[SCENT_SPRAY]) or 0) < 1 then
      return "nowhere"
    end
    Bag.remove(world.game.save, SCENT_SPRAY, 1)
    netState.scentSteps = SCENT_SPRAY_STEPS
    world.vfrScentSprayPending = "The scent spread\nthrough the grass."
    pcall(function() Sound.play(world.game.data, "Sfx_Item") end)
    return "scent_spray"
  end

  local function dispatchScentSpray(world)
    local text = world and world.vfrScentSprayPending
    if not text then return end
    world.vfrScentSprayPending = nil
    restoreOverworldAfterItemMenu(world)
    world:showText(text)
  end

  if not World.__vfrDev22FieldNetUse then
    World.__vfrDev22FieldNetUse = true
    local vanillaUseFieldItem = World.useFieldItem
    function World:useFieldItem(itemId)
      if itemId == SCENT_SPRAY then
        return useScentSpray(self)
      end
      local usingShinyNet = itemId == SHINY_NET
      if itemId ~= FIELD_NET and not usingShinyNet then
        return vanillaUseFieldItem(self, itemId)
      end
      if self.battleActive or self:busy() then return "nowhere" end
      queueFieldNet(self, usingShinyNet)
      if self.usingItemWithSelect then dispatchFieldNet(self) end
      return usingShinyNet and "shiny_net" or "field_net"
    end

    local vanillaExitMenusFade = World.exitMenusFade
    function World:exitMenusFade(...)
      local hadNet = self.vfrFieldNetPending ~= nil
      local hadScent = self.vfrScentSprayPending ~= nil
      local result = vanillaExitMenusFade(self, ...)
      if hadNet then dispatchFieldNet(self) end
      if hadScent then dispatchScentSpray(self) end
      return result
    end
  end

  ---------------------------------------------------------------------------
  -- DEV60 TEST GRANT: give the existing Crystal SQUIRT BOTTLE once so the
  -- watering loop can be tested immediately. Remove this grant for release.
  ---------------------------------------------------------------------------
  mod.events:on("map.entered", function()
    local game = mod.game
    if not (game and game.save) then return end
    if mod.save:get("vfrDev54SquirtGranted") == true then return end
    local inv = game.save.inventory or {}
    if (tonumber(inv.SQUIRTBOTTLE) or 0) < 1 then
      Bag.add(game.save, "SQUIRTBOTTLE", 1, game.data)
    end
    mod.save:set("vfrDev54SquirtGranted", true)
  end)

  ---------------------------------------------------------------------------
  -- VIVARIUM INTRO SCENE
  -- First visit: JAXEN calls the player over, explains the Restoration Project,
  -- gives the FIELD NET, and points them toward FERN.  The fixed movement is
  -- exactly the requested four steps UP then two RIGHT from Kurt-house entry.
  ---------------------------------------------------------------------------
  mod.events:on("map.entered", function()
    local world = mod.game and mod.game.world
    if not (world and world.map and world.map.id == STATION and world.vm) then return end

    local introDone = mod.save:get("vfrVivariumIntroComplete") == true
    world.mapScenes[STATION] = introDone and 1 or 0

    local jaxen, fern
    for _, npc in pairs(world.npcPool or {}) do
      local role = npc and npc.def and npc.def.vfrRole
      if role == "jaxen" then jaxen = npc
      elseif role == "fern" then fern = npc end
    end

    -- Default room pose: the two researchers face each other.
    if jaxen then jaxen.facing = introDone and "left" or "right" end
    if fern then fern.facing = "left" end
    if introDone then return end

    local vm = world.vm
    local Opcodes = require("src.script.gen2.Opcodes")
    local MOD = Opcodes.MOD_COMMAND

    -- Four UP, two RIGHT, then movement terminator.
    vm.movements["VFR_WALK_TO_JAXEN"] = { 0x0d, 0x0d, 0x0d, 0x0d, 0x0f, 0x0f, 0x47 }

    local main = {
      { op = "rawtext", text = "JAXEN: HEY!\nOver here!" },
      { op = "applymovement", object = 0, movement = "VFR_WALK_TO_JAXEN" },
      { op = MOD, verb = "vfr:face_jaxen_left" },
      { op = "turnobject", object = 0, facing = 3 }, -- player faces right
      { op = "rawtext", text = "I'm JAXEN.\nI study BUGS." },
      { op = "rawtext", text = "FERN and I run\nthis VIVARIUM." },
      { op = "rawtext", text = "We help restore\nVIRIDIAN FOREST." },
      { op = "rawtext", text = "BUGS and plants\nneed protection." },
      { op = "rawtext", text = "Will you help\nour project?" },
      { op = "rawtext", text = "Take this NET.\nUse it near grass." },
      { op = MOD, verb = "vfr:give_field_net" },
      { op = "rawtext", text = "You got the\nFIELD NET!" },
      { op = "rawtext", text = "Grass may start\nto rustle." },
      { op = "rawtext", text = "Walk into the\nrustling patch." },
      { op = "rawtext", text = "Small BUG or\nplant PKMN hide." },
      { op = "rawtext", text = "BALL catches can\nhelp us too." },
      { op = "rawtext", text = "Keep some in the\nTERRARIUM." },
      { op = "rawtext", text = "Donate extras\nthrough LOGBOOK." },
      { op = "rawtext", text = "Species have\ndonation goals." },
      { op = "rawtext", text = "Goals unlock\nnew shop stock." },
      { op = "rawtext", text = "Use the LOGBOOK\nfor reminders." },
      { op = "rawtext", text = "Talk to FERN.\nShe grows plants." },
      { op = MOD, verb = "vfr:finish_intro" },
      { op = "end" },
    }

    world.scripts["VFR_VIVARIUM_INTRO_MAIN"] = main
    vm.scripts["VFR_VIVARIUM_INTRO_MAIN"] = main
  end)

  ---------------------------------------------------------------------------
  -- TILE DESIGNATOR DEV TOOL
  --
  -- Stand next to any tile and FACE it.  START -> VIV DEV lets you record the
  -- facing tile as SRC1, DST1, SRC2 or DST2.  The menu shows all four exact
  -- map/cell coordinates so the user can screenshot them for the next patch.
  ---------------------------------------------------------------------------
  local function devState(save)
    return vfrDevData(save)
  end

  local function facingTile(game)
    local world = game and game.world
    local player = world and world.player
    local map = world and world.map
    if not (player and map) then return nil end
    local d = Map.DELTA[player.facing]
    if not d then return nil end
    return {
      map = map.id or "?",
      x = player.cellX + d[1],
      y = player.cellY + d[2],
      facing = player.facing,
    }
  end

  local function shortMap(name)
    if name == "ROUTE_2" then return "R2" end
    return name or "?"
  end

  local SLOT_LABELS = {
    SRC1 = "SOURCE 1",
    DST1 = "DEST 1",
    SRC2 = "SOURCE 2",
    DST2 = "DEST 2",
  }
  local SLOT_ORDER = { "SRC1", "DST1", "SRC2", "DST2" }

  mod.content.screens:register(DEV_SCREEN, {
    new = function(game)
      local face = facingTile(game)
      local state = devState(game.save)
      local items = {}
      for _, key in ipairs(SLOT_ORDER) do
        local mark = state.marks[key]
        items[#items + 1] = {
          label = SLOT_LABELS[key],
          right = mark and ((mark.x or 0) .. "," .. (mark.y or 0)) or "--",
          sub = mark and shortMap(mark.map) or nil,
          value = key,
        }
      end
      items[#items + 1] = { label = "TIME +2H", value = "TIME2" }
      items[#items + 1] = { label = "TIME +8H", value = "TIME8" }
      items[#items + 1] = { label = "NEXT QUOTA", value = "QUOTA" }
      items[#items + 1] = { label = "UNLOCK COMMON", value = "TIER_COMMON" }
      items[#items + 1] = { label = "UNLOCK UNCOMMON", value = "TIER_UNCOMMON" }
      items[#items + 1] = { label = "UNLOCK RARE", value = "TIER_RARE" }
      items[#items + 1] = { label = "UNLOCK STOCK", value = "SHOP_ALL" }
      items[#items + 1] = { label = "GIVE VIV ITEMS", value = "GIVE_ITEMS" }
      items[#items + 1] = { label = "NEXT SPARK SHINY", value = "SPARK_SHINY" }
      items[#items + 1] = { label = "NEXT SPARK PRIME", value = "SPARK_PRIME" }
      items[#items + 1] = { label = "NEXT NET SHINY", value = "NET_SHINY" }
      items[#items + 1] = { label = "CLEAR ALL", value = "CLEAR" }

      local title = "VIV DEV"
      if face then title = ("FACE %d,%d"):format(face.x, face.y) end

      return mod.ui.ListMenu.new(game, title, items, {
        footer = face and ("Facing " .. shortMap(face.map) .. ". Pick a slot.")
                      or "Return to the overworld.",
        onChoose = function(item, menu)
          if item.value == "TIME2" then
            fastForwardVivariumTime(game, 2)
            menu:close()
            if game.stack and game.stack:top() then game.stack:pop() end
            local world = game.world
            if world then
              world:showText(("TIME +2 HOURS\nNOW %02d:%02d"):format(Clock.hour(game.save), Clock.minute(game.save)))
            end
            return
          end
          if item.value == "TIME8" then
            fastForwardVivariumTime(game, 8)
            menu:close()
            if game.stack and game.stack:top() then game.stack:pop() end
            local world = game.world
            if world then
              world:showText(("TIME +8 HOURS\nNOW %02d:%02d"):format(Clock.hour(game.save), Clock.minute(game.save)))
            end
            return
          end
          if item.value == "SHOP_ALL" then
            local root = vivariumRoot(game)
            local dp = syncDonationProgress(root)
            dp.devShopUnlockAll = true
            menu:close()
            if game.stack and game.stack:top() then game.stack:pop() end
            if game.world then game.world:showText("ALL SHOP STOCK\nUNLOCKED") end
            return
          end
          if item.value == "GIVE_ITEMS" then
            local grants = {
              { SCENT_SPRAY, 5 }, { FUNGI_SPORES, 5 }, { SPARKLE_BITS, 5 },
              { BERRY_SEED, 5 }, { FERTILIZER, 5 }, { SHINY_NET, 1 },
            }
            for _, g in ipairs(grants) do
              local have = tonumber((game.save.inventory or {})[g[1]]) or 0
              local want = (g[1] == SHINY_NET) and math.max(0, 1 - have) or g[2]
              if want > 0 then Bag.add(game.save, g[1], want, game.data) end
            end
            menu:close()
            if game.stack and game.stack:top() then game.stack:pop() end
            if game.world then game.world:showText("VIVARIUM ITEMS\nADDED TO PACK") end
            return
          end
          if item.value == "NET_SHINY" then
            local d = devState(game.save)
            d.nextNetShiny = true
            menu:close()
            if game.stack and game.stack:top() then game.stack:pop() end
            if game.world then game.world:showText("NEXT NET TARGET\nFORCES SHINY") end
            return
          end
          if item.value == "SPARK_SHINY" or item.value == "SPARK_PRIME" then
            local d = devState(game.save)
            d.nextSparkleResult = (item.value == "SPARK_PRIME") and "prime" or "shiny"
            menu:close()
            if game.stack and game.stack:top() then game.stack:pop() end
            if game.world then game.world:showText(item.value == "SPARK_PRIME" and "NEXT SPARKLE\nFORCES PRIME" or "NEXT SPARKLE\nFORCES SHINY") end
            return
          end
          if item.value == "TIER_COMMON" or item.value == "TIER_UNCOMMON" or item.value == "TIER_RARE" then
            local tierName = ({
              TIER_COMMON = "common",
              TIER_UNCOMMON = "uncommon",
              TIER_RARE = "rare",
            })[item.value]
            local root = vivariumRoot(game)
            local dp = syncDonationProgress(root)
            dp.devTierUnlocks = dp.devTierUnlocks or {}
            dp.devTierUnlocks[tierName] = true
            menu:close()
            if game.stack and game.stack:top() then game.stack:pop() end
            local world = game.world
            if world then
              world:showText((DONATION_TIERS[tierName].label or tierName:upper()) .. " TIER\nUNLOCKED")
            end
            return
          end
          if item.value == "QUOTA" then
            local root = vivariumRoot(game)
            local beforeCommon = completedCommonGoals(root)
            local pickedSpecies, pickedTier
            for _, tierName in ipairs(DONATION_TIER_ORDER) do
              local tier = DONATION_TIERS[tierName]
              if donationTierUnlocked(root, tierName) then
                for _, species in ipairs(tier.species) do
                  if (tonumber(root.donations[species]) or 0) < tier.goal then
                    pickedSpecies, pickedTier = species, tier
                    break
                  end
                end
              end
              if pickedSpecies then break end
            end
            if pickedSpecies then
              root.donations[pickedSpecies] = pickedTier.goal
              local dp = syncDonationProgress(root)
              local milestone
              if dp.commonCompleted > beforeCommon and dp.commonCompleted <= 6 then
                milestone = SHOP_MILESTONES[dp.commonCompleted]
              end
              menu:close()
              if game.stack and game.stack:top() then game.stack:pop() end
              local world = game.world
              if world then
                if milestone then
                  world:showText(pickedSpecies .. "\n" .. milestone.item)
                else
                  world:showText(pickedSpecies .. " QUOTA\nCOMPLETE")
                end
              end
            else
              menu:close()
              if game.stack and game.stack:top() then game.stack:pop() end
              local world = game.world
              if world then world:showText("ALL QUOTAS\nARE COMPLETE") end
            end
            return
          end
          if item.value == "CLEAR" then
            state.marks = {}
            menu:close()
            mod.ui.push(game, DEV_SCREEN)
            return
          end
          if not face then return end

          state.marks[item.value] = {
            map = face.map,
            x = face.x,
            y = face.y,
          }

          -- Close VIV DEV, then close the START menu underneath it so the
          -- player is immediately back on the map to line up the next tile.
          menu:close()
          if game.stack and game.stack:top() then game.stack:pop() end

          local world = game.world
          if world then
            world:showText(("%s MARKED\n%s %d,%d"):format(
              item.value, shortMap(face.map), face.x, face.y))
          end
        end,
      })
    end,
  })

  if not SummaryMenu.__vfrPrimeSymbol then
    SummaryMenu.__vfrPrimeSymbol = true
    local vanillaPageTile = SummaryMenu.pageTile
    function SummaryMenu:pageTile(id, tx, ty, colors)
      if id == 0x3f and self and self.mon and self.mon.vfrPrime then
        if drawPrimeSymbolAtTile(tx, ty) then return end
      end
      return vanillaPageTile(self, id, tx, ty, colors)
    end
  end

  if not PhotoStudio.__vfrPrimeSymbol then
    PhotoStudio.__vfrPrimeSymbol = true
    local vanillaDrawPanel = PhotoStudio.drawPanel
    function PhotoStudio:drawPanel(...)
      vanillaDrawPanel(self, ...)
      local mon = self and self.mon
      if mon and mon.shiny and mon.vfrPrime then
        drawPrimeSymbolAtTile(18, 2)
      end
    end
  end

  ---------------------------------------------------------------------------
  -- SIGN / NPC INTERACTION
  -- Field Net rustles are handled by walking onto the shaking grass; A-button
  -- interactions here are reserved for signs, the Logbook, JAXEN, and FERN.
  ---------------------------------------------------------------------------
  local function faceNpcToPlayer(player, npc)
    if not (player and npc) then return end
    local opposite = { up = "down", down = "up", left = "right", right = "left" }
    npc.facing = opposite[player.facing] or npc.facing
  end

  -- Chain normal Gen 2 textboxes. Every page waits for player input before the
  -- next page is opened, so FERN reads like vanilla NPC dialogue with no auto-scroll.
  local function showVanillaPages(world, pages, index, onDone)
    index = tonumber(index) or 1
    local page = pages and pages[index]
    if not page then
      if type(onDone) == "function" then onDone() end
      return
    end
    world:showText(page, function()
      if index < #pages then
        showVanillaPages(world, pages, index + 1, onDone)
      elseif type(onDone) == "function" then
        onDone()
      end
    end)
  end

  if not World.__vfrDev22Interactions then
    World.__vfrDev22Interactions = true
    local vanilla = World.interactBody
    function World:interactBody(...)
      if self.map and self.player and not self:busy() and not self.player.moving then
        local d = Map.DELTA[self.player.facing]
        if d then
          local fx, fy = self.player.cellX + d[1], self.player.cellY + d[2]
          if self.map.id == STATION then
            local npc = self:npcAtCell(fx, fy)
            local role = npc and npc.def and npc.def.vfrRole
            if role == "logbook" then
              mod.ui.push(self.game, LOGBOOK_SCREEN)
              return true
            elseif role == "jaxen" then
              faceNpcToPlayer(self.player, npc)
              if mod.save:get("vfrJaxenDonationIntro") ~= true then
                showVanillaPages(self, {
                  "Got extra PKMN?\nUse the LOGBOOK.",
                  "Each species has\na project quota.",
                  "COMMON goals:\n30 donations each.",
                  "Each quota adds\nnew shop stock.",
                  "Finish any six.\nHarder goals open.",
                }, 1, function()
                  mod.save:set("vfrJaxenDonationIntro", true)
                end)
              else
                local root = vivariumRoot(self.game)
                local dp = syncDonationProgress(root)
                local pendingReward = nextDonationReward(root)
                if pendingReward then
                  local title = donationRewardTitle(pendingReward)
                  local introPages
                  if pendingReward == RARE_CAPSTONE_KEY then
                    introPages = {
                      "JAXEN: Incredible!",
                      "Every RARE quota\nis complete.",
                    }
                  else
                    introPages = {
                      "JAXEN: Nice work!",
                      title .. " quota\nis complete.",
                    }
                  end
                  showVanillaPages(self, introPages, 1, function()
                    local ok, rewardPages = grantDonationReward(self.game, pendingReward)
                    showVanillaPages(self, rewardPages)
                  end)
                elseif shopUnlocked(root, "scentSpray") or shopUnlocked(root, "sparkleBits")
                    or shopUnlocked(root, "shinyNet") then
                  mod.ui.push(self.game, JAXEN_SHOP_SCREEN)
                else
                  showVanillaPages(self, {
                    "Use the LOGBOOK\nto donate PKMN.",
                    "Finish quotas to\nunlock my stock.",
                  })
                end
              end
              return true
            elseif role == "fern" then
              faceNpcToPlayer(self.player, npc)
              if mod.save:get("vfrFernIntroComplete") ~= true then
                local pages = {
                  "I'm FERN.\nI study plants.",
                  "The TERRARIUM has\nthree soil plots.",
                  "Plant a BERRY in\nan empty plot.",
                  "Plants take about\n24 hours to grow.",
                  "LIGHTS ON make\nplants grow fast.",
                  "Your SQUIRT BOTTLE\ncan water plots.",
                  "Watered soil grows\nplants faster.",
                  "Harvest a plant\nwhen it's mature.",
                  "Later we'll grow\nfungi too.",
                }
                showVanillaPages(self, pages, 1, function()
                  mod.save:set("vfrFernIntroComplete", true)
                end)
              else
                local root = vivariumRoot(self.game)
                if shopUnlocked(root, "fungiSpores") or shopUnlocked(root, "berrySeed")
                    or shopUnlocked(root, "fertilizer") then
                  mod.ui.push(self.game, FERN_SHOP_SCREEN)
                else
                  showVanillaPages(self, {
                    "LIGHTS ON help\nplants grow.",
                    "The SQUIRT BOTTLE\nwaters all plots.",
                  })
                end
              end
              return true
            elseif fx >= TERR_X and fx <= TERR_X + 3
                and fy >= TERR_Y and fy <= TERR_Y + 1 then
              Screens.push(self.game, VIVARIUM_SCREEN, { world = self })
              return true
            end
          end
          if self.map.id == ROUTE and fx == SIGN_X and fy == SIGN_Y then
            self:showText("VIRIDIAN VIVARIUM\nRestoration club")
            return true
          end
        end
      end
      return vanilla(self, ...)
    end
  end
end
