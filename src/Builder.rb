class Builder

	private

	#get the raker in our dir
	#return: Raker
	def raker()
		return BuildEnv::raker(dir())
	end
	
	#run build commands, assuming dep-graph updating is done
	#return: none
	def buildAux(rakeTask)
		build(rakeTask)
	end
	
	#update dependences (in BuildEnv and in rake) as much as necessary at build time
	#return: none
	def updateDeps(rakeTask)
		raise 'to be implemented by subclasses'
	end
	
	#run build commands
	#return: none
	def build(rakeTask)
		raise 'to be implemented by subclasses'
	end
	
	#to be called before building: set up the build environment and rake properly once we know all our targets and at least some prereqs
	#return: none
#	def finalizeInit()
#		#to make sure our build commands will only be run once, we register them for only one of our targets
#		target0 = @targets.shift
#		
#		#ensure all targets other than the first will also get built
#		@targets.each {|entity| file entity.to_s => target0.to_s}
#		@targets.unshift target0
#		
#		#if a target gets linked, we also need to make sure things that get included in it are built before it
#		@targets.each do |target|
#			if BuildEnv::isLinked?(target)
#				file target.to_s => (BuildEnv::allLinkDeps(target) - [target]).select {|entity| BuildEnv::isBuilt?(entity)}.map {|entity| entity.to_s}
#			end
#		end
#	end
	
	#define what this entity does when asked to :clean (meant to be overridden)
	#:clean means clean your own targets (so overriding should rarely be necessary)
	def clean()
		System::clean targets()
	end
	
	#define what this entity does when asked to :clean-all (meant to be overridden)
	#:clean-all means clean yourself and everything you depend on to be built
	def cleanall(rakeTask)
		clean()
	end

	public
	
	#params we use: (none)
	def initialize(params)
		#these need to be arrays or similar since sometimes I want to get some--any--element and there's no nice Set equivalent for [0] -- EVH
		@prereqs = [] #enumerable of entity specs
		@targets = [] #enumerable of entity specs
		
		#holders for functions that will customize the build process for our target(s)
		@cxxCustomizations = []
		@fortranCustomizations = []
		@linkerCustomizations = []
		@slibMaintainerCustomizations = []
		
		@buildRecurse = -1 #see buildAux() and/or updateDepsAux() for how this is used
	end
	
	#for now, return the dir of our first target; assume no builder is creating things in multiple dirs, since that's a little weird
	#pre: !targets().empty?()
	#return: Pathname
	def dir()
		raise "dir() called on a Builder with no target set yet" if targets().empty?()
		return targets()[0].dirname()
	end
	
	#return: enumerable of entity specs
	def prereqs()
		return @prereqs
	end
	
	private
	
	#entity: entity spec
	#return: whether the entity spec, which is a prereq of ours, refers to a file
	def prereqIsFile?(entity)
		return entity.class != Symbol
	end

	# returns a prefix to be used to create internal task names from
	# normal task names
	#return: String
	def self.internalTaskPrefix()
		return "~INTERNAL_"
	end
	
	public
	
	#get all prereqs that represent files
	#return: enumerable of entity specs
	def filePrereqs()
		return prereqs().select {|entity| prereqIsFile?(entity)}
	end
	
	#add entity as a prereq for this builder if we haven't already done so
	#entity: entity spec
	#return: none
	def addPrereq(entity)
		return if @prereqs.index(entity) != nil #"if we haven't already done so"
	
		#update data structures
		if prereqIsFile?(entity)
			BuildEnv::ensureRakefileRead(canonicalizeDir(Pathname.new(entity.dirname()), Pathname.pwd())) #read the rakefile controlling the entity's dir if we haven't already
		end
		
		#set up dependences for our system
		if prereqIsFile?(entity)
			#add prereqs to one target, which will in turn be a prereq for our other targets
			BuildEnv::addBuildPrereq target(), entity 
			BuildEnv::addLinkDeps target(), entity
		end
		
		#set up dependences for rake (these will be actual rake tasks; no point creating rake tasks for entities we know we don't need to build)
	#	if BuildEnv::isBuilt?(entity) #changed 20090427 to the below line
		if !entity.is_a?(Symbol) && (BuildEnv::entityTypeSafe(entity)[0] != :h || BuildEnv::isBuilt?(entity))
			@prereqs.push entity
			
			if !@targets.empty?()
				task target().to_s => entity.to_s #add prereqs to our existing main rake task
			end
		end
	end
	
	#return: enumerable of entity specs
	def targets()
		return @targets
	end
	#convenience: many builders have only one target
	#return: entity spec
	def target()
		return @targets[0]
	end
	
	#add entity as a target for this builder if we haven't already done so
	#entity: entity spec
	#return: none
	def addTarget(entity)
		return if @targets.index(entity) != nil #"if we haven't already done so"
	
		#update data structures
		if entity.is_a?(Pathname)
			BuildEnv::ensureRakefileRead(entity.dirname()) #read the rakefile controlling the entity's dir if we haven't already
		end
		@targets.push entity
		
		#set up dependences
		if @targets.size() == 1 #this is the first target registered for this builder; we'll set our prereqs as prereqs for one rake target, then
										# set this rake target as a prereq for the rest of our targets
			filePrereqs = filePrereqs()
			BuildEnv::addBuildPrereq entity, filePrereqs 
			BuildEnv::addLinkDeps entity, filePrereqs
		end
		
		#create target-specific tasks used within the build system
		task Builder::cleanTaskName(entity) do
			clean()
		end
		task Builder::cleanAllTaskName(entity) do |t|
			cleanall(t)
		end
		
		#if the target is a file, also create *user-level* tasks to clean it
		if(entity.is_a?(Pathname))
			task :"clean_#{entity.basename()}" do
				Pathname.delete entity
			end
			
			task :"clean-all_#{entity.basename()}" => Builder::cleanAllTaskName(entity)
		end
				
		#give the raker the info it needs to set up project-wide tasks, eg :all, :clean
		raker().registerBuiltEntity entity, self
		
		#create a rake task as a handle for us to run our dependence-graph-updating code at build time
		if @targets.size() == 1 #this is the first target registered for this builder (we only want to register the task for one target)
			task Builder::updateDepsTaskName(entity) do |t|
				updateDeps(t)
			end
			file entity.to_s => (@prereqs.map {|prereq| prereq.to_s} + [Builder::updateDepsTaskName(entity)]) do |t| #we'll add more prereqs later through addPrereq()
				System::createPath entity.dirname().to_s #create the dir if it doesn't exist
				buildAux(t)
			end
		end
	end
	
##### customize our build process
	
	public

	#add target-specific options to a default compiler
	#return: CXXCompiler
	def cxxCompiler()
		compiler = BuildEnv::cxxCompiler()
		@cxxCustomizations = raker().buildCustomizations(self) if @cxxCustomizations.empty?
		@cxxCustomizations.each {|f| if f[:cxxcmp] then f[:cxxcmp].call(compiler) end}
		return compiler
	end
	
	#add target-specific options to a default compiler
	#return: FortranCompiler
	def fortranCompiler()
		compiler = BuildEnv::fortranCompiler()
		@fortranCustomizations = raker().buildCustomizations(self) if @fortranCustomizations.empty?
		@fortranCustomizations.each {|f| if f[:fcmp] then f[:fcmp].call(compiler) end}
		return compiler
	end
	
	#add target-specific options to a default compiler
	#return: Linker
	def linker()
		compiler = BuildEnv::linker()
		@linkerCustomizations = raker().buildCustomizations(self) if @linkerCustomizations.empty?
		@linkerCustomizations.each {|f| if f[:ldcmp] then f[:ldcmp].call(compiler) end}
		return compiler
	end
	
	#add target-specific options to a default lib maintainer
	#return: StaticLibMaintainer
	def staticLibMaintainer()
		compiler = BuildEnv::staticLibMaintainer()
		@slibMaintainerCustomizations = raker().buildCustomizations(self) if @slibMaintainerCustomizations.empty?
		@slibMaintainerCustomizations.each {|f| if f[:slibmnt] then f[:slibmnt].call(compiler) end}
		return compiler
	end

	#names of system-internal tasks for a given entity
	#return: Symbol
	def self.cleanTaskName(entity) return :"#{Builder::internalTaskPrefix()}clean_#{entity}" end
	def self.cleanAllTaskName(entity) return :"#{Builder::internalTaskPrefix()}cleanall_#{entity}" end
	def self.updateDepsTaskName(entity) return :"#{Builder::internalTaskPrefix()}updateDeps_#{entity}" end

end
