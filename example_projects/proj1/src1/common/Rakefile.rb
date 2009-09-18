Dir.chdir('../..') do require 'Rakefile.include' end
raker = Raker.new

raker.gen_src(:inputs => 'generate.rb', :cmd => 'ruby generate.rb > generated.h', :output => 'generated.h')
