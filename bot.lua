local irc   = require 'irc'
local sleep = require 'socket'.sleep

math.randomseed(os.time())

local args = arg

local flag_i = 1
if args[1]:sub(1, 1) ~= '-' then
    flag_i = 0
end

local flags = {}
if flag_i > 0 then
    for i=2, #args[1] do
        local char  = args[1]:sub(i, i)
        flags[char] = true
    end
end

local nick     = args[flag_i+1]
local password = args[flag_i+2]

local channels = {}
for i=flag_i+3, #args do
    table.insert(channels, args[i])
end

if flags.d then
    for k, v in pairs(flags) do
        print('flag: '..k)
    end

    print('[DEBUG] nick: '..nick)
    print('[DEBUG] pass: '..password)

    for _, v in ipairs(channels) do
        print('[DEBUG] channel: '..v)
    end
end

local stack = {}

function stack.push(t, object)
    t[#t+1] = object

    if flags.d then
        for i, v in ipairs(t) do
            print('\n[DEBUG] -- pushing data onto stack --')
            print('[DEBUG] ['..i..'] user: '..v.user..' msg: '..v.msg)
            print('[DEBUG] -- done --\n')
        end
    end
end

function stack.pop(t)
    local ret = t[#t]
    t[#t]     = nil
    return ret
end

function stack.inspect(t)
    if flags.d then
        print('\n[DEBUG] -- inspecting top of stack --')
        print('[DEBUG] user: '..t[#t].user)
        print('[DEBUG] msg: '..t[#t].msg)
        print('[DEBUG] -- done --\n')
    end

    return t[#t]
end

function stack.depth(t)
    return #t
end

local function choice(t)
    local n = math.random(1, #t)
    return t[n]
end

--returns true if all table values are equal
local function check_values(t)
    local bool = true
    if #t > 1 then
        for i=1, #t-1 do
            bool = t[i] == t[i+1]
            if not bool then
                break
            end
        end
    end
    return bool
end

--if check_values is true, will return true if tables contain same values
local function check_equality(t1, t2)
    return t1[1] == t2[1]
end 

local function catch_pyramid(bot, user, channel, message)
    if flags.d then
        print('[DEBUG] user.nick: '..user.nick)
        print('[DEBUG] channel: '..channel)
        print('[DEBUG] message: '..message)
    end

    if stack.depth(bot.stacks[channel]) == 0 then
        stack.push (
            bot.stacks[channel],
            {
                user = user.nick,
                msg  = message
            }
        )
    elseif stack.inspect(bot.stacks[channel]).user == user.nick then
        if flags.d then
            print('[DEBUG] depth: '..stack.depth(bot.stacks[channel]))
        end

        local last_msg         = stack.pop(bot.stacks[channel]).msg
        local last_occurrences = 0
        local last_emotes      = {}

        for str in string.gmatch(last_msg, '(%S+)%s*') do
            last_emotes[#last_emotes+1] = str
            last_occurrences            = last_occurrences + 1
        end

        local this_msg         = message
        local this_occurrences = 0
        local this_emotes      = {}

        for str in string.gmatch(this_msg, '(%S+)%s*') do
            this_emotes[#this_emotes+1] = str
            this_occurrences            = this_occurrences + 1
        end

        if flags.d then
            print('[DEBUG] last emotes:')
            for i, v in ipairs(last_emotes) do
                print(v)
            end

            print('[DEBUG] this emotes:')
            for i, v in ipairs(this_emotes) do
                print(v)
            end
        end

        if check_values(last_emotes) and check_values(this_emotes) then
            if check_equality(last_emotes, this_emotes) then
                if (
                       (this_occurrences - last_occurrences == 1)
                    or (this_occurrences - last_occurrences == -1)
                ) then
                    if flags.d then
                        print('\n[DEBUG] interrupting\n')
                    end

                    local num = math.random(1000, 9999)
                    bot.sock:sendChat (
                        channel,
                        'No. OMGScoots ['..num..']'
                    )
                    print('Interrupted '..user.nick..' in '..channel)
                end
            end
        end
    else
        stack.pop(bot.stacks[channel])
    end
end

local bot = {}

function bot.init(self)
    self.sock = irc.new {
        nick     = nick,
        username = nick,
        realname = nick
    }

    self.host = {
        host     = 'irc.twitch.tv',
        port     = 6667,
        password = password
    }

    self.sock:hook('PreRegister',    self.handle_prereg)
    self.sock:hook('OnNotice',         self.handle_notice)
    self.sock:hook('OnChat',         self.handle_message)
    self.sock:hook('OnSend',         self.handle_send)
    self.sock:hook('OnModeChange',  self.handle_mode_change)
    self.sock:hook('OnKick',        self.handle_kick)
    if flags.r then
        self.sock:hook('OnRaw',     self.handle_raw)
    end

    self.stacks = {}
    for _, channel in ipairs(channels) do
        self.stacks[channel] = {}
    end

    self.triggers = {}
    self.triggers['!combobreaker'] = self.send_info
end

function bot.run(self)
    self.sock:connect(self.host)
    
    for _, channel in ipairs(channels) do
        self.sock:join(channel)
    end

    while true do
        self.sock:think()
        sleep(0.1)
    end
end

function bot.handle_prereg(connection)
    if connection then
        print (
            ('[username: %s] [nick: %s]'):format (
                connection.username, connection.nick
            )
        )
    else
        print('failed to connect, check nick/password')
        os.exit()
    end
end

function bot.handle_notice(user, channel, message)
    print (
        ('[%s] NOTICE %s: %s'):format (
            channel, user.nick, message
        )
    )
end

function bot.handle_raw(line)
    print (('<-- [RAW] %s'):format(line))
end

function bot.handle_message(user, channel, message)
    if flags.m then
        print (
            ('%s: MSG [%s]: %s'):format (
                channel, user.nick, message
            )
        )
    end

    if bot.triggers[message] then
        bot.triggers[message](channel)
    end

    local pm = string.find(message:lower(), '@*'..nick:lower())
    if pm then
        print('\n<-- '..user.nick..' PMed us: '..message..' in '..channel..'\n')
        local num = math.random(1000, 9999)
        bot.sock:sendChat (
            channel,
            '@'..user.nick..' Relayed to my master. Kappa '..'['..num..']'
        )
    end

    catch_pyramid(bot, user, channel, message)
end

function bot.handle_send(line)
    print('--> '..line)
end

function bot.handle_mode_change(user, target, modes, ...)
    if user.nick == nick then
        print('<-- Someone changed our mode in '..target)
    end
end

function bot.handle_kick(channel, user, kicker, reason)
    if user.nick == nick then
        print (
            kicker.nick..' kicked us from '..channel
        )
    end
end

function bot.send_info(channel)
    bot.sock:sendChat (
        channel,
        'I was created by the_SaltySpitoon. ['..math.random(1000, 9999)..']'
    )
end

bot:init()
bot:run()