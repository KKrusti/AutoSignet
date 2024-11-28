_addon.name = 'AutoSignet'
_addon.author = 'Kkrusti'
_addon.version = '1.0.1'
_addon.commands = {'autoSignet','as'}

require('logger')
require('tables')
require('pack')
packets = require('packets')
extdata = require('extdata')
res_slots = require('resources').slots
res_zones = require('resources').zones
send_command = windower.send_command

signet_staffs = T{'Rep. Signet Staff','Fed. Signet Staff','Kgd. Signet Staff'}

idle_staff = false

-- set your preferences here
function init()
    override = 'no' -- 'no','xp','bo'
    cycle_time = 4
    use_in_town = 'no' -- 'no', 'yes'
    start:schedule(8)
end

-------------------------------------------------------------------------------
----------------- Do not touch anything below this point, ok? -----------------
-------------------------------------------------------------------------------

lang = string.lower(windower.ffxi.get_info().language)
active = false
busy = false
moving = false

buff_id = {
    ['Signet'] = 253,
}

-- Having this here makes the addon use less ram than using the resources lib... maybe.

item_resources = T{
    [17583] = {id=17583,en="Kgd. Signet Staff",ja="王国儀仗",enl="Kingdom Signet staff",jal="王国儀仗",cast_delay=30,cast_time=1,category="Weapon",damage=1,delay=366,flags=3136,jobs=8388606,level=1,max_charges=25,races=510,recast_delay=10,skill=12,slots=1,stack=1,targets=29,type=4},
    [17584] = {id=17584,en="Rep. Signet Staff",ja="共和国儀仗",enl="Republic Signet staff",jal="共和国儀仗",cast_delay=30,cast_time=1,category="Weapon",damage=1,delay=366,flags=3136,jobs=8388606,level=1,max_charges=25,races=510,recast_delay=10,skill=12,slots=1,stack=1,targets=29,type=4},
    [17585] = {id=17585,en="Fed. Signet Staff",ja="連邦儀仗",enl="Federation Signet staff",jal="連邦儀仗",cast_delay=30,cast_time=1,category="Weapon",damage=1,delay=366,flags=3136,jobs=8388606,level=1,max_charges=25,races=510,recast_delay=10,skill=12,slots=1,stack=1,targets=29,type=4},
}

function get_item_info(items)
    local results = T{}
    for i,v in ipairs(items) do
        local item = item_resources:with('en', v)
        if item and item.id > 0 then
            results[i] = {
                ['id'] = item.id,
                ['slot'] = 0,
                ['english'] = '"'..item.en..'"',
                ['japanese'] = item.ja,
            }
        end
    end
    return results
end

signet_staffs_info = get_item_info(signet_staffs)

-- returns current zone
local function get_zone()
    return res_zones[windower.ffxi.get_info().zone].en
end

-- returns true if current zone is a city or town.
local in_town = function()
	local Cities = S{
            "Northern San d'Oria", "Southern San d'Oria", "Port San d'Oria", "Chateau d'Oraguille",
            "Bastok Markets", "Bastok Mines", "Port Bastok", "Metalworks",
            "Windurst Walls", "Windurst Waters", "Windurst Woods", "Port Windurst", "Heavens Tower",
            "Ru'Lude Gardens", "Upper Jeuno", "Lower Jeuno", "Port Jeuno",
            "Selbina", "Mhaura", "Kazham", "Norg", "Rabao", "Tavnazian Safehold",
            "Aht Urhgan Whitegate", "Al Zahbi", "Nashmau",
            "Southern San d'Oria (S)", "Bastok Markets (S)", "Windurst Waters (S)",
            -- "Walk of Echoes", "Provenance", -- YMMV
            "Western Adoulin", "Eastern Adoulin", "Celennia Memorial Library",
            "Bastok-Jeuno Airship", "Kazham-Jeuno Airship", "San d'Oria-Jeuno Airship", "Windurst-Jeuno Airship",
            "Ship bound for Mhaura", "Ship bound for Selbina", "Open sea route to Al Zahbi", "Open sea route to Mhaura",
            "Silver Sea route to Al Zahbi", "Silver Sea route to Nashmau", "Manaclipper", "Phanauet Channel",
            "Chocobo Circuit", "Feretory", "Mog Garden",
            }
    return function()
        if Cities:contains(get_zone()) then
            return true
        end
        return false
    end
end()

local midaction = function()
    local acting = false
    local last_action = -1
    local cooldown = false

    return function(param)
        if param ~= nil then
            acting = param and true
            cooldown = type(param) == 'number' and param > 0 and param
            last_action = os.clock()
        end
        if cooldown and os.clock() > (last_action + cooldown) then
            cooldown = false
            acting = false
        end

        return acting
    end
end()


-- returns a string with human readable time.
local time2human = function(seconds,period)
    local response = ''
    if seconds > 86400 then
        response = 'more than a day'
    else
        local h = math.floor(seconds/3600)
        local m = math.floor(seconds%3600/60)
        local s = seconds%60

        if h > 0 then response = '%s hour%s':format(h,h > 1 and 's' or '') end
        if h > 0 and m > 0 then response = response .. ' and ' end
        if m > 0 then response = response .. '%s minute%s':format(m,m > 1 and 's' or '') end
        if (h*10 + m) < 2 then response = '%s seconds':format(s) end
    end

    return response .. (period and '.' or '')
end

function start()
    if not active then
        active = check_signet_buffs:loop(cycle_time)
    end
end

function stop()
    if active then
        coroutine.close(active)
        active = false
    end
end

function gs_disable_slot(slot)
    send_command('gs disable '..res_slots[slot].en:gsub(' ','_'))
end

function gs_disable_gearswap()
    send_command('lua u gearswap')
end

function gs_enable_gearswap()
    send_command('lua l gearswap')
end

function gs_enable_slot(slot)
    send_command('gs enable '..res_slots[slot].en:gsub(' ','_'))
end

function my_preciouss() -- not very semantic but the ring will do that to you
    if not windower.ffxi.get_info().logged_in then
        return false
    end

    if busy or moving or midaction() then
        return false
    end

    if in_town() and use_in_town == 'no' then
        return false
    end

    if windower.ffxi.get_info().mog_house then
        return false
    end

    if windower.ffxi.get_player().status > 1 then
        return false
    end

    return true
end

function check_signet_buffs(option)

    if not my_preciouss() then
        return
    end

    local signet_buff = 0

    local player = windower.ffxi.get_player()

    for _,v in ipairs(player.buffs) do
        if v == buff_id['Signet'] then
            signet_buff = signet_buff +1
        end
    end

    local staffs = T{}
    if signet_buff < 1 then
        staffs:extend(signet_staffs_info)
    end
    search_staffs(staffs)
end

function search_staffs(item_info)
    local item_array = {}
    local bags = {0,8,10,11,12}
    local get_items = windower.ffxi.get_items
    for i=1,#bags do
        for _,item in ipairs(get_items(bags[i])) do
            if item.id > 0 then
                item_array[item.id] = item
                item_array[item.id].bag = bags[i]
            end
        end
    end
    local min_recast = false
    for index,stats in pairs(item_info) do
        local item = item_array[stats.id]
        local set_equip = windower.ffxi.set_equip
        if item then
            local ext = extdata.decode(item)
            local enchant = ext.type == 'Enchanted Equipment'
            local recast = enchant and ext.charges_remaining > 0 and math.max(ext.next_use_time+18000-os.time(),0)
            local usable = recast and recast == 0
            if usable then
                log(stats[lang])
            elseif recast then
                log(stats[lang],time2human(recast,true))
                if not min_recast or recast < min_recast then
                    min_recast = recast
                end
            end
            if usable then
                gs_disable_gearswap()

                busy = true
                if enchant and item.status ~= 30 then --not equipped
                    set_equip(item.slot,stats.slot,item.bag)
                    log_flag = true
                    local timeout = 0
                    repeat --waiting cast delay
                        coroutine.sleep(1)
                        local ext = extdata.decode(get_items(item.bag,item.slot))
                        local delay = ext.activation_time+18000-os.time()
                        timeout = timeout +1
                        if midaction() then
                            log(stats[lang],math.max(delay,0),'busy')
                            ext.usable = false
                        elseif delay > 0 then
                            log(stats[lang],delay)
                        elseif log_flag then
                            log_flag = false
                            log('Item use within 3 seconds..')
                        end
                    until ext.usable or delay > 45 or timeout > 90
                end
            windower.chat.input('/item '..windower.to_shift_jis(stats[lang])..' <me>')
            coroutine.sleep(2)
            busy = false
            gs_enable_gearswap()
            if idle_staff then
                coroutine.sleep(5)
                windower.chat.input('/equip "%s" %s':format(res_slots[stats.slot].name,idle_staff))
            end
            min_recast = false
            break
            end
        end
    end
    if min_recast then
        stop()
        start:schedule(min_recast)
        log('Staff on recast. Sleeping for',time2human(min_recast,true))
    end
