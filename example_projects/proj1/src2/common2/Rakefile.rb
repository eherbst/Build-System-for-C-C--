Dir.chdir('../..') do require 'Rakefile.include' end
raker = Raker.new

raker.associate 'header.h' => ['A.cpp', 'B.cpp']
