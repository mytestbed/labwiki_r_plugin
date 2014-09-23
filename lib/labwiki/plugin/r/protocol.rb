
module LabWiki::Plugin::R
  class Protocol < OMF::Base::LObject
    include Rserve::Protocol

    attr_reader :io

    def initialize(io)
      @io = io
    end

    def ready?
      io.ready?
    end

    def debug(*args)
      super if RSERVE_INTERNALS_DEBUG
    end

    # sends a request with attached prefix and  parameters.
    # All parameters should be enter on Hash
    # Both :prefix and :cont can be <code>nil</code>.
    #   Effectively <code>request(:cmd=>a,:prefix=>b,:cont=>nil)</code>
    #   and <code>request(:cmd=>a,:prefix=>nil,:cont=>b)</code> are equivalent.
    #
    # @param :cmd command - a special command of -1 prevents request from sending anything
    # @param :prefix - this content is sent *before* cont. It is provided to save memory copy operations
    #                  where a small header precedes a large data chunk (usually prefix conatins
    #                  the parameter header and cont contains the actual data).
    # @param :cont contents
    # @param :offset offset in cont where to start sending (if <0 then 0 is assumed, if >cont.length then no cont is sent)
    # @param :len number of bytes in cont to send (it is clipped to the length of cont if necessary)
    # @return returned packet or <code>null</code> if something went wrong */
    #
    def request(params=Hash.new, &result_cbk)

      cmd     = params.delete :cmd
      prefix  = params.delete :prefix
      cont    = params.delete :cont
      offset  = params.delete :offset
      len     = params.delete :len

      if cont.is_a? String
        cont=request_string(cont)
      elsif cont.is_a? Integer
        cont=request_int(cont)
      end
      raise ArgumentError, ":cont should be an Enumerable" if !cont.nil? and !cont.is_a? Enumerable
      if len.nil?
        len=(cont.nil?) ? 0 : cont.length
      end

      offset||=0


      if (!cont.nil?)
        raise ":cont shouldn't contain anything but Fixnum" if cont.any? {|v| !v.is_a? Fixnum}
        if (offset>=cont.length)
          cont=nil;len=0
        elsif (len>cont.length-offset)
          len=cont.length-offset
        end
      end
      offset=0 if offset<0
      len=0 if len<0
      contlen=(cont.nil?) ? 0 : len
      contlen+=prefix.length if (!prefix.nil? and prefix.length>0)

      hdr=Array.new(16)
      set_int(cmd,hdr,0)
      set_int(contlen,hdr,4);
      8.upto(15) {|i| hdr[i]=0}
      if (cmd!=-1)
        io.write(hdr.pack("C*"))
        if (!prefix.nil? && prefix.length>0)
          io.write(prefix.pack("C*"))
          debug "SEND PREFIX #{prefix}"
        end
        if (!cont.nil? and cont.length>0)
          debug "SEND CONTENT #{cont.slice(offset, len)} (#{offset},#{len})"
          io.write(cont.slice(offset, len).pack("C*"))
        end
      end

      io.on_recv(16) do |chunk|
        #"Expecting 16 bytes..." if $DEBUG
        ih = chunk.unpack("C*")
        if (ih.length != 16)
          debug "Received #{ih.length} of expected 16."
          result_cbk.call(nil)
          return
        end
        debug "Answer: #{ih.to_s}"

        rep=get_int(ih, 0);
        rl =get_int(ih,4);

        debug "rep: #{rep} #{rep.class} #{rep & 0x00FFFFFF}"
        debug "rl: #{rl} #{rl.class}"

        if (rl>0)
          ct=Array.new();
          io.on_recv(rl) do |chunk|
            ct = chunk.unpack("C*")
            debug "ct: #{ct.size}"
            result_cbk.call(Rserve::Packet.new(rep, ct))
          end
        else
          result_cbk.call(Rserve::Packet.new(rep, nil))
        end
      end
    end

    def request_string(s)
      b=s.unpack("C*")
      sl=b.length+1;
      sl=(sl&0xfffffc)+4 if ((sl&3)>0)  # make sure the length is divisible by 4
      rq=Array.new(sl+5)

      b.length.times {|i| rq[i+4]=b[i]}
      ((b.length)..sl).each {|i|
        rq[i+4]=0
      }
      set_hdr(DT_STRING,sl,rq,0)
      rq
    end

    def request_int(par)
      rq=Array.new(8)
      set_int(par,rq,4)
      set_hdr(DT_INT,4,rq,0)
      rq
    end
  end # Talker

end