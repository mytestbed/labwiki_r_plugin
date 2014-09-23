
#require 'omf-web/theme/bright/widget_chrome'

module LabWiki::Plugin::R

  # Override some of the functionality of the text renderer defined in OMF::Web
  class ConsoleRenderer < Erector::Widget
    include OMF::Base::Loggable

    def initialize(widget, opts = {})
      super opts
      @opts = opts
      @wid = @opts[:wid] = "w#{widget.object_id}"
      opts[:output_source_id] = widget.output_source_id
      @widget = widget
    end

    def content
      link :href => '/resource/plugin/r/css/r_console.css', :rel => "stylesheet", :type => "text/css"

      div class: "r_console", id: @wid do
        div class: 'r_output_block' do
          div class: 'wrapper'
        end
        div class: 'r_input_block' do
          div '>', id: @wid + '_input_prompt', class: 'prompt'
          input class: 'input', spellcheck: false, type: 'text'
        end
        #rawtext @content
      end
      javascript %{
        require(['plugin/r/js/r_console', 'omf/data_source_repo'], function(console, ds) {
          #{@widget.output_proxy.to_javascript};
          console($('##{@wid}'), LW.execute_controller, #{@opts.to_json});
        });
      }
    end

    def title_info
      {
        img_src: "/resource/plugin/r/img/r_console32.png",
        title: "R Console",
        sub_title: @widget.r_version || 'Unknown'
      }
    end
  end

end # module
