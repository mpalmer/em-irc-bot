# A message that has come in to the bot from the server.
#
# You will see one of these objects in every one of your `#on` callbacks --
# it is what gets yielded to your callbacks.  You should never need to
# create an instance of this class yourself.
#
class EM::IrcBot::Message
	# The instance of {EM::IrcBot} from which this message originated.
	# Useful if you want to send a customised message back.
	#
	# @example Use .bot to send a message
	#   on(/./) do |msg|
	#     msg.bot.say "master", "I was sent a message: #{msg.line}"
	#   end
	#
	# @return [EM::IrcBot]
	#
	attr_reader :bot

	# The public channel, or nick, which originated the message.  This is the
	# place which replies will be sent to by {#reply}.
	#
	# @return [String]
	#
	attr_reader :channel

	# The nick which sent the message.  For private messages, this will be
	# the same as {#channel}, but for messages in-channel, this will be the
	# nick which sent the message, while {#channel} is, well, the channel.
	#
	# @return [String]
	#
	attr_reader :sender

	# The text of the message.
	#
	# @return [String]
	#
	attr_reader :line

	#:nodoc:
	#
	def initialize(bot, channel, sender, line)
		@bot     = bot
		@channel = channel
		@sender  = sender
		@line    = line
	end

	# Send a line of text back to the channel which originated the message.
	#
	# This is only a reply to the *source channel*; it doesn't modify your
	# message at all to, say, prepend the nick of the sender.  That bit's up
	# to you.
	#
	# @param s [String] The message to send.
	#
	# @return void
	#
	def reply(s)
		bot.say(channel, s)
	end

	# Whether or not this message was sent directly to the bot, or came to us
	# via a channel.
	#
	# @return [Boolean]
	#
	def private?
		channel == sender
	end
end
