local args = {...}
local version = "0.3"
local name = "CraftNix Kernel"
local output = {
	debug = function(...)
		if not quietBoot then
			print("[DEBUG]",...)
		end
	end,
	info = function(...)
		print("[INFO]",...)
	end,
	warn = function(...)
		local oldPrintColor
		if term.isColor() then
			oldPrintColor = term.getTextColor()
			term.setTextColor(colors.yellow)
		end
		print("[WARNING]",...)
		if term.isColor() then
			term.setTextColor(oldPrintColor)
		end
	end,
	error = function(...)
		printError("[ERROR]",...)
	end,
}

local argsStr = ""
local quietBoot = false
for i,v in pairs(args) do
	if i ~= 1 then
		argsStr = argsStr.." "
	end
	argsStr = argsStr..v
	if v == "quiet" then
		quietBoot = true
	end
end
output.info(name.." version "..version)
output.info("Command line: "..argsStr)
local hostname = ""
local rootColor = colors.red
local userColor = colors.green

-- by default everything is root, not great but unless we make FS protection it doesn't matter
-- since this is CC we don't really need to make user protection and don't need to figure out multi user at this moment
-- we may in the future but you can't really run things in the background so eh
local isRoot = true
local userAccount = "root" 

---prevent tampering
local oldGlobal = _G
local oldset = rawset

local newGlobal = setmetatable({},{
	__index = oldGlobal,
	__newindex = function(table, index, value)
		return
	end,
	__metatable = {}
})
_G = newGlobal

-- this figures out where the hell we are
local parentDir = debug.getinfo(1).source:match("@?(.*/)") --https://stackoverflow.com/a/35072122 (getting current file location)
-- basically we need to be able to make portable disks for a possible future installer
-- the current init system won't support that since its meant for specialized applications
-- not generic desktop usage since that would never be used

function resolvePath(path)
	local matches = {}
	for i in path:gmatch("[^/]+") do
		table.insert(matches,i)
	end
	local result1 = {}
	local lastIndex = 1
	for i,v in pairs(matches) do
		if v ~= "." then
			if v== ".." then
				result1[lastIndex] = nil
				lastIndex = lastIndex-1
			else
				lastIndex = lastIndex + 1
				result1[lastIndex] = v
			end
		end
	end
	local result = {}
	for i,v in pairs(result1) do
		table.insert(result,v)
	end
	local final = "/"
	for i,v in pairs(result) do
		if i ~= 1 then
			final = final .. "/"
		end
		final = final..v
	end
	return final
end
local accounts = { -- incase it goes wrong somehow
	root = "5e884898da28047151d0e56f8dc6292773603d0d6aabbdd62a11ef721d1542d8", --password, literally
}
local function loadfrompasswd()
    if not fs.exists("/etc/passwd") then
	output.warn("/etc/passwd does not exist, creating.")
    	local file = fs.open("/etc/passwd", "w")
    	file.writeLine("root:5e884898da28047151d0e56f8dc6292773603d0d6aabbdd62a11ef721d1542d8") -- default
    	file.close()
        return false, "/etc/passwd does not exist"
    end

    local seen = {}
    local file = fs.open("/etc/passwd", "r")
    while true do
        local line = file.readLine()
        if line == nil then break end

        local username, password = line:match("([^:]+):([^:]+)")
        if username and password then
            if not seen[username] then
                accounts[username] = password
                seen[username] = true
            else
                output.warn("Duplicate account for user: " .. username .. "with hashed password: " .. password ..", ignoring.")
            end
        end
    end
    file.close()
    return true