end

windower.register_event('incoming chunk', function(id,data,modified,is_injected,is_blocked)
    if id == 0x028 then
        p = windower.packets.parse_action(data)
        if p.actor_id ~= windower.ffxi.get_player().id then
            return
        end
        -- this could be much simpler but I like the categorizations
        if p.category >= 2 and p.category <= 8 then -- finish: ranged atk, WS, spells, items; begin: JAs, WSs,
            midaction(2.5)
        elseif p.category == 6 or p.category == 7 or p.category == 14 then -- JA, WS/TP moves, DNC moves
            midaction(2.5)
        elseif p.category == 8 or p.category == 9 or p.category == 12 or p.category == 15 then -- spells, items, ranged attacks, run JAs?
            if p.param == 28787 then
                midaction(2.5)
            else
                midaction(true)
            end
        end
    end
end)

windower.register_event('load', function()
    if not windower.ffxi.get_info().logged_in then
        return
    end

    coroutine.sleep(0.5)

    -- opening equipment menu also gets current JP and Merits held.
    local packet = packets.new('outgoing', 0x061, {})
    packets.inject(packet)
end)

windower.register_event('unload',stop)

windower.register_event('outgoing chunk',function(id,data,modified,is_injected,is_blocked)
    if id == 0x015 then
        moving = lastlocation ~= modified:sub(5, 16)
        lastlocation = modified:sub(5, 16)

    end
end)


windower.register_event('addon command',function(cmd,opt)
    local cmd = cmd:lower()
    if cmd == 'reload' or cmd == 'r' then
        send_command('lua reload autosignet')
    elseif cmd == 'unload' or cmd == 'u' then
        send_command('lua unload autosignet')
    elseif cmd == 'on' or cmd == 'start' then
        log('Starting.')
        start()
    elseif cmd == 'off' or cmd == 'stop' then
        log('Stopping.')
        stop()
    elseif cmd == 'xp' or cmd == 'both' or cmd == 'normal' then
        override = cmd:sub(1,2)
        log('Override mode set to %s.':format(cmd:upper()))
    elseif tonumber(cmd) and tonumber(cmd) < 300 and tonumber(cmd) > 0 then
        cycle_time = cmd
        log('Delay between checks set to %s seconds.':format(cmd))
    elseif cmd == 'town' then
        use_in_town = use_in_town == 'no' and 'yes' or 'no'
        log('Rings %s be used in town.':format(use_in_town == 'yes' and 'will' or 'will not'))
    elseif cmd == 'check' then
        stop()
        start()
        log('Checking for new available rings...')
        log(capped_jp and 'JP are capped.' or '',capped_merits and 'Merits are capped' or '')
    elseif cmd == 'reset' then
        stop()
        init()
        log('Override disabled and delay between checks reset to %s seconds. Restarting.':format(cycle_time))
    elseif cmd == 'help' then
        log('Go to ffxiah.com and search for \'smeagol\' to get help.')
    else
        log('Command not valid.')
        send_command('smeagol help')
    end
end)

init()

