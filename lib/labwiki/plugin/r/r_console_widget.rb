require 'labwiki/column_widget'
require 'labwiki/plugin/r/r_console_renderer'
require 'labwiki/plugin/r/rserve_session'

module LabWiki::Plugin::R

  # Allows editing a topology descrription
  #
  class ConsoleWidget < LabWiki::ColumnWidget

    attr_reader :output_source_id, :output_proxy
    renderer :r_console_renderer

    MAX_HISTORY = 30


    def initialize(column, config_opts, opts)
      unless column == :execute
        raise "Should only be used in ':execute' column"
      end
      super column, :type => :r_console

      @output_source_id = "r_console_#{self.object_id}"
      schema = [[:line_no, :int32], [:part_no, :int32], :input, :state, :type, :class, :output, :svg]
      #@output_table = OMF::OML::OmlIndexedTable.new @output_source_id, :line_no, schema, max_size: MAX_HISTORY
      @output_table = OMF::OML::OmlTable.new @output_source_id, schema, max_size: MAX_HISTORY
      OMF::Web::DataSourceProxy.register_datasource @output_table
      @output_proxy = OMF::Web::DataSourceProxy.for_source(:name => @output_table.name)[0]

      reset_session
    end

    def on_new(params, req)
      debug "on_new_console: '#{params}'"
      nil
    end

    def on_reset(params, req)
      debug "on_reset"
      @output_table.clear
      reset_session
      true
    end

    def on_eval_line(params, req)
      debug "EVAL - p: #{params}"
      input = params[:input]
      line_no = params[:line_no]

      @rsession.eval_cmd_line input do |state, res_r|
        incomplete = false
        if state == :ok
          res = res_r.to_ruby
          type = res['type']
          klass = res['class']
          msg = res['msg']
          output = _serialize_output(msg, type, klass)
            # /Error in parse.*unexpected end of input/
          if incomplete = (klass == 'try-error' && msg.match(/Error in parse.*unexpected end of input/))
            klass = 'incomplete-line'
          end
          debug "RES: class: #{klass} part_no: #{@part_no} type: #{type} output: #{output} svg: #{res['svg'].nil?.!}"
          @output_table << [line_no, @part_no, input, state, type, klass, output, res['svg']]
          if incomplete
            @part_no += 1
            raise IncompleteCommand.new
          else
            @part_no = 0
          end
        else
          puts "ERRROR>>>>> #{state} - #{res_r}"
        end
      end
      nil
    end

    def _serialize_output(msg, type, klass)
      res = {}
      if msg.is_a? Array
        if msg.respond_to? :names
          res[:names] = msg.names
        end
      end
      res[:val] = msg
      res #.to_json
    end

    def mime_type
      'R'
    end

    def r_version
      @rsession.version do |version|
        @output_table << [-1, 0, nil, nil, nil, nil, version, nil]
      end
    end

    def content_url
      nil
    end

    def reset_session
      @rsession.reset if @rsession
      @rsession = LabWiki::Plugin::R::RSession.new
      @part_no = 0
    end
  end # class

end # module
