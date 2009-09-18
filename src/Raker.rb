######################################################################################
#one Raker per directory; created in rakefiles
#any cleaning of pathnames from outside this file is done in this class (ie there might not be any done, but if you want to add it, do that here)
class Raker

	private

#not currently used -- EVH 20090114
#
#	#do processing to a nested array (at any level, each element could be an array or not)
#	#thing: element or nested array
#	#f: function to operate on each non-array element
#	#return: result of processing each non-array element, in the same nested-array structure
#	def processNestedArray(thing, f)
#		case thing
#			when Array: return thing.map {|element| processNestedArray(element, f)}
#			else return f.call(thing)
#		end
#	end
	
##### for the use of Builders #####

	public
	
	#let this directory's Raker know about items in this dir that get built (useful, eg, when deciding what needs to be cleaned)
	#entity: entity spec
	#builder: the Builder for the given entity
	#return: none
	def registerBuiltEntity(entity, builder)
		#initialize project-wide tasks (initialize() also does some of this)
		unless BuildEnv::readingAuxiliary?()
			#create the task aliases the user will usually use, eg "test.o" for "/this/dir/test.o"
			whichTree = BuildEnv::whichProjectTree(entity)
			curdir = realdir(Pathname.pwd())
			case whichTree
				when :src then task :"#{entity.relative_path_from(curdir)}" => entity.to_s
				when :build then task :"#{entity.relative_path_from(BuildEnv::src2build(curdir))}" => entity.to_s
				when :neither then raise "entity '#{entity.to_s}' to be built is in neither source nor build tree -- build system error"
			end
			
			task :clean => Builder::cleanTaskName(entity) #the prereqs (created by Builders) do all the work
			task :'clean-all' => Builder::cleanAllTaskName(entity) #the prereqs (created by Builders) do all the work
			task :all => entity.to_s
		end
	end
	
