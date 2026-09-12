dofile("HeadlessWrapper.lua")
local t0 = os.clock()
newBuild()
local function equip(raw)
	build.itemsTab:CreateDisplayItemFromRaw(raw); build.itemsTab:AddDisplayItem()
end
equip("Rarity: RARE\nDread Shroud\nElementalist Robe\n--------\nEnergy Shield: 116\n--------\n+95 to maximum Life")
equip("Rarity: RARE\nStorm Bite\nAttuned Wand\n--------\nSpell Damage: 40%\n--------\n+30 to Intelligence")
build.skillsTab:PasteSocketGroup("Spark 20/0  1")
build.mainSocketGroup = 1
build.buildFlag = true
runCallback("OnFrame")
local tSetup = os.clock()

-- cost of obtaining a calculator (full base pass)
local c0 = os.clock()
local calcFunc, calcBase = build.calcsTab:GetMiscCalculator()
local tCalcGet = os.clock() - c0

-- cost per candidate item, reusing the same calculator
local raw = "Rarity: RARE\nLoath Veil\nElementalist Robe\n--------\nEnergy Shield: 180\n--------\n+150 to maximum Life\n30% increased Spell Damage"
local N = 20
local p0 = os.clock()
for i = 1, N do
	local item = new("Item"):Item(raw)
	local slotName = build.itemsTab:GetComparisonSlotNameForItem(item)
	local _ = calcFunc({ repSlotName = slotName, repItem = item })
end
local perItem = (os.clock() - p0) / N

print(("\n--- timings ---"))
print(("build setup (incl. boot): %.0f ms"):format((tSetup - t0) * 1000))
print(("GetMiscCalculator()     : %.0f ms"):format(tCalcGet * 1000))
print(("per candidate item      : %.1f ms  (avg of %d)"):format(perItem * 1000, N))
