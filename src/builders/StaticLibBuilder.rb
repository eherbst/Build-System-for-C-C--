require 'Builder'

#since the build system knows what object files need to be linked into an executable, static libs aren't necessary within a project,
# but they're still useful as external libs for other projects
class StaticLibBuilder < Builder

	public
	
	#params we use:
	#  :name => abs module Pathname
	#  :modules => enumerable of abs module Pathnames
	def initialize(params)
		super
		basename = requireParam(params, :name)
		modpaths = requireParam(params, :modules)
		
		modpaths.each {|path| addPrereq BuildEnv::src2build(System::mod2obj(path))}
		addTarget BuildEnv::src2build(System::mod2slib(basename))
			
		#symlink from the src tree to the build tree (even if our target is up-to-date, in case the symlink currently points to a file built with 
		# different options, ie elsewhere in the build tree)
		SymlinkBuilder.new(:target => target(), :name => BuildEnv::build2src(target()))
		
		#flags for tasks that edit their own prereq lists before reinvoking themselves
		@cleanallRecurse = true #true before cleanall() is called from outside; false when it's called by itself
	end
	
	#update dependences (in BuildEnv and in rake) as necessary at build time
	#return: whether we're done updating and can progress to actual build steps
	def updateDeps(rakeTask)
		return true
	end

	#run build commands
	#return: none
	def build(rakeTask)
		filePrereqs = filePrereqs() #remove internal build-system stuff
		unless FileUtils.uptodate?(target(), filePrereqs) #the check rake does always fails because it includes a non-file prereq task
			staticLibMaintainer().addOrUpdate(:lib => target(), :objs => filePrereqs)
			staticLibMaintainer().index(target())
		end
	end
	
	#run commands to clean our targets
	def clean()
		System::clean target()
	end
	
	#run commands to clean our targets and everything we depend on to build
	def cleanall(rakeTask)
		if @cleanallRecurse
			@cleanallRecurse = false
			task rakeTask.name => prereqs().map {|entity| Builder::cleanAllTaskName(entity)}
			rakeTask.reenable()
			rakeTask.invoke() #run again, starting with our updated prereqs list
		else #we've called ourselves after updating prereqs and running them; now do our work
			clean()
		end
	end
	
end
