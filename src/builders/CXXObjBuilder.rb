require 'Builder'

#build a C or C++ object file (the only difference is in the compiler flags)
class CXXObjBuilder < Builder

	public
	
	#params we use:
	#  :name => abs module Pathname
	#  :src => abs source file Pathname
	def initialize(params)
		super
		modname = Pathname.new(requireParam(params, :name))
		@srcfile = Pathname.new(requireParam(params, :src))
		
		entityType, modbase = BuildEnv::entityTypeSafe(@srcfile)
		@srctype = entityType #:c | :cxx

		#put something in our target list so base-class functions will know our target dir
		addTarget BuildEnv::srcOrBuild2build(System::mod2obj(modname))

		addPrereq @srcfile
		
		#set immediate link-time dependences for this module (needs to be done at construction time rather than build time so when objects set each
		# other as prereqs at build time, headers will already know their immediate link deps, so objects with compile-time dependence on those
		# headers can find their own link deps)
		hdrfiles = BuildEnv::findHeadersForModule(modname) #array of abs Pathnames
		hdrfiles.each {|filepath| BuildEnv::addLinkDeps filepath, target()}

		#make sure we don't parse the source file for dependences until it's been built if necessary
		task Builder::updateDepsTaskName(target()) => @srcfile
		
		#this needs to be a non-file task because it has to call the include parser to know what files to figure out whether the includes-list file is up to date with respect to
		#make sure include-parsing is always run when someone requests that our object file be built or cleaned, so our targets have correct dep graphs
		# (don't use addPrereq() for this first one, because it wouldn't create a rake-task dependence, since the parse-includes task isn't a built entity)
		task Builder::cleanAllTaskName(target()) => Builder::updateDepsTaskName(target())
	end

	#set @uptodateFilepaths to be an array of filenames we need the object file to be uptodate with respect to
	#return: none
	def parseIncludes()
		#figure out include deps
		filepaths = BuildEnv::parseHeaderDeps(self, @srcfile)
		#canonicalize paths
		filepaths = filepaths.map {|filepath| canonicalizeFilepath(filepath, Pathname.pwd())}
		#setting these headers as build and link deps couldn't happen at construction time, so it should happen now
		filepaths.each {|filepath| addPrereq filepath}
		#we'll check up-to-dateness against the source file, the file listing our header deps, and those headers
		@uptodateFilepaths = filepaths + [@srcfile, BuildEnv::getIncludeDepListFilepath(@srcfile)]
	end
	
	#update dependences (in BuildEnv and in rake) as necessary at build time
	#return: whether we're done updating and can progress to actual build steps
	def updateDeps(rakeTask)
		parseIncludes()
	end
	
	#run build commands
	#return: none
	#pre: parseIncludes() has been run so that @uptodateFilepaths is up to date
	def build(rakeTask)
		unless FileUtils.uptodate?(target(), @uptodateFilepaths) #the check rake does always fails because it includes non-file prereq tasks, so do our own
			cxxCompiler().compileCXX(:src => @srcfile, :target => target())
		end
	end
	
	#run commands to clean our targets and everything we depend on to build
	def cleanall(rakeTask)
		clean()
	end

end