##### for rakefile use #####

	public
	
	#params we use:
	#  :subtree => <anything> -- the calling rakefile builds its entire filesystem subtree, not just its dir
	#any other params we get are passed on to set()
	def initialize(*params)
		BuildEnv::setRaker self, Pathname.pwd()
		
		#target-specific build process customizations (see Raker::customize())
		@buildCustomizations = [] #array of {:filter => filter function taking entity spec for target, :... => various customizing functions for that target}
		
		#parse params (which is an array) and pass what we don't use along
		searchSubdirs = false
		if !params.empty?()
			params = params[0] #extract the named-param hash from the array
			if params.has_key?(:subtree)
				searchSubdirs = true
				params.delete(:subtree)
			end
			unless params.empty?()
				set(params)
			end
		end
		
		#set us as the raker for all dirs in our subtree if requested
		if searchSubdirs
			Pathname.glob("**/*").select {|p| p.directory?}.each {|reldir| BuildEnv::setRaker self, Pathname.pwd().join(reldir)}
		end
		
		#auto-create builders for file types we know about
		allFiles = searchSubdirs ? Dir.glob(File.join('**', '*')) : Dir.entries(Pathname.pwd()) #enumerable of filename strings relative to this dir
		realpwd = Pathname.pwd().realpath() #visit the filesystem to clean up the string if nec
		allFiles = allFiles.map {|filename| realpwd.join(filename)}.select {|pathname| !pathname.directory?()} #enumerable of Pathnames; non-directory files only
		allFiles.each do |filepath|
			type, modbase = BuildEnv::entityTypeSafe(filepath)
			case type
				when :c, :cxx then CXXObjBuilder.new(:name => removeExt(filepath), :src => filepath)
				when :f then FObjBuilder.new(:name => removeExt(filepath), :src => filepath)
			end
		end
		
		#initialize project-wide tasks (registerBuiltEntity() also does some of this)
		unless BuildEnv::readingAuxiliary?()
			task :default => :all #:default is a special name to rake; it's what happens when you don't specify a task
		end
	end
	
	#set various dir-wide things
	#params we use:
	#  :libs => libsym or array of them to be used by all files built by this file
	#pre: there's at least one argument
	def set(*params)
		params = params[0] #extract the named-param hash from the array
		params.each do |key, val|
			case key
				when :libs then
					libsyms = ensureArray(val)
					customize(:cxxcmp => lambda {|cxxcmp| libsyms.each {|libsym| cxxcmp.addIncludeDirs(ExtlibRegistry::incdirsForLib(libsym))}}) #add a customization for all targets in our dir(s)
				else raise "Raker::set(): unrecognized param #{key}" 
			end
		end
	end
	
	#return all build customizations in this raker that are appropriate for the given builder
	#return: array of hashes of the form created by customize() and put in @buildCustomizations
	def buildCustomizations(builder)
		return @buildCustomizations.select {|c| c[:filter].call(builder)}
	end
	
	#customize the build process for specified targets
	#params we use:
	# targetspecs in order of precedence (the first one found is used; if none found, use :targets => :all):
	#  :targets (optional; default all in cur dir) -> string/regex or enumerable of those for filenames (rel to cwd)
	#  :prereqs (optional; no default) -> string/regex or enumerable of those for filenames (rel to cwd)
	#  :type (optional; no default) -> entity type symbol to be compared to target type
	#  :pretype (optional; no default) -> entity type symbol to be compared to prereq types (must match one or more)
	# customization of build for selected targets/prereqs:
	#  :cxxcmp (optional) -> function that takes a CXXCompiler and edits it
	#  :fcmp (optional) -> function that takes a FortranCompiler and edits it
	#  :ldcmp (optional) -> function that takes a Linker and edits it
	#  :slibmnt (optional) -> function that takes a StaticLibMaintainer and edits it
	#
	#the editing functions for a given target are run in the order in which they're given to this function
	def customize(params)
		targets = params.has_key?(:targets) ? ensureArray(params[:targets]) : nil
		prereqs = params.has_key?(:prereqs) ? ensureArray(params[:prereqs]) : nil
		type = params[:type] || nil
		pretype = params[:pretype] || nil
		cxxCompilerXform = params[:cxxcmp] || nil
		fortranCompilerXform = params[:fcmp] || nil
		linkerXform = params[:ldcmp] || nil
		staticLibMaintainerXform = params[:slibmnt] || nil
		
		#create a filter to select build items for which to apply the changes
		if targets
			targets.each do |tgtspec|
				case tgtspec
					when String then filter = lambda {|builder| builder.target().to_s == tgtspec}
					when Regexp then filter = lambda {|builder| builder.target().to_s =~ tgtspec}
					else raise "unhandled type '#{tgtspec.class}' of tgtspec (user error)"
				end
			end
		elsif prereqs
			prereqs.each do |prespec|
				case prespec
					when String then filter = lambda {|builder| !builder.prereqs().select {|entity| entity.to_s == prespec}.empty?()}
					when Regexp then filter = lambda {|builder| !builder.prereqs().select {|entity| entity.to_s =~ prespec}.empty?()}
					else raise "unhandled type '#{prespec.class}' of prespec (user error)"
				end
			end 
		elsif type
			filter = lambda {|builder| BuildEnv::entityTypeSafe(builder.target())[0] == type}
		elsif pretype
			filter = lambda {|builder| !builder.prereqs().select {|entity| BuildEnv::entityTypeSafe(entity)[0] == pretype}.empty?()}
		else
			filter = lambda {|builder| true}
		end
		
		@buildCustomizations.push({:filter => filter, 
											:cxxcmp => cxxCompilerXform, 
											:fcmp => fortranCompilerXform, 
											:ldcmp => linkerXform, 
											:slibmnt => staticLibMaintainerXform
											})
	end
	
	#associate each specified header with the specified source file(s) (which means the header will pull in the module(s) at link time)
	# (in addition to any others it's already associated with via this function or otherwise)
	#a header can be associated with multiple modules; uncool but some weird libraries require it
	#params: enumerable with each element of the form 'hdr_filename.h' => ['src_filename.cpp', ...] (rel-to-cwd and abs paths allowed)
	def associate(params)
		params.each do |hdrfile, srcfiles|
			hdrfile = canonicalizeFilepath(Pathname.new(hdrfile), Pathname.pwd())
			srcfiles = canonicalizeFilepaths(srcfiles.map {|filepath| Pathname.new(filepath)}, Pathname.pwd())
			srcfiles.each do |srcfile|
				type, modbase = BuildEnv::entityType(srcfile)
				BuildEnv::addLinkDeps hdrfile, BuildEnv::srcOrBuild2build(System::mod2obj(srcfile.dirname().join(modbase)))
			end
		end 
	end
	
	#declare a static library built as part of the project (in case we want to use part of this project as an external lib for another project)
	#params we use:
	#  :sym => symbol for this lib
	#  :name (optional; default params[:sym]) => filenamebase
	#  :modules => enumerable of abs or rel module paths (to which .o will be appended)
	def lib(params)
		sym = requireParam(params, :sym)
		name = canonicalizeFilepath(Pathname.new(params[:name] || sym.to_s), Pathname.pwd())
		modules = requireParam(params, :modules)
		modules = canonicalizeFilepaths(modules.map {|modpath| Pathname.new modpath}, Pathname.pwd())
		StaticLibBuilder.new(:name => name, :modules => modules)
	end
	
	#declare an executable
	#params we use:
	#  :name => executable filenamebase (with relative (to cwd) path if desired)
	#  :mainmod (optional; default params[:name]) => abs or rel module path of main module (to which the appropriate extension will be appended)
	def exe(params)
		if !BuildEnv::readingAuxiliary?() #don't waste time processing executables in auxiliary dirs
			name = requireParam(params, :name)
			name = canonicalizeFilepath(Pathname.new(name), Pathname.pwd())
			mainmod = params.has_key?(:mainmod) ? canonicalizeFilepath(Pathname.new(params[:mainmod]), Pathname.pwd()) : name
			ExeBuilder.new(:name => name, :mainmod => mainmod)
		end
	end
	
	#declare a file to be put through the Qt preprocessor, MOC
	#params: hash of (moc input filename: (abs or rel to cwd) String or Pathname => moc output filename: (abs or rel to cwd) String or Pathname)
	#        and the (optional) entry :mocpath => abs path (String or Pathname) to moc executable, including filetitle
	def moc(params)
		mocpath = Pathname.new('moc') #default: assume it's in the PATH
		if params[:mocpath]
			mocpath = params[:mocpath]
			params.delete(:mocpath)
		end
		params.each_pair do |inpath, outpath|
			inpath = canonicalizeFilepath(Pathname.new(inpath), Pathname.pwd())
			outpath = canonicalizeFilepath(Pathname.new(outpath), Pathname.pwd())
			QtMocBuilder.new(:input => inpath, :output => outpath, :mocpath => mocpath)
		end
	end
	
	#declare a generated source file (which can be a header)
	#params we use:
	#  :inputs => abs or rel (to cwd) filename or array of them listing the command's input files
	#  :cmd => command to run
	#  :output => abs or rel (to cwd) filename or array of them listing the command's output files
	#(all other params passed along)
	def gen_src(params)
		inputs = ensureArray requireParam(params, :inputs)
		inputs = canonicalizeFilepaths(inputs.map {|filepath| Pathname.new(filepath)}, Pathname.pwd())
		cmd = requireParam(params, :cmd)
		outputs = ensureArray requireParam(params, :output)
		outputs = canonicalizeFilepaths(outputs.map {|filepath| Pathname.new(filepath)}, Pathname.pwd())
		params[:inputs] = inputs
		params[:cmd] = cmd
		params[:output] = outputs
		GeneratedSourceBuilder.new(params)
		#if we're generating non-header source, also autocreate an object module builder for it
		outputs.each do |filepath|
			type, modbase = BuildEnv::entityTypeSafe filepath
			case type
				when :c, :cxx then CXXObjBuilder.new(:name => removeExt(filepath), :src => filepath)
				when :f then FObjBuilder.new(:name => removeExt(filepath), :src => filepath)
			end
		end
	end

end
