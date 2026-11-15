--- File and directory pickers for Yazi with fzf: the files below the folder, or its folders, and the
--- hovered file or folder becomes the one that you chose.
---
--- It takes what fzf has for its own key bindings: the command and the options of Ctrl-T for the files
--- (`FZF_CTRL_T_COMMAND`, `FZF_CTRL_T_OPTS`), of Alt-C for the folders (`FZF_ALT_C_COMMAND`,
--- `FZF_ALT_C_OPTS`), and `FZF_DEFAULT_OPTS` for both, so Yazi looks as your shell does.
---
--- Keys, in keymap.toml:
---
---   { on = "z", run = "plugin finder file", desc = "Find a file" }
---   { on = "Z", run = "plugin finder dir",  desc = "Find a folder" }
---
--- Optional setup, in init.lua:
---
---   require("finder"):setup {
---     file = { command = "fd -t f", opts = "--preview 'bat {}'" },
---     dir = { command = "fd -t d" },
---     tmux = "auto",   -- "auto": a popup of tmux inside tmux, true, or false
---   }

local M = {}

-- the options of setup, kept for the code that runs async (see get_options): async code has a Lua
-- state of its own, where `setup` has not run
local get_options = ya.sync(function(state)
	return state.options or {}
end)

-- the folder that Yazi shows
local get_cwd = ya.sync(function()
	return tostring(cx.active.current.cwd)
end)

function M:setup(opts)
	self.options = opts or {}
end

local notify = function(level, content)
	ya.notify { title = "finder.yazi", content = content, timeout = 5, level = level }
end

-- `old` is replaced by `new` in `text`, where `old` is plain text and not a pattern
local replace = function(text, old, new)
	if old == "" then
		return text
	end
	local out, start = {}, 1
	while true do
		local from, to = string.find(text, old, start, true)
		if not from then
			out[#out + 1] = string.sub(text, start)
			break
		end
		out[#out + 1] = string.sub(text, start, from - 1)
		out[#out + 1] = new
		start = to + 1
	end
	return table.concat(out)
end

local has_command = function(name)
	local output = Command(name):arg("--version"):stdout(Command.PIPED):stderr(Command.PIPED):output()
	return output ~= nil
end

-- What each mode runs: the setup first, then the variables of fzf for its key bindings.
-- The files with no command anywhere are the ones that fzf finds itself.
local MODES = {
	file = { command = "FZF_CTRL_T_COMMAND", opts = "FZF_CTRL_T_OPTS" },
	dir = { command = "FZF_ALT_C_COMMAND", opts = "FZF_ALT_C_OPTS" },
}

local mode_command = function(mode, options)
	local given = options[mode] and options[mode].command
	if given and given ~= "" then
		return given
	end
	local env = os.getenv(MODES[mode].command)
	if env and env ~= "" then
		return env
	end
	if mode == "dir" then
		-- fzf lists files unless it is told otherwise
		return has_command("fd") and "fd -t d" or "find . -type d -not -path '*/.*'"
	end
	return nil
end

local mode_opts = function(mode, options, cwd)
	local parts = {}
	local default = os.getenv("FZF_DEFAULT_OPTS")
	if default and default ~= "" then
		parts[#parts + 1] = default
	end
	local given = options[mode] and options[mode].opts
	local env = os.getenv(MODES[mode].opts)
	local own = (given and given ~= "") and given or env
	if own and own ~= "" then
		parts[#parts + 1] = own
	end
	local text = table.concat(parts, " ")
	-- FZF_CWD is not an fzf variable: if you set it, the footers of your options that name that
	-- folder name the folder of Yazi
	local fzf_cwd = os.getenv("FZF_CWD")
	if fzf_cwd and fzf_cwd ~= "" then
		text = replace(text, fzf_cwd, cwd)
	end
	-- a popup of tmux is for tmux: outside of it, fzf draws on the screen of Yazi, which is hidden
	local tmux = options.tmux
	if tmux == nil or tmux == "auto" then
		tmux = os.getenv("TMUX") ~= nil
	end
	if tmux == true then
		text = text .. " --tmux"
	end
	return text, tmux == true
end

function M:entry(job)
	local mode = job.args[1]
	if not MODES[mode] then
		return notify("error", "Use `plugin finder file` or `plugin finder dir`")
	end
	if not has_command("fzf") then
		return notify("error", "`fzf` was not found")
	end

	local options = get_options()
	local cwd = get_cwd()
	local opts, popup = mode_opts(mode, options, cwd)

	-- the process runs in the folder, so the paths that it finds are relative to it and nothing of the
	-- folder is in a command line
	local command = Command("fzf")
		:cwd(cwd)
		:stdin(Command.INHERIT)
		:stdout(Command.PIPED)
		:stderr(Command.INHERIT)
		:env("FZF_DEFAULT_OPTS", opts)
	local given_command = mode_command(mode, options)
	if given_command then
		command = command:env("FZF_DEFAULT_COMMAND", given_command)
	end

	local permit = (not popup) and ui.hide() or nil
	local child, err = command:spawn()
	if not child then
		if permit then
			permit:drop()
		end
		return notify("error", string.format("Failed to start `fzf`: %s", err))
	end
	local output, err2 = child:wait_with_output()
	if permit then
		permit:drop()
	end

	if not output then
		return notify("error", string.format("Cannot read the output of `fzf`: %s", err2))
	elseif output.status.code == 130 then
		return -- cancelled
	elseif output.status.code == 1 then
		return notify("info", "No " .. mode .. " selected")
	elseif output.status.code ~= 0 then
		return notify("error", string.format("`fzf` exited with code %s", output.status.code))
	end

	local target = output.stdout:gsub("\n$", ""):match("[^\n]+")
	if target and target ~= "" then
		local url = Url(target)
		if not url.is_absolute then
			url = Url(cwd):join(url)
		end
		ya.emit("reveal", { url })
	end
end

return M