end
--local function savetopasswd()
--    local file = fs.open("/etc/passwd", "w")
--    for username, password in pairs(accounts) do
--        file.writeLine(username .. ":" .. password)
--    end
--    file.close()
--end -- only use this as a example on how to write to /etc/passwd
local success, err = loadfrompasswd() -- the accounts table is also the one in passwd by default so if the file exists but is unchanged its still the same table, if the passwd file doesnt exist then its still the default table
local directory = "/"
local user = {
	login = function(name, password)
		-- i don't want to have to deal with the kernel needing an SHA256 library
		-- the login system handles hashing it (i dont want to)
		if accounts[name] and accounts[name] == password then
			if not fs.exists("/home/"..name) then
				fs.makeDir("/home/"..name)
			end
			if (name:match("^[a-zA-Z0-9_]+$")) then
				userAccount = name
			else
				return false
			end
			isRoot = (userAccount == "root")
			return true
		else
			return false
		end
	end,
	createUser = function(name, password)
		-- the program that runs createUser handles hashing
		if isRoot then
			if not fs.exists("/home/"..name) then
				fs.makeDir("/home/"..name)
			end
			if (name:match("^[a-zA-Z0-9_]+$")) then
				accounts[name] = password
				local file = fs.open("/etc/passwd", "a")
				file.writeLine(name .. ":" .. password)
				file.close()
			else
				return false
			end
			return true
		else 
			return false
		end
	end,
	chkRoot = function() return isRoot end,
	home = function()
		return "/home/"..userAccount.."/"
	end,
	currentUser = function()
		return userAccount or "root"
	end,
	currentUserColor = function()
		return isRoot and rootColor or userColor
	end,
}
oldGlobal.output = output
oldGlobal.user = user
function oldGlobal.fs.setDir(dir)
	directory = dir
end
function oldGlobal.fs.getDir()
	return directory
end
function oldGlobal.fs.getBootedDrive()
	local drive = resolvePath(parentDir.."..").."/"
	if drive == "//" then
		drive = "/"
	end
	return drive
end
oldGlobal.fs.resolvePath = resolvePath
function oldGlobal.fs.updateFile(file,url)
	local result, reason = http.get({url = url, binary = true}) --make names better
	if not result then
		output.warn(("Failed to update %s from %s (%s)"):format(file, url, reason)) --include more detail
		return
	end
	local a1 = fs.open(file,"wb")
	a1.write(result.readAll())
	a1.close()
	result.close()
end
function oldGlobal.fs.isProgramInPath(path,progName)
	if fs.exists(path..progName) then
		return path..progName
	elseif fs.exists(path..progName..".lua") then
		return path..progName..".lua"
	elseif fs.exists(path..progName..".why") then
		return path..progName..".why"
	else
		return false
	end
end
function oldGlobal.rawset(tab,...)
	if tab ~= _G then
		return oldset(tab,...)
	end
end
function oldGlobal.term.fixColorScheme()
	for i=0,15 do
		local color = 2^i
		term.setPaletteColor(color,term.nativePaletteColor(color))
	end
	term.setBackgroundColor(colors.black)
	term.setTextColor(colors.white)
end
local oldRun = os.run
function oldGlobal.os.run(env,file,...)
	--resolving this here since its required for files to work
	local a = fs.open(file,"r")
	if a then
		local firstLine = a.readLine(false)
		a.close()
		if firstLine:sub(1,2) == "#!" then
			local interpreter = firstLine:sub(3)
			if fs.isProgramInPath("",interpreter) then
				interpreter = fs.isProgramInPath("",interpreter)
			end
			oldRun(env,interpreter,file,...)
		else
			oldRun(env,file,...)
		end
	else
		output.info(file)
	end
end
function oldGlobal.os.version()
	return name.." v"..version
end
function oldGlobal.os.hostname()
	return hostname
end
local function makeDir(dir)
	if not fs.exists(fs.getBootedDrive()..dir) then
		fs.makeDir(fs.getBootedDrive()..dir)
	end
end

term.fixColorScheme()
makeDir("/etc")
makeDir("/usr")
makeDir("/lib")
makeDir("/usr/bin")
makeDir("/usr/lib")
makeDir("/usr/bin")
makeDir("/usr/etc")
if not fs.exists(fs.getBootedDrive().."/etc/hostname") then
	output.info("Host name not set!")
	term.write("Please enter a hostname: ")
	local file = fs.open(fs.getBootedDrive().."/etc/hostname","w")
	while true do
		local a = read()
		if a ~= "" then
			file.write(a)
			break
		end
	end
	file.close()
end
oldGlobal.rednet = setmetatable({},{
	__metatable = {},
	__index = function(...)
		output.error("Rednet is unsupported")
		return function(...) end
	end,
})
local file = fs.open(fs.getBootedDrive().."/etc/hostname", "r")
hostname = file.readAll()
file.close()
os.run({},fs.isProgramInPath(fs.getBootedDrive().."sbin/","init"))
