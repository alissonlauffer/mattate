--[[
    Copyright 2020 Matthew Hesketh <matthew@matthewhesketh.com>
    This code is licensed under the MIT. See LICENSE for details.
]]

local allowlist = {}
local mattata = require('mattata')
local redis = require('libs.redis')

function allowlist:init()
    allowlist.commands = mattata.commands(self.info.username):command('allowlist').table
    allowlist.help = '/allowlist [user] - Allowlists a user to use the bot in the current chat. This command can only be used by moderators and administrators of a supergroup.'
end

function allowlist:on_message(message, configuration, language)
    if message.chat.type ~= 'supergroup'
    then
        return mattata.send_reply(
            message,
            language['errors']['supergroup']
        )
    elseif not mattata.is_group_admin(
        message.chat.id,
        message.from.id
    )
    then
        return mattata.send_reply(
            message,
            language['errors']['admin']
        )
    end
    local reason = false
    local input = message.reply
    and (
        message.reply.from.username
        or tostring(message.reply.from.id)
    )
    or mattata.input(message.text)
    if not input
    then
        local success = mattata.send_force_reply(
            message,
            language['allowlist']['1']
        )
        if success
        then
            redis:set(
                string.format(
                    'action:%s:%s',
                    message.chat.id,
                    success.result.message_id
                ),
                '/allowlist'
            )
        end
        return
    elseif not message.reply
    then
        if input:match('^.- .-$')
        then
            reason = input:match(' (.-)$')
            input = input:match('^(.-) ')
        end
    elseif mattata.input(message.text)
    then
        reason = mattata.input(message.text)
    end
    if tonumber(input) == nil
    and not input:match('^%@')
    then
        input = '@' .. input
    end
    local user = mattata.get_user(input)
    or mattata.get_chat(input) -- Resolve the username/ID to a user object.
    if not user
    then
        return mattata.send_reply(
            message,
            language['errors']['unknown']
        )
    elseif user.result.id == self.info.id
    then
        return
    end
    user = user.result
    local status = mattata.get_chat_member(
        message.chat.id,
        user.id
    )
    if not status
    then
        return mattata.send_reply(
            message,
            language['errors']['generic']
        )
    elseif mattata.is_group_admin(
        message.chat.id,
        user.id
    )
    or status.result.status == 'creator'
    or status.result.status == 'administrator'
    then -- We won't try and allowlist moderators and administrators.
        return mattata.send_reply(
            message,
            language['allowlist']['2']
        )
    elseif status.result.status == 'left'
    or status.result.status == 'kicked'
    then -- Check if the user is in the group or not.
        return mattata.send_reply(
            message,
            status.result.status == 'left'
            and language['allowlist']['3']
            or language['allowlist']['4']
        )
    end
    redis:del('group_allowlist:' .. message.chat.id .. ':' .. user.id)
    redis:hincrby(
        string.format(
            'chat:%s:%s',
            message.chat.id,
            user.id
        ),
        'allowlists',
        1
    )
    if redis:hget(
        string.format(
            'chat:%s:settings',
            message.chat.id
        ),
        'log administrative actions'
    ) then
        mattata.send_message(
            mattata.get_log_chat(message.chat.id),
            string.format(
                '<pre>%s%s [%s] has allowlisted %s%s [%s] in %s%s [%s]%s.</pre>',
                message.from.username and '@' or '',
                message.from.username or mattata.escape_html(message.from.first_name),
                message.from.id,
                user.username and '@' or '',
                user.username or mattata.escape_html(user.first_name),
                user.id,
                message.chat.username and '@' or '',
                message.chat.username or mattata.escape_html(message.chat.title),
                message.chat.id,
                reason and ', for ' .. reason or ''
            ),
            'html'
        )
    end
    mattata.unban_chat_member(message.chat.id, user.id) -- attempt to unban the user too
    return mattata.send_message(
        message.chat.id,
        string.format(
            '<pre>%s%s has allowlisted %s%s%s.</pre>',
            message.from.username and '@' or '',
            message.from.username or mattata.escape_html(message.from.first_name),
            user.username and '@' or '',
            user.username or mattata.escape_html(user.first_name),
            reason and ', for ' .. reason or ''
        ),
        'html'
    )
end

return allowlist