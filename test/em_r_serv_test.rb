
module LabWiki
  module Plugin
    module R; end
  end
end


require 'pp'
require "eventmachine"
require 'rserve'

require 'labwiki/plugin/r/rserve_session'
OMF::Base::Loggable.init_log 'r_serve_test'


def run(prompt = '>>')
  #sleep (delay = 5 * rand)
  session = LabWiki::Plugin::R::RSession.new

  cmd = 'boxplot(decrease ~ treatment, data=OrchardSprays)'
  cmd = 'x <- rnorm(1)'
  #cmd = 'OrchardSprays'
  cmd = 'x <- 1'
  eval(cmd, session)
  eval('x', session)
  eval('x <- 1; x', session)
end

def eval(cmd, session)
  session.eval_cmd_line cmd do |state, res|
    puts ">> #{state}: #{res}"
    if state == :ok
      r = res.to_ruby
      puts "RES: class: #{r['class']} type: #{r['type']} msg: #{r['msg']} svg: #{r['svg'].nil?.!}"
    end
  end
end

def run2(prompt = '>>')
  con = Rserve::Connection.new
  x = con.eval('x <- rnorm(1)')
  puts "#{prompt} #{x} -- #{x.to_ruby}"
end

def run_em
  EM.run do
    1.times do |i|
      Fiber.new do
        run("P#{i}>>")
      end.resume
    end
  end
end

run_em
#run2

