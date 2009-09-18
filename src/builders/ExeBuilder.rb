require 'Builder'

class ExeBuilder < Builder

	private
	
	#return: an array of our link-time dependences in correct order for the link line
	def linkDepsOrdered()
		tempLinkDeps = BuildEnv::allLinkDepsOrdered(target()) - targets().to_a #in correct order for the link line
		#remove project-internal static libs; since the object files we need are in our list anyway, we never need to include intlibs in executables
		finalLinkDeps = tempLinkDeps.select {|entity| BuildEnv::entityTypeSafe(entity)[0] != :intlib}
		return finalLinkDeps
	end
	
	#return: String
	def mainObjFilepath()
		return prereqs()[1]
	end

	public
	
	#params we use:
	#  :name (optional; default same as mainmod) => abs Pathname for output file
	#  :mainmod => abs module Pathname
	def initialize(params)
		super
		mainmod = Pathname.new(requireParam(params, :mainmod))
		basename = Pathname.new(params[:name] || mainmod.basename())
		
		prereqFile = BuildEnv::src2build(System::mod2obj(mainmod))
		addPrereq prereqFile
		addTarget BuildEnv::src2build(basename)
		
		#symlink from the src tree to the build tree (even if our target is up-to-date, in case the symlink currently points to a file built with 
		# different options, ie elsewhere in the build tree)
		SymlinkBuilder.new(:target => target(), :name => BuildEnv::build2src(target()))
		
		#flags for tasks that edit their own prereq lists before reinvoking themselves
		@cleanallRecurse = true #true before cleanall() is called from outside; false when it's called by itself
	end
	
	#update dependences (in BuildEnv and in rake) as necessary at build time
	#return: whether we're done updating and can progress to actual build steps
	def updateDeps(rakeTask)
		prevLinkDeps = []
		linkDeps = linkDepsOrdered() - [mainObjFilepath()]
		while !(linkDeps - prevLinkDeps).empty?()
			(linkDeps - prevLinkDeps).each do |dep|
				if BuildEnv::isBuilt?(dep)
					Rake::Task[Builder::updateDepsTaskName(dep)].invoke()
				end
			end
			prevLinkDeps = linkDeps
			linkDeps = linkDepsOrdered() - [mainObjFilepath()]
		end

		linkDeps.each {|dep| addPrereq dep}
		buildTask = Rake::Task["#{target()}"]
		buildTask.reenable()
		buildTask.invoke() #run again, starting with our updated prereqs list
	end
	
	#run build commands
	#return: none
	def build(rakeTask)
		#we've called ourselves after updating prereqs and running them; now do our work
		
		filePrereqs = filePrereqs() #remove internal build-system stuff
		unless FileUtils.uptodate?(target(), filePrereqs) #the check rake does always fails because it includes non-file prereq tasks, so do our own
			linker().link(:objs => linkDepsOrdered(), :target => target())
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
			linkDepsOrdered().select {|entity| BuildEnv::isBuilt?(entity)}.each do |entity|
				task rakeTask.name => Builder::cleanAllTaskName(entity)
			end
			rakeTask.reenable()
			rakeTask.invoke() #run again, starting with our updated prereqs list
		else #we've called ourselves after updating prereqs and running them; now do our work
			clean()
		end
	end

end
