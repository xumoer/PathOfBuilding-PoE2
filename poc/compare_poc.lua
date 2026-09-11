-- Proof of concept: headless "is this item an upgrade?" comparison.
-- Run from src/:  luajit ../poc/compare_poc.lua
dofile("HeadlessWrapper.lua")

local function equip(raw)
	build.itemsTab:CreateDisplayItemFromRaw(raw)
	build.itemsTab:AddDisplayItem()   -- no arg => auto-equip into first valid empty slot
end

newBuild()

-- A minimal geared character so the calculations have something to chew on
equip([[Rarity: RARE
Dread Shroud
Elementalist Robe
--------
Energy Shield: 116
--------
+95 to maximum Life
+40 to maximum Energy Shield
+25% to Fire Resistance]])

equip([[Rarity: RARE
Storm Bite
Attuned Wand
--------
Spell Damage: 40%
--------
+30 to Intelligence
25% increased Spell Damage]])

build.skillsTab:PasteSocketGroup("Spark 20/0  1")
build.mainSocketGroup = 1
build.buildFlag = true
runCallback("OnFrame")

-- ---------------------------------------------------------------------------
-- The actual comparison primitive
-- ---------------------------------------------------------------------------
local function compareItem(raw)
	local item = new("Item"):Item(raw)
	if not item.base then return nil, "could not parse item" end

	local slotName = build.itemsTab:GetComparisonSlotNameForItem(item)
	local calcFunc, calcBase = build.calcsTab:GetMiscCalculator()
	local output = calcFunc({ repSlotName = slotName, repItem = item })

	local slot = build.itemsTab.slots[slotName]
	local replacing = slot and build.itemsTab.items[slot.selItemId]

	local diffs = {}
	for _, statData in ipairs(build.displayStats) do
		local stat = statData.stat
		if stat and not statData.childStat then
			local base, new_ = calcBase[stat], output[stat]
			if type(base) == "number" and type(new_) == "number" and math.abs(new_ - base) > 0.001 then
				table.insert(diffs, {
					stat  = stat,
					label = statData.label or stat,
					before = base,
					after = new_,
					delta = new_ - base,
					pct   = base ~= 0 and ((new_ - base) / math.abs(base) * 100) or nil,
				})
			end
		end
	end
	return { slot = slotName, replacing = replacing and replacing.name or "(empty)", diffs = diffs }
end

-- ---------------------------------------------------------------------------
local candidate = [[Rarity: RARE
Loath Veil
Elementalist Robe
--------
Energy Shield: 180
--------
+150 to maximum Life
+90 to maximum Energy Shield
+35% to Fire Resistance
30% increased Spell Damage]]

local result, err = compareItem(candidate)
if not result then print("ERROR: " .. err) return end

print(("\n=== Candidate would go in: %s (replacing %s) ==="):format(result.slot, result.replacing))
for _, d in ipairs(result.diffs) do
	print(("  %-34s %12.2f -> %12.2f   %+.2f%s"):format(
		d.label, d.before, d.after, d.delta,
		d.pct and (" (%+.1f%%)"):format(d.pct) or ""))
end
print(("\n%d stats changed"):format(#result.diffs))
