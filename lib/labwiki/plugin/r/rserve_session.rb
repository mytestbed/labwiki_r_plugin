require 'omf_base/lobject'
require 'stringio'
require 'rserve'

require 'labwiki/plugin/r/protocol'
require 'labwiki/plugin/r/rserve_connection'


module LabWiki::Plugin::R

  RSERVE_INTERNALS_DEBUG = false # create debug messages related to RServe internals

  # Thrown by eval handler if the just processed line
  # should be pre-pended to the next line and tried again
  class IncompleteCommand < Exception; end

  # Creates and maintains a session with a specific
  # RServe server.
  #
  class RSession < OMF::Base::LObject
    DEF_RSERVE_HOST = 'localhost'
    DEF_RSERVE_PORT = 6311

    @@rserve = {host: 'localhost'}

    attr_reader :auth_req
    attr_reader :auth_type

    # Create a new session for a LW user. User credentials
    # are maintained in 'opts'.
    #
    def initialize(opts = {})
      @host = opts[:host] || @@rserve[:host] || DEF_RSERVE_HOST
      @port = opts[:port] || @@rserve[:port] || DEF_RSERVE_PORT
      @connection_state = :unknown

      @is_processing = false
      @last_eval_line = nil

      @process_queue = []
      @version = nil
      @version_cbk = nil

      si = File.read(File.join(File.dirname(__FILE__), 'session_init.R'))
      eval(si) do |state, msg|
        if state == :ok
          @version = msg.to_ruby
          @version_cbk.call(version) if @version_cbk
          @version_cbk = nil
          #puts "IIINIT> #{@version}"
        else
          error "Couldn't initialize RServe - #{msg}"
        end
      end

      debug "Attempting to connect to Rserve"
      EventMachine::connect @host, @port, RServConnection do |c|
        @connection = c
        @protocol = Protocol.new(c)
        c.on_new_state do |state|
          debug "Connection state: ", state
          @connection_state = state
          _process_queue
        end
      end
    end

    # Reset this session. May need to send something to the backend as well
    #
    def reset
      @last_eval_line = nil
      @process_queue.clear
    end

    def eval_cmd_line(cmd, &block)
      #eval("LW$eval(\"#{cmd}\")", &block)
      eval(cmd, true, &block)
    end

    # evaluates the given command and call the supplied block with the result
    #
    # * @param cmd command/expression string
    # * @param &block Block to call with R-xpression or <code>null</code> if an error occured
    #
    def eval(cmd, is_command_line = false, &block)
      @process_queue << [cmd, is_command_line, block]
      _process_queue
    end

    # Return the version. If not known report it through the optional
    # callback when available
    def version(&callback)
      unless @version
        @version_cbk = callback
      end
      @version
    end

    # Process one command at a time as there is a sequencing problem in the Talker. We would need to ensure
    # that the various reads there would be sequenced within a command 'fiber'.
    #
    def _process_queue
      return unless @protocol && @protocol.ready?
      return if @is_processing
      return if @process_queue.empty?

      cmd, is_command_line, block = @process_queue.shift
      @is_processing = true
      #eval_line = cmd + "\n"
      if @last_eval_line
        cmd = @last_eval_line + "\n" + cmd
      end
      cont = is_command_line ? "LW$eval(#{cmd.inspect})" : cmd
      debug "EVAL: #{cont[0 .. 70]}"
      @protocol.request(cmd: Rserve::Protocol::CMD_eval, cont: cont) do |rp|
        begin
          next unless @is_processing # skip if session had been reset in the meantime
          if !rp.nil? and rp.ok?
            res = parse_eval_response(rp)
            begin
              block.call(:ok, res)
              @last_eval_line = nil
            rescue IncompleteCommand
              @last_eval_line = cmd
            end
          else
            block.call(:eval_error, "eval failed: #{rp.to_s}")
          end
        rescue => ex
          warn "Error while processing R result - #{ex}"
          debug ex.backtrace.join("\n\t")
        end
        @is_processing = false
        _process_queue
      end
    end

    # NOT TESTED
    def parse_eval_response(rp)
      rxo=0
      pc=rp.cont
      if (@connection.rsrv_version > 100) # /* since 0101 eval responds correctly by using DT_SEXP type/len header which is 4 bytes long */
        rxo=4
        # we should check parameter type (should be DT_SEXP) and fail if it's not
        if pc.nil?
          raise "Error while processing eval output: SEXP (type #{Rserve::Protocol::DT_SEXP}) expected but nil returned"
        elsif (pc[0]!=Rserve::Protocol::DT_SEXP and pc[0]!=(Rserve::Protocol::DT_SEXP|Rserve::Protocol::DT_LARGE))
          raise "Error while processing eval output: SEXP (type #{Rserve::Protocol::DT_SEXP}) expected but found result type "+pc[0].to_s+"."
        end

        if (pc[0]==(Rserve::Protocol::DT_SEXP|Rserve::Protocol::DT_LARGE))
          rxo=8; # large data need skip of 8 bytes
        end
        # warning: we are not checking or using the length - we assume that only the one SEXP is returned. This is true for the current CMD_eval implementation, but may not be in the future. */
      end
      if pc.length>rxo
        rx = Rserve::Protocol::REXPFactory.new;
        rx.parse_REXP(pc, rxo);
        return rx.get_REXP();
      else
        return nil
      end
    end


    # class Talker < OMF::Base::LObject
    #   include Rserve::Protocol
    #
    #   attr_reader :io
    #
    #   def initialize(io)
    #     @io = io
    #   end
    #
    #   def ready?
    #     io.ready?
    #   end
    #
    #   def debug(*args)
    #     super if RSERVE_INTERNALS_DEBUG
    #   end
    #
    #   # sends a request with attached prefix and  parameters.
    #   # All parameters should be enter on Hash
    #   # Both :prefix and :cont can be <code>nil</code>.
    #   #   Effectively <code>request(:cmd=>a,:prefix=>b,:cont=>nil)</code>
    #   #   and <code>request(:cmd=>a,:prefix=>nil,:cont=>b)</code> are equivalent.
    #   #
    #   # @param :cmd command - a special command of -1 prevents request from sending anything
    #   # @param :prefix - this content is sent *before* cont. It is provided to save memory copy operations
    #   #                  where a small header precedes a large data chunk (usually prefix conatins
    #   #                  the parameter header and cont contains the actual data).
    #   # @param :cont contents
    #   # @param :offset offset in cont where to start sending (if <0 then 0 is assumed, if >cont.length then no cont is sent)
    #   # @param :len number of bytes in cont to send (it is clipped to the length of cont if necessary)
    #   # @return returned packet or <code>null</code> if something went wrong */
    #   #
    #   def request(params=Hash.new, &result_cbk)
    #
    #     cmd     = params.delete :cmd
    #     prefix  = params.delete :prefix
    #     cont    = params.delete :cont
    #     offset  = params.delete :offset
    #     len     = params.delete :len
    #
    #     if cont.is_a? String
    #       cont=request_string(cont)
    #     elsif cont.is_a? Integer
    #       cont=request_int(cont)
    #     end
    #     raise ArgumentError, ":cont should be an Enumerable" if !cont.nil? and !cont.is_a? Enumerable
    #     if len.nil?
    #       len=(cont.nil?) ? 0 : cont.length
    #     end
    #
    #     offset||=0
    #
    #
    #     if (!cont.nil?)
    #       raise ":cont shouldn't contain anything but Fixnum" if cont.any? {|v| !v.is_a? Fixnum}
    #       if (offset>=cont.length)
    #         cont=nil;len=0
    #       elsif (len>cont.length-offset)
    #         len=cont.length-offset
    #       end
    #     end
    #     offset=0 if offset<0
    #     len=0 if len<0
    #     contlen=(cont.nil?) ? 0 : len
    #     contlen+=prefix.length if (!prefix.nil? and prefix.length>0)
    #
    #     hdr=Array.new(16)
    #     set_int(cmd,hdr,0)
    #     set_int(contlen,hdr,4);
    #     8.upto(15) {|i| hdr[i]=0}
    #     if (cmd!=-1)
    #       io.write(hdr.pack("C*"))
    #       if (!prefix.nil? && prefix.length>0)
    #         io.write(prefix.pack("C*"))
    #         debug "SEND PREFIX #{prefix}"
    #       end
    #       if (!cont.nil? and cont.length>0)
    #         debug "SEND CONTENT #{cont.slice(offset, len)} (#{offset},#{len})"
    #         io.write(cont.slice(offset, len).pack("C*"))
    #       end
    #     end
    #
    #     io.on_recv(16) do |chunk|
    #       #"Expecting 16 bytes..." if $DEBUG
    #       ih = chunk.unpack("C*")
    #       if (ih.length != 16)
    #         debug "Received #{ih.length} of expected 16."
    #         result_cbk.call(nil)
    #         return
    #       end
    #       debug "Answer: #{ih.to_s}"
    #
    #       rep=get_int(ih, 0);
    #       rl =get_int(ih,4);
    #
    #       debug "rep: #{rep} #{rep.class} #{rep & 0x00FFFFFF}"
    #       debug "rl: #{rl} #{rl.class}"
    #
    #       if (rl>0)
    #         ct=Array.new();
    #         io.on_recv(rl) do |chunk|
    #           ct = chunk.unpack("C*")
    #           debug "ct: #{ct.size}"
    #           result_cbk.call(Rserve::Packet.new(rep, ct))
    #         end
    #       else
    #         result_cbk.call(Rserve::Packet.new(rep, nil))
    #       end
    #     end
    #   end
    #
    #   def request_string(s)
    #     b=s.unpack("C*")
    #     sl=b.length+1;
    #     sl=(sl&0xfffffc)+4 if ((sl&3)>0)  # make sure the length is divisible by 4
    #     rq=Array.new(sl+5)
    #
    #     b.length.times {|i| rq[i+4]=b[i]}
    #     ((b.length)..sl).each {|i|
    #       rq[i+4]=0
    #     }
    #     set_hdr(DT_STRING,sl,rq,0)
    #     rq
    #   end
    #
    #   def request_int(par)
    #     rq=Array.new(8)
    #     set_int(par,rq,4)
    #     set_hdr(DT_INT,4,rq,0)
    #     rq
    #   end
    # end # Talker

    # class RServConnection < EventMachine::Connection
    #   attr_reader :rsrv_version
    #
    #   def initialize(opts = {})
    #     @buffer = nil # using StringIO doesn't seem to work with binary
    #
    #     @pending_queue = [] # keep track of size and callback waiting for incoming data
    #     state :waiting
    #
    #     @gracefully_closed = false
    #     @reconnect_retries = 0
    #     @immediate_reconnect = false
    #     @last_data_received_at = nil
    #
    #     # Process incoming header message
    #     on_recv(32) do |chunk|
    #       check_protocol(chunk)
    #     end
    #
    #   end
    #
    #   def ready?
    #     state? :initialized
    #   end
    #
    #   def on_new_state(&clbk)
    #     @on_new_state_clbk = clbk
    #     @on_new_state_clbk.call(@state) if clbk && @state
    #   end
    #
    #   def write(data)
    #     send_data(data)
    #   end
    #
    #   def on_recv(size, &cbk)
    #     @pending_queue << [size, cbk]
    #     _check_pending_queue
    #   end
    #
    #   def _check_pending_queue
    #     return unless (@pending_queue.length > 0 && @buffer)
    #     chunk_size, cbk = @pending_queue[0]
    #     return unless (@buffer.size >= chunk_size)
    #
    #     @pending_queue.shift # remove job from queue
    #     #puts ">>>>> buff: #{@buffer.size} chunk_len: #{chunk_size}"
    #     if @buffer.length > chunk_size
    #       chunk = @buffer[0, chunk_size]
    #       @buffer = @buffer[chunk_size .. -1]
    #     else
    #       chunk = @buffer
    #       @buffer = nil
    #     end
    #     cbk.call(chunk)
    #
    #     _check_pending_queue # maybe there is more to do
    #   end
    #
    #   # === INTERNAL ===
    #   def post_init
    #     state :connected
    #   end
    #
    #   def receive_data(data)
    #     #debug "Received #{data.length} bytes"
    #     #puts "INCOMING(#{data.length}): #{data} (buffer size: #{@buffer ? @buffer.length : 0})"
    #     @buffer = @buffer ? @buffer + data : data
    #     #puts "INCOMING2 buffer size: #{@buffer.size}"
    #     _check_pending_queue
    #   end
    #
    #   # Check the first 32bits for
    #   def check_protocol(data)
    #     input = data.unpack("a4a4a4a4a4a4a4a4")
    #     #puts "CHECK: #{input.inspect}"
    #     unless input[0] == "Rsrv"
    #       raise Rserve::Connection::IncorrectServerError, "Handshake failed: Rsrv signature expected, but received [#{input[0]}]"
    #     end
    #     @rsrv_version = input[1].to_i
    #     if @rsrv_version > 103
    #       raise Rserve::Connection::IncorrectServerVersionError, "Handshake failed: The server uses more recent protocol than this client."
    #     end
    #     @protocol = input[2]
    #     if @protocol != "QAP1"
    #       raise Rserve::Connection::IncorrectProtocolError, "Handshake failed: unsupported transfer protocol #{@protocol}, I talk only QAP1."
    #     end
    #     (3..7).each do |i|
    #       # TODO: This is most likely going to fail miserably
    #       attr=input[i]
    #       if (attr=="ARpt")
    #         if (!auth_req) # this method is only fallback when no other was specified
    #           auth_req=true
    #           auth_type = Rserve::Connection::AT_plain
    #         end
    #       end
    #       if (attr=="ARuc")
    #         auth_req=true
    #         authType = Rserve::Connection::AT_crypt
    #       end
    #       if (attr[0]=='K')
    #         key=attr[1,3]
    #       end
    #
    #     end
    #     state :initialized
    #   end
    #
    #
    #
    #
    #   def state(new_state = nil)
    #     if new_state && @state != new_state
    #       @state = new_state
    #       @on_new_state_clbk.call(state) if @on_new_state_clbk
    #     end
    #     @state
    #   end
    #
    #   # Return true if current state is equal 'sate'
    #   def state?(state)
    #     @state == state
    #   end
    # end
  end
end

