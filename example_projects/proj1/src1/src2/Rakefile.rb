Dir.chdir('../..') do require 'Rakefile.include' end
raker = Raker.new

raker.exe(:name => 'exec2', :mainmod => 'exec2_1')
raker.exe(:name => 'exec2_2')
