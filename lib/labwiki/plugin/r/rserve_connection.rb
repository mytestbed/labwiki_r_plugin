
module LabWiki::Plugin::R

  # Monkey patching what?????
  #
  class RServConnection < EventMachine::Connection
    attr_reader :rsrv_version

    def initialize(opts = {})
      @buffer = nil # using StringIO doesn't seem to work with binary

      @pending_queue = [] # keep track of size and callback waiting for incoming data
      state :waiting

      @gracefully_closed = false
      @reconnect_retries = 0
      @immediate_reconnect = false
      @last_data_received_at = nil

      # Process incoming header message
      on_recv(32) do |chunk|
        check_protocol(chunk)
      end
    end

    def ready?
      state? :initialized
    end

    def on_new_state(&clbk)
      @on_new_state_clbk = clbk
      @on_new_state_clbk.call(@state) if clbk && @state
    end

    def write(data)
      send_data(data)
    end

    def on_recv(size, &cbk)
      @pending_queue << [size, cbk]
      _check_pending_queue
    end

    def _check_pending_queue
      return unless (@pending_queue.length > 0 && @buffer)
      chunk_size, cbk = @pending_queue[0]
      return unless (@buffer.size >= chunk_size)

      @pending_queue.shift # remove job from queue
      #puts ">>>>> buff: #{@buffer.size} chunk_len: #{chunk_size}"
      if @buffer.length > chunk_size
        chunk = @buffer[0, chunk_size]
        @buffer = @buffer[chunk_size .. -1]
      else
        chunk = @buffer
        @buffer = nil
      end
      cbk.call(chunk)

      _check_pending_queue # maybe there is more to do
    end

    # === INTERNAL ===
    def post_init
      state :connected
    end

    def receive_data(data)
      #debug "Received #{data.length} bytes"
      #puts "INCOMING(#{data.length}): #{data} (buffer size: #{@buffer ? @buffer.length : 0})"
      @buffer = @buffer ? @buffer + data : data
      #puts "INCOMING2 buffer size: #{@buffer.size}"
      _check_pending_queue
    end

    # Check the first 32bits for
    def check_protocol(data)
      input = data.unpack("a4a4a4a4a4a4a4a4")
      #puts "CHECK: #{input.inspect}"
      unless input[0] == "Rsrv"
        raise Rserve::Connection::IncorrectServerError, "Handshake failed: Rsrv signature expected, but received [#{input[0]}]"
      end
      @rsrv_version = input[1].to_i
      if @rsrv_version > 103
        raise Rserve::Connection::IncorrectServerVersionError, "Handshake failed: The server uses more recent protocol than this client."
      end
      @protocol = input[2]
      if @protocol != "QAP1"
        raise Rserve::Connection::IncorrectProtocolError, "Handshake failed: unsupported transfer protocol #{@protocol}, I talk only QAP1."
      end
      (3..7).each do |i|
        # TODO: This is most likely going to fail miserably
        attr=input[i]
        if (attr=="ARpt")
          if (!auth_req) # this method is only fallback when no other was specified
            auth_req=true
            auth_type = Rserve::Connection::AT_plain
          end
        end
        if (attr=="ARuc")
          auth_req=true
          authType = Rserve::Connection::AT_crypt
        end
        if (attr[0]=='K')
          key=attr[1,3]
        end

      end
      state :initialized
    end

    def state(new_state = nil)
      if new_state && @state != new_state
        @state = new_state
        @on_new_state_clbk.call(state) if @on_new_state_clbk
      end
      @state
    end

    # Return true if current state is equal 'sate'
    def state?(state)
      @state == state
    end
  end
end