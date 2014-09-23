source 'https://rubygems.org'

def override_with_local(opts)
  local_dir = opts.delete(:path)
  unless local_dir.start_with? '/'
    local_dir = File.join(File.dirname(__FILE__), local_dir)
  end
  #puts "Checking for '#{local_dir}' - #{Dir.exist?(local_dir)}"
  Dir.exist?(local_dir) ? {path: local_dir} : opts
end

#gem "rserve-client"
gem "omf_oml", override_with_local(path: '../rserve_ruby_client', github: 'maxott/Rserve-Ruby-client') # branch => '2-3-stable'


