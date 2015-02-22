#:nodoc:
#
class EM::IrcBot::ConnHandler < EventMachine::Connection
	extend Forwardable
	def_delegators :@parent, :receive_data, :unbind
		
	def initialize(parent, tls = false)
		@parent = parent
		@tls    = tls
	end
		
	#:nodoc:
	def connection_completed
		@tls ? start_tls : @parent.ready
	end

	#:nodoc:
	def ssl_handshake_completed
		@parent.ready
	end
end
