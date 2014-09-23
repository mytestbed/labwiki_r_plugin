
module LabWiki::Plugin
  module R; end
end

require 'labwiki/plugin/r/r_console_widget'

#LabWiki::Plugin::Topology::SliceServiceProxy.instance # Validate configuration

#OMF::Web::ContentRepository.register_mime_type(gjson: 'text/topology')

LabWiki::PluginManager.register :r, {
  version: LabWiki.plugin_version([0, 1, 'pre'], __FILE__),

  widgets: [
    # {
      # :name => 'r',
      # :context => :execute,
      # :priority => lambda do |opts|
        # (opts[:url].end_with? '.rspec') ? 500 : nil
      # end,
      # :search => lambda do |pat, opts, wopts|
        # opts[:mime_type] ||= 'text/topology'
        # OMF::Web::ContentRepository.find_files(pat, opts)
      # end,
      # :widget_class => LabWiki::Plugin::Topology::TopologyEditorWidget,
      # :handle_mime_type => 'text/topology'
    # },
    {
      :name => 'r/console',
      :context => :execute,
      :widget_class => LabWiki::Plugin::R::ConsoleWidget,
      #:handle_mime_type => 'topology'
    }
  ],
  renderers: {
    :r_console_renderer => LabWiki::Plugin::R::ConsoleRenderer,
  },
  resources: File.dirname(__FILE__) + '/resource',
  global_js: 'js/r_global.js',

  # on_authorised: lambda do
    # speaks_for = OMF::Web::SessionStore[:speak_for, :user]
    # user = OMF::Web::SessionStore[:urn, :user]
    # LabWiki::Plugin::Topology::SliceServiceProxy.instance.speaks_for_user(user, speaks_for)
  # end

}
