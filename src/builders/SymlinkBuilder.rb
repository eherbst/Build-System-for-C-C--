require 'Builder'

class SymlinkBuilder < Builder

	public
	
	#params we use:
	#  :name => abs Pathname
	#  :target => abs Pathname
	def initialize(params)
		super
		@linkName = requireParam(params, :name)
		@target = requireParam(params, :target)
		
		addPrereq @target
		addTarget @linkName
	end
	
	#update dependences (in BuildEnv and in rake) as necessary at build time
	#return: whether we're done updating and can progress to actual build steps
	def updateDeps(rakeTask)
		return true
	end
	
	#run build commands
	#return: none
	def build(rakeTask)
		System::symlink @linkName => @target
	end
	
	#run commands to clean our targets
	def clean()
		System::clean @linkName
	end
		
end
