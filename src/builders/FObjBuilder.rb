require 'Builder'

#build a fortran object file
class FObjBuilder < Builder

	public
	
	#params we use:
	#  :name => abs module Pathname
	#  :src => abs source file Pathname
	def initialize(params)
		super
		modname = Pathname.new(requireParam(params, :name))
		@srcfile = Pathname.new(requireParam(params, :src))

		#put something in our target list so base-class functions will know our target dir
		addTarget BuildEnv::src2build(System::mod2obj(modname))

		addPrereq @srcfile
	end
	
	#update dependences (in BuildEnv and in rake) as necessary at build time
	#return: whether we're done updating and can progress to actual build steps
	def updateDeps(rakeTask)
		raise "Evan doesn't know enough about the fortran build process to implement this"
	end
	
	#run build commands
	#return: none
	def build(rakeTask)
		fortranCompiler().compileFortran(:src => @srcfile, :target => target())
	end
	
	#run commands to clean our targets and everything we depend on to build
	def cleanall(rakeTask)
		clean()
	end

end

