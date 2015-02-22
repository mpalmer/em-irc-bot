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

	# The nick or channel which originated the message.
	#
	# @return [String]
	#
	attr_reader :source

	# The nick which sent the message.  For private messages, this will
	# be the same as {#source}, but for messages in-channel, this will be
	# the nick which sent the message, while {#source} is the channel.
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
	def initialize(bot, source, sender, line)
		@bot    = bot
		@source = source
		@sender = sender
		@line   = line
	end

	# Send a line of text back to the source of the message.
	#
	# This is only a reply to the *source*; it doesn't modify your message at
	# all to, say, prepend the nick of the sender.  That bit's up to you.
	#
	# @param s [String] The message to send.
	#
	# @return void
	#
	def reply(s)
		bot.say(source, s)
	end
end
