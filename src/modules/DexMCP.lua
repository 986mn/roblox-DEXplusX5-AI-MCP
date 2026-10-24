--[[
	DexMCP Module

	Bridges DEX PlusPlusPlusPlus to an MCP server (AI agent).
	Exposes a read/write API on getgenv().DEX so an external MCP server
	can query the DEX selection, read properties, decompile scripts,
	execute Luau, and drive the DEX UI.

	This module follows the standard DEX++ module contract:
		return {InitDeps = ..., InitAfterMain = ..., Main = ...}
	and is registered in Main.ModuleList as "DexMCP".

	API cheat sheet (from any executor console):
		local D = getgenv().DEX
		D.Snapshot()                          -- current selection + meta
		D.Select({"game.Workspace.NPC"})      -- select (UI jumps to it)
		D.Tree("game.Workspace", 3, 200)      -- instance tree
		D.Props("game.Workspace.NPC")         -- properties/attributes/tags
		D.Source("game.ReplicatedStorage.X")  -- decompile (6 modes)
		D.SetProp(path, "Health", "0")        -- write
		D.Run("return 1+1")                   -- execute
		D.App("Explorer", true)               -- toggle a panel
		D.OpenScript(path, "Executor")        -- open in Notepad tab
		getgenv().DEX_QUEUE.Take()            -- queue handoff
]]

<<<BODY>>>
