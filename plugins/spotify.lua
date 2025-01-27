--[[
    Copyright 2020 Matthew Hesketh <matthew@matthewhesketh.com>
    This code is licensed under the MIT. See LICENSE for details.
]]

local spotify = {}
local mattata = require('mattata')
local https = require('ssl.https')
local url = require('socket.url')
local json = require('dkjson')
local redis = require('libs.redis')
local ltn12 = require('ltn12')

function spotify:init()
    spotify.commands = mattata.commands(self.info.username):command('spotify').table
    spotify.help = '/spotify <query> - Searches Spotify for a track matching the given search query and returns the most relevant result.'
end

function spotify.get_track(jdat)
    if jdat.tracks.total == 0
    then
        return false
    end
    local output = ''
    if jdat.tracks.items[1].name
    then
        if jdat.tracks.items[1].external_urls.spotify
        then
            output = output .. '<b>Song:</b> <a href="' .. jdat.tracks.items[1].external_urls.spotify .. '">' .. mattata.escape_html(jdat.tracks.items[1].name) .. '</a>\n'
        else
            output = output .. '<b>Song:</b> ' .. mattata.escape_html(jdat.tracks.items[1].name) .. '\n'
        end
    end
    if jdat.tracks.items[1].album.name
    then
        if jdat.tracks.items[1].album.external_urls.spotify
        then
            output = output .. '<b>Album:</b> <a href="' .. jdat.tracks.items[1].album.external_urls.spotify .. '">' .. mattata.escape_html(jdat.tracks.items[1].album.name) .. '</a>\n'
        else
            output = output .. '<b>Album:</b> ' .. mattata.escape_html(jdat.tracks.items[1].album.name) .. '\n'
        end
    end
    if jdat.tracks.items[1].album.artists[1].name
    then
        if jdat.tracks.items[1].album.artists[1].external_urls.spotify
        then
            output = output .. '<b>Artist:</b> <a href="' .. jdat.tracks.items[1].album.artists[1].external_urls.spotify .. '">' .. mattata.escape_html(jdat.tracks.items[1].album.artists[1].name) .. '</a>\n'
        else
            output = output .. '<b>Artist:</b> ' .. mattata.escape_html(jdat.tracks.items[1].album.artists[1].name) .. '\n'
        end
    end
    if jdat.tracks.items[1].disc_number
    then
        output = output .. '<b>Disc:</b> ' .. jdat.tracks.items[1].disc_number .. '\n'
    end
    if jdat.tracks.items[1].track_number
    then
        output = output .. '<b>Track:</b> ' .. jdat.tracks.items[1].track_number .. '\n'
    end
    if jdat.tracks.items[1].popularity
    then
        output = output .. '<b>Popularity:</b> ' .. jdat.tracks.items[1].popularity
    end
    return output ~= ''
    and output
    or false
end

function spotify:on_message(message, configuration, language)
    local input = mattata.input(message.text)
    if not input
    then
        return mattata.send_reply(
            message,
            spotify.help
        )
    elseif not redis:get('spotify:' .. message.from.id .. ':access_token')
    then
        if redis:get('spotify:' .. message.from.id .. ':refresh_token')
        then
            local query = 'grant_type=refresh_token&refresh_token=' .. url.escape(
                redis:get('spotify:' .. message.from.id .. ':refresh_token')
            ) .. '&client_id=' .. configuration['keys']['spotify']['client_id'] .. '&client_secret=' .. configuration['keys']['spotify']['client_secret']
            local wait_message = mattata.send_message(
                message.chat.id,
                'Re-authorising your Spotify account, please wait...'
            )
            local response = {}
            local _, res = https.request(
                {
                    ['url'] = 'https://accounts.spotify.com/api/token',
                    ['method'] = 'POST',
                    ['headers'] = {
                        ['Content-Type'] = 'application/x-www-form-urlencoded',
                        ['Content-Length'] = query:len()
                    },
                    ['source'] = ltn12.source.string(query),
                    ['sink'] = ltn12.sink.table(response)
                }
            )
            local jdat = json.decode(
                table.concat(response)
            )
            if res ~= 200
            or not jdat
            or jdat.error
            then
                return mattata.edit_message_text(
                    message.chat.id,
                    wait_message.result.message_id,
                    'An error occcured whilst re-authorising your Spotify account. Please try again later.'
                )
            end
            redis:set(
                'spotify:' .. message.from.id .. ':access_token',
                jdat.access_token
            )
            redis:expire(
                'spotify:' .. message.from.id .. ':access_token',
                3600
            )
            mattata.edit_message_text(
                message.chat.id,
                wait_message.result.message_id,
                'Successfully re-authorised your Spotify account! Processing your original request...'
            )
        else
            local success = mattata.send_force_reply(
                message,
                'You need to authorise mattata in order to connect your Spotify account. Click [here](https://accounts.spotify.com/en/authorize?client_id=' .. url.escape(configuration['keys']['spotify']['client_id']) .. '&response_type=code&redirect_uri=' .. configuration['keys']['spotify']['redirect_uri'] .. '&scope=user-library-read,playlist-read-private,playlist-read-collaborative,user-read-private,user-read-email,user-follow-read,user-top-read,user-read-playback-state,user-read-recently-played,user-read-currently-playing,user-modify-playback-state) and press the green "OKAY" button to link mattata to your Spotify account. After you\'ve done that, send the link you were redirected to (it should begin with "' .. configuration['keys']['spotify']['redirect_uri'] .. '", followed by a unique code) in reply to this message.',
                'markdown'
            )
            if success
            then
                redis:set(
                    string.format(
                        'action:%s:%s',
                        message.chat.id,
                        success.result.message_id
                    ),
                    '/authspotify'
                )
            end
            return
        end
    end
    local response = {}
    local _, res = https.request(
        {
            ['url'] = 'https://api.spotify.com/v1/search?q=' .. url.escape(input) .. '&type=track&limit=1',
            ['method'] = 'GET',
            ['headers'] = {
                ['Authorization'] = 'Bearer ' .. redis:get('spotify:' .. message.from.id .. ':access_token')
            },
            ['sink'] = ltn12.sink.table(response)
        }
    )
    if res ~= 200
    then
        return mattata.send_reply(
            message,
            language['errors']['connection']
        )
    end
    local jdat = json.decode(
        table.concat(response)
    )
    local output = spotify.get_track(jdat)
    if not output
    then
        return mattata.send_reply(
            message,
            language['errors']['results']
        )
    end
    return mattata.send_message(
        message.chat.id,
        output,
        'html'
    )
end

return spotify
