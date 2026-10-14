--!strict
-- Temporary boosts. Buying again extends the timer up to MaxDuration.
-- PriceScales: price is multiplied by the player's highest world multiplier.

export type Boost = {
	Id: string,
	Name: string,
	Stat: "Coins" | "Speed" | "Luck" | "All",
	Multiplier: number,
	Duration: number,
	MaxDuration: number,
	Price: number,
	Currency: string,
	ProductId: number?,
	PriceScales: boolean,
	Rarity: string,
	IconAssetId: number,
	Glyph: string,
	Order: number,
	NightOnly: boolean?,
	Description: string,
}

local Boosts = {}

Boosts.List = {
	{ Id = "boost_coins_2x", Name = "2x Coins", Stat = "Coins", Multiplier = 2, Duration = 15 * 60, MaxDuration = 3 * 3600, Price = 5_000, Currency = "Coins", PriceScales = true, Rarity = "Rare", IconAssetId = 0, Glyph = "💰", Order = 1, Description = "Double coins from selling for 15 minutes." },
	{ Id = "boost_speed", Name = "Turbo Suction", Stat = "Speed", Multiplier = 1.5, Duration = 10 * 60, MaxDuration = 2 * 3600, Price = 3_500, Currency = "Coins", PriceScales = true, Rarity = "Uncommon", IconAssetId = 0, Glyph = "⚡", Order = 2, Description = "+50% suction speed for 10 minutes." },
	{ Id = "boost_luck", Name = "Lucky Capsules", Stat = "Luck", Multiplier = 2, Duration = 15 * 60, MaxDuration = 2 * 3600, Price = 8_000, Currency = "Coins", PriceScales = true, Rarity = "Epic", IconAssetId = 0, Glyph = "🍀", Order = 3, Description = "Double chance for Epic+ pets for 15 minutes." },
	{ Id = "boost_mega", Name = "Mega Boost", Stat = "All", Multiplier = 2, Duration = 20 * 60, MaxDuration = 4 * 3600, Price = 99, Currency = "Robux", ProductId = 0, PriceScales = false, Rarity = "Legendary", IconAssetId = 0, Glyph = "🚀", Order = 4, Description = "2x coins, speed and luck for 20 minutes." },
	{ Id = "boost_night_owl", Name = "Night Owl", Stat = "Coins", Multiplier = 3, Duration = 10 * 60, MaxDuration = 3600, Price = 20_000, Currency = "Coins", PriceScales = true, Rarity = "Legendary", IconAssetId = 0, Glyph = "🦉", Order = 5, NightOnly = true, Description = "Night deal: 3x coins for 10 minutes." },
} :: { Boost }

Boosts.ById = {} :: { [string]: Boost }
for _, boost in Boosts.List do
	Boosts.ById[boost.Id] = boost
end

function Boosts.Get(id: string): Boost?
	return Boosts.ById[id]
end

-- Active multiplier for a stat given { [boostId]: expiresAt } and current unix time.
function Boosts.ActiveMultiplier(active: { [string]: number }?, stat: string, now: number): number
	local result = 1
	if not active then
		return result
	end
	for id, expiresAt in active do
		local boost = Boosts.ById[id]
		if boost and expiresAt > now and (boost.Stat == stat or boost.Stat == "All") then
			result *= boost.Multiplier
		end
	end
	return result
end

return Boosts
