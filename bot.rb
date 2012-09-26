require 'rubygems'
require 'amqp'
require 'blather/client/dsl'
require 'log4r'

# Logging
$log = Log4r::Logger.new('jabber-client')
$log.add(Log4r::StdoutOutputter.new('console', {
  :formatter => Log4r::PatternFormatter.new(:pattern => "[#{Process.pid}:%l] %d :: %m")
}))

module Bot
  extend Blather::DSL
  def self.run; client.run; end
  setup ENV['JID'], ENV['JPASSWORD']

  when_ready do
    $log.info "Connected ! send messages to #{jid.stripped}."
    write_to_stream Blather::Stanza::Presence::Status.new(:available, "Feeding you updates since 1908!")
  end

  # Auto approve subscription requests
  subscription :request? do |s|
    # $log.info s.inspect
    write_to_stream s.approve!
  end

  # Echo back what was said
  message :chat?, :body do |m|
    # $log.info m.body.inspect
    say m.from, "You said: #{m.body}"
  end

  def self.say_to_roster(payload)
    my_roster.items.each do |item|
      say item[0], payload
    end
  end
end

EM.run do
  AMQP.connect(ENV['MSQ_QUEUE']) do |connection|
    channel  = AMQP::Channel.new(connection)
    queue = channel.queue("q.events.xmpp-bot").bind("e.events")
    queue.subscribe do |metadata, payload|
      # $log.info payload.inspect
      Bot.say_to_roster payload
    end

    EM.next_tick do
      Bot.run
    end

    stop = proc { puts "Terminating the XMPP bot"; connection.close { EM.stop } }
    Signal.trap("INT",  &stop)
    Signal.trap("TERM", &stop)

  end
end
