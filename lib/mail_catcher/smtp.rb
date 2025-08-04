# frozen_string_literal: true

require "eventmachine"

require "mail_catcher/mail"

class MailCatcher::Smtp < EventMachine::Protocols::SmtpServer
  @@parms ||= {}
  @@parms[:auth] = true

  # We override EM's mail from processing to allow multiple mail-from commands
  # per [RFC 2821](https://tools.ietf.org/html/rfc2821#section-4.1.1.2)
  def process_mail_from sender
    if @state.include? :mail_from
      @state -= [:mail_from, :rcpt, :data]

      receive_reset
    end

    super
  end
  
  def process_auth_line(line)
    begin
      plain = line.unpack("m").first
      _, user, password = plain.split("\000")
      
      if receive_plain_auth(user, password)
        @authenticated_user = user.to_s.strip
        send_data "235 authentication ok\r\n"
        @state << :auth
      else
        send_data "535 authentication failed\r\n"
      end
    rescue => e
      puts "==> SMTP: Auth decoding error: #{e.message}"
      send_data "535 authentication failed\r\n"
    ensure
      @state.delete(:auth_incomplete)
    end
  end
  
  def current_message
    @current_message ||= {}
  end

  def receive_reset
    @current_message = nil

    true
  end

  def receive_sender(sender)
    # EventMachine SMTP advertises size extensions [https://tools.ietf.org/html/rfc1870]
    # so strip potential " SIZE=..." suffixes from senders
    sender = $` if sender =~ / SIZE=\d+\z/

    current_message[:sender] = sender
    current_message[:inbox] = current_inbox

    true
  end

  def receive_recipient(recipient)
    current_message[:recipients] ||= []
    current_message[:recipients] << recipient

    true
  end

  def receive_data_chunk(lines)
    current_message[:source] ||= +""

    lines.each do |line|
      current_message[:source] << line << "\r\n"
    end

    true
  end

  def receive_message
    MailCatcher::Mail.add_message current_message
    MailCatcher::Mail.delete_older_messages!
    puts "==> SMTP: Received message from '#{current_message[:sender]}' (#{current_message[:source].length} bytes)"
    true
  rescue => exception
    MailCatcher.log_exception("Error receiving message", @current_message, exception)
    false
  ensure
    @current_message = nil
  end

  def current_inbox
    inbox = @authenticated_user || MailCatcher.options[:default_inbox] || 'default'
    
    inbox.to_s.strip
  end
end
