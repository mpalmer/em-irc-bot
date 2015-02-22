This is a (presently) bare-bones framework for writing an IRC bot, using
EventMachine behind the scenes.


# Why EM?

Why not?


# Basic Usage

Create a new bot and connect to a server:

    require 'em/irc_bot'
    
    bot = EM::IrcBot.new("fred",
                         server: "irc.example.com",
                         port: 6667,
                         channels: ["#botz"])

Say some stuff:

    bot.say("#botz", "'sup, bots?")

React to things other people say:

    bot.on(/^fred:/) do |msg|
      msg.reply "You talkin' to me?"
    end

For more info, see the docs for {EM::IrcBot}.
    
