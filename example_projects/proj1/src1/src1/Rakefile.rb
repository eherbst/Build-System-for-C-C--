Dir.chdir('../..') do require 'Rakefile.include' end
raker = Raker.new

raker.exe(:name => 'exec1', :mainmod => 'exec1_1')
