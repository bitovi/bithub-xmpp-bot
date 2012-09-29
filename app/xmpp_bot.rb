require 'rubygems'
require 'amqp'
require 'blather/client/dsl'
require 'log4r'
require 'yajl'

# Logging
$log = Log4r::Logger.new('XMPP-bot')
$log.add(Log4r::StdoutOutputter.new('console', {
  :formatter => Log4r::PatternFormatter.new(:pattern => "[#{Process.pid}:%l] %d :: %m")
}))

# RabbitMQ connection string
$mq_cs = ENV['MSGQ']

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
    write_to_stream s.approve!
  end

  # Echo back what was said
  message :chat?, :body do |m|
    say m.from, "You said: #{m.body}"
  end

  def self.say_to_roster(payload)
    msg = Yajl::Parser.parse(payload)
    my_roster.items.each do |item|
      say item[0], "#{msg['actor']} : #{msg['title']}"
    end
  end
end

EM.run do
  AMQP.connect($mq_cs) do |connection|
    channel  = AMQP::Channel.new(connection)
    queue = channel.queue("q.events.xmpp-bot").bind("e.events")
    queue.subscribe do |metadata, payload|
      EM.defer do
        Bot.say_to_roster payload
      end
    end

    EM.next_tick do
      Bot.run
    end

    stop = proc { puts "Terminating the XMPP bot"; connection.close { EM.stop } }
    Signal.trap("INT",  &stop)
    Signal.trap("TERM", &stop)
  end
end
