
$DEBUG = true

require 'pp'
require 'rserve'


def run2(cmd, prompt = '>>')
  con = Rserve::Connection.new
  x = con.eval(cmd)
  p "#{prompt}: #{x.to_ruby}"
end

#run2 'x <- rnorm(1)'
run2('complex(real = 2, imaginary = 1)').methods.sort