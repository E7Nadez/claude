--!strict
-- Bosses only matter to the shop as unlock conditions and core currencies.

export type Boss = {
	Id: string,
	Name: string,
	World: string,
	Core: string,
}

local Bosses = {
	TrashKing = {
		Id = "TrashKing",
		Name = "Trash King",
		World = "Cleanville",
		Core = "TrashKingCore",
	},
	RustDragon = {
		Id = "RustDragon",
		Name = "Rust Dragon",
		World = "Dustlands",
		Core = "RustDragonCore",
	},
} :: { [string]: Boss }

return Bosses
