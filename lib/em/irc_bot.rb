require 'openssl'
require 'eventmachine'
require 'forwardable'
require 'logger'

# A straightforward, if slightly bare-bones, EventMachine-based IRC bot
# framework.
#
# IRC bots.  We love 'em.  Chatops wouldn't exist without 'em.  Sometimes,
# when you're feeling a bit of self-loathing, you might decide you want to
# write one using EventMachine.  Make life a bit easier on yourself, and use
# this class.
#
# Basic usage is pretty simple: create a new instance, passing in all sorts
# of options to specify the server to talk to and the channels to join.  Then
# specify what to respond to, and how to respond to it, by using the {#on}
# method to register callbacks in response to all lines which match a given
# regular expression.  That's... pretty much it.  The rest is up to you.
# 
class EM::IrcBot
	# This bot's nick.
	#
	# @return [String]
	#
	attr_reader :nick

	# Create a new IRC bot.
	#
	# If you want to have the bot connect to the server immediately upon
	# creation, pass the `:server` and `:port` (and optionally `:tls`)
	# options.  Otherwise, you can ask the bot to connect any later time with
	# {#connect}.
	#
	# @param nick [String] The IRC 'nickname' of the bot.
	#
	# @param opts [Hash] Additional configuration options.
	#
	# @option opts [String] :serverpass The server-level password needed to
	#   access the server.  If you don't know you need this, you almost
	#   certainly don't.  Typically, only private IRC servers use this.
	#
	# @option opts [String] :username The 'username' of the bot, as seen by
	#   the IRC network.  This defaults to `"em-irc-bot"` if you don't set
	#   it.
	#
	# @option opts [String] :realname The 'realname' of the bot, as seen by
	#   the IRC network.  This defaults to `"EM::IrcBot"` if you don't set
	#   it.
	#
	# @option opts [Array<String>] :channels A list of channels to
	#   automatically join on startup.  The name **must** include the leading
	#   `#`.
	#
	# @option opts [String] :server The server to connect to.  If you don't
	#   specify this, you can trigger a connection by calling {#connect}.
	#
	# @option opts [Fixnum] :port The port on the server to connect to.  If
	#   you don't specify this, you can trigger a connection by calling
	#   {#connect}.
	#
	# @option opts [Boolean] :tls Whether to use TLS on the
	#   connection to the server.  This option is only useful when `:server`
	#   and `:port` are set as options to the constructor.
	#
	# @option opts [Logger] :logger A logger to use.  All communication
	#   between the bot and server will be logged at `INFO` priority, so
	#   consider that when setting the logger's priority.  If no logger is
	#   specified, a default logger will be setup to send only fatal errors
	#   to `$stderr`.
	#
	# @option opts [String] :command_prefix The string which must precede
	#   any commands sent to the bot in-channel.  The default is `"!"`.
	#
	def initialize(nick, opts = {})
		@nick             = nick
		@ready            = false
		@backlog          = ""
		@line_handlers    = {}
		@privmsg_handlers = {}
		@commands         = {}

		@serverpass = opts[:serverpass]
		@username   = opts[:username] || "em-irc-bot"
		@realname   = opts[:realname] || "EM::IrcBot"
		@channels   = opts[:channels] || []
		@log        = opts[:logger]   || Logger.new($stderr).tap do |l|
		                                   l.level = Logger::FATAL
		                                   l.formatter = proc { |s, dt, p, m| "#{m}\n" }
		                                 end
		@cmd_prefix = opts[:command_prefix] || "!"

		if opts[:server] and opts[:port]
			connect(opts[:server], opts[:port], opts[:tls])
		end

		on(/^ping( |$)/i) do |s, _|
			s.send_line "PONG"
		end

		on(/^:[^\s]+ PRIVMSG /, &method(:do_privmsg))

		listen_for(/./, &method(:command_handler))
	end

	# Connect to an IRC server.
	#
	# If a connection is already established, the bot will be disconnect and
	# then a new connection made to the specified server.
	#
	# @param host [String] The name or address of a server to connect to.
	#
	# @param port [Fixnum] The port number to connect to.
	#
	# @param tls [Boolean] Whether or not to use TLS over the
	#   connection.
	#
	# @return void
	#
	def connect(host, port, tls = false)
		@host = host
		@port = port
		@tls  = tls
		
		reconnect
	end
	
	# Make the bot join a channel.
	#
	# @param ch [String] The name of the channel to join, including the
	#   leading `#`.
	#
	# @return void
	#
	def join(ch)
		send_line("JOIN #{ch}")
	end

	# Register a callback to be executed on a given command.
	#
	# A command is anything said in-channel which is prefixed by the
	# `:command_prefix` option passed to the bot's constructor (`"!"` by
	# default), or anything at all said to the bot privately.
	#
	# Only one callback can be registered for a given command.  If you
	# register for the same command twice, only the last callback will be
	# activated.
	#
	# @param cmd [String] The command to call back for.  It must have
	#   no whitespace.
	#
	# @param blk [Proc] The callback.
	#
	# @yieldparam [EM::IrcBot::Message] The full message that was received.
	#   This is given so you can reply through it
	#
	# @yieldparam [String] The command itself.  Just in case you have multiple
	#   commands pointing to the same block, so you can differentiate between
	#   them.
	#
	# @yieldparam [Array<String>] The remaining arguments that were passed to
	#   the command.  All command arguments are strictly whitespace-separated.
	#   There is no way to pass an argument containing whitespace.
	#
	# @return void
	#
	def command(cmd, &blk)
		@commands[cmd] = blk
	end

	# Register a new callback for a PRIVMSG seen by the bot.
	#
	# The fundamental way of causing the bot to interact with its environment
	# is to watch for incoming messages, and run all callbacks associated
	# with regular expressions which match the line that was received.  This
	# method registers those callbacks.
	#
	# @note This method only matches against the message body -- what a user
	#   "normally" sees in their IRC client as conversation.  While this is
	#   *usually* what you want, if you want your bot to respond to control
	#   data, like join/part, you'll want to use {#on} instead of this
	#   method.
	#
	# @param match [Regexp] A regular expression to match against the content
	#   of every message.  Nothing special is done to the regex, so
	#   you'll probably want to anchor it at the beginning in most cases.
	#
	# @param opts [Hash] Zero or more optional parameters that can alter the
	#   way that the handler behaves, or the circumstances in which it is
	#   invoked.
	#
	# @param blk [Proc] A callback to be executed when an incoming message
	#   matches the regexp.
	#
	# @yieldparam [EM::IrcBot::Message] an object which contains the message,
	#   as well as information about the sender, and has some convenience
	#   methods for easily replying.
	#
	# @yieldparam [String] Any captured subexpressions in `match` will be
	#   passed as additional arguments to the callback.
	#
	# @return void
	#
	def listen_for(match, opts = {}, &blk)
		@log.debug { "Setting handler for #{match.inspect}, opts: #{opts.inspect}" }
		@privmsg_handlers[match] = blk
	end

	# Register a new callback to handle a line sent to the bot.
	#
	# This method matches against *everything* in the data line; you'll need
	# to handle all of the protocol internal parts yourself.  In general, you
	# probably want to use {#listen_for} instead.
	#
	# @param match [Regexp] A regular expression to match against the line.
	#
	# @param blk [Proc] The callback to be executed when an incoming line
	#   matches the regexp.
	#
	# @yieldparam [EM::IrcBot] The bot instance that generated the message; this
	#   allows you to call back into the bot to send replies.
	#
	# @yieldparam [String] The line of data which was sent.
	#
	def on(match, &blk)
		@log.debug { "Setting 'on' handler for #{match.inspect}" }
		@line_handlers[match] = blk
	end

	# Register a new "one-shot" callback to handle a single line sent to the
	# bot.
	#
	# Sometimes, you want to respond to only the "next" message matching a
	# particular regex.  That's what this method is for.  The first line that
	# matches the regex will cause the callback to be called (in the same
	# manner as {#on}), and then the handler will be deleted.
	#
	# @see {#on}
	#
	def on_once(match, opts = {}, &blk)
		on(match) do |*args|
			blk.call(*args)
			@line_handlers.delete(match)
		end
	end

	# Send a (raw) line to the server.
	#
	# This method does *nothing* to your line, except terminate it.  In general,
	# you should rarely, if ever, use this method yourself.
	#
	# @param s [String] The line to send to the server.
	#
	# @raise [ArgumentError] if the line you want to send has a newline or
	#   carriage return in it.  That is not allowed.
	#
	# @return void
	#
	def send_line(s)
		if s =~ /[\r\n]/
			raise ArgumentError,
			      "Line contained NL or CR"
		end

		@log.info ">> #{s}"
		@conn.send_data("#{s}\r\n")
	end
	
	# Send a message to someone (or a channel)
	#
	# @param target [String] the nick or channel to send the message to.
	#
	# @param msg [String] the message to send.
	#
	def say(target, msg)
		send_line("PRIVMSG #{target} :#{msg}")
	end

	#:nodoc:
	#
	# Callback used by {EM::IrcBot::ConnHandler} to signal to the bot that
	# the connection is established.
	#
	def ready
		@log.debug "Ready to rock and/or roll"
		send_line("PASS #{@serverpass}") if @serverpass
		send_line("NICK #{@nick}")
		send_line("USER #{@username} 0 * :#{@realname}")
		
		on_once(/^:#{@nick} /) do
			@channels.each do |ch|
				join(ch)
			end
		end

		@ready = true
	end

	# Tell whether the bot is ready to do things.
	#
	# @return [Boolean]
	#
	def ready?
		@ready
	end

	#:nodoc:
	#
	# Callback used by {EM::IrcBot::ConnHandler} to give us data that has
	# come from the server.
	#
	def receive_data(s)
		s = @backlog + s
		
		while (i = s.index("\r\n")) do
			l = s[0..i-1]
			s = s[i+2..-1]

			@log.info "<< #{l}"
			@line_handlers.each_pair do |re, blk|
				blk.call(self, l) if re =~ l
			end
		end

		@backlog = s
	end

	#:nodoc:
	#
	# Callback used by {EM::IrcBot::ConnHandler} to tell us that our
	# connection has gone away.
	#
	def unbind(*args)
		@log.debug "Unbind called: #{args.inspect}"
		@ready = false
		@conn = nil

		EM.add_timer(1) { reconnect }
	end

	private

	def reconnect
		@log.info { "Connecting to #{@host}:#{@port}, TLS? #{@tls.inspect}" }

		@conn && @conn.close_connection

		@conn = EM.connect(@host, @port, EM::IrcBot::ConnHandler, self, @tls)
	end

	def do_privmsg(bot, line)
		unless line =~ /^:([^!]+)![^ ]+ PRIVMSG ([^ ]+) :(.*)$/
			raise ArgumentError,
			      "do_privmsg got line that wasn't a PRIVMSG: #{l.inspect}"
		end

		channel = ($2 == nick) ? $1 : $2
		sender  = $1
		message = $3

		msg = EM::IrcBot::Message.new(self, channel, sender, message)

		@privmsg_handlers.each_pair do |re, blk|
			if (matchdata = message.match(re))
				blk.call(msg, *(matchdata[1..-1]))
			end
		end
	end

	def command_handler(msg)
		if msg.private? or msg.line.index(@cmd_prefix) == 0
			cmdline = msg.line.gsub(/^#{@cmd_prefix}/, '').split(/\s+/)
			if @commands[cmdline[0]]
				@commands[cmdline[0]].call(msg, cmdline[0], cmdline[1..-1])
			else
				msg.reply "I don't understand that."
			end
		end
	end
end

require_relative "irc_bot/conn_handler"
require_relative "irc_bot/message"
