--- @since 26.1.22
-- Emit OSC 7 on every directory change so Ghostty (and other OSC-7 aware
-- terminals) track yazi's current working directory. New splits/tabs
-- created by the terminal then inherit the directory you are browsing,
-- instead of the directory where yazi was launched.

local M = {}
local subscribed = false

local function url_encode(path)
	return (path:gsub("([^%w%-%._~/])", function(c)
		return string.format("%%%02X", string.byte(c))
	end))
end

local function safe_tostring(value)
	local ok, str = pcall(function()
		return tostring(value)
	end)
	if ok and type(str) == "string" and str ~= "" then
		return str
	end
	return nil
end

local function safe_field(value, key)
	local ok, result = pcall(function()
		if value then
			return value[key]
		end
		return nil
	end)
	if ok then
		return result
	end
	return nil
end

-- URI scheme and host are both deliberate:
--
-- Scheme: `kitty-shell-cwd`. Ghostty's OSC 7 validator accepts only
-- `file` or `kitty-shell-cwd`; the latter is what Ghostty's own zsh
-- shell integration emits, and it is the well-trodden path.
--
-- Host: literal `localhost`. Ghostty validates that the hostname is
-- local by comparing against `gethostname(3)`, whose value on macOS
-- depends on scutil state and can differ from `hostname -s` in ways
-- that vary by machine. The validator special-cases `localhost` as
-- always-local, so using it makes the URI machine-agnostic.
local function emit(path)
	if not path or #path == 0 then
		return
	end
	local opened, tty = pcall(function()
		return io.open("/dev/tty", "w")
	end)
	if not opened then
		return
	end
	if not tty then
		return
	end
	local ok = pcall(function()
		tty:write("\27]7;kitty-shell-cwd://localhost" .. url_encode(path) .. "\7")
		tty:flush()
	end)
	pcall(function()
		tty:close()
	end)
	if not ok then
		return
	end
end

-- ps.sub callbacks run in async context where `cx` is not directly
-- accessible; ya.sync wraps a block so we can read the current cwd safely.
local get_cwd = ya.sync(function()
	local active = safe_field(cx, "active")
	local current = safe_field(active, "current")
	if not current then
		return nil
	end
	local cwd = safe_field(current, "cwd")
	if cwd then
		return safe_tostring(cwd)
	end
	return nil
end)

function M:setup()
	if subscribed then
		return
	end
	local ok = pcall(function()
		ps.sub("cd", function()
			emit(get_cwd())
		end)
	end)
	if ok then
		subscribed = true
	end
end

return M
