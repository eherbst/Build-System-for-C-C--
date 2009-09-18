#build-framework: C/C++-based-project build system framework using rake, the ruby make
#(to be extended, for each project, with a project-specific rakefile-header that's included by all rakefiles in that project;
# the rakefile-header can, eg, define things in BuildEnv, define new Builder subclasses and add factory functions to Raker)
#Evan Herbst, 4 / 17 / 08

require 'pathname'
$: << File.expand_path(File.dirname(__FILE__)) #add cwd to the search path so we can include the rest of the build system

#build system includes
require 'System'
require 'Compiler'
require 'compilers/GNU'
require 'ExtlibRegistry'

##### utils #####

#return params[symbol] or yell if it doesn't exist
def requireParam(params, symbol)
	return params[symbol] || raise("parameter :#{symbol} required")
end

#if arg isn't an array, put it in one (return the result)
def ensureArray(arg)
	return arg.is_a?(Array) ? arg : [arg]
end

#filepath: Pathname
#return: same Pathname minus extension if it had one
def removeExt(filepath)
	return filepath.sub(filepath.extname(), '')
end

#if dir isn't absolute, tack it on to basedir
#dir: Pathname
#basedir: Pathname
#return: Pathname
def absolutizeDir(dir, basedir)
	return dir.absolute? ? dir : basedir.join(dir)
end

#clean up by removing multiple separators, all ..s, etc (requires visiting the filesystem)
#dir: abs Pathname
#return: Pathname
def realdir(dir)
	return dir.realpath()
end

#absolutize and clean up by removing multiple separators, all ..s, etc (requires visiting the filesystem)
#dir: Pathname
#basedir: Pathname
#return: Pathname
def canonicalizeDir(dir, basedir)
	return realdir(absolutizeDir(dir, basedir))
end

#if filepath isn't absolute, tack it on to basedir
#filepath: Pathname
#basedir: Pathname
#return: Pathname
def absolutizeFilepath(filepath, basedir)
	return filepath.absolute? ? filepath : basedir.join(filepath)
end

#tack basedir onto the filepaths that aren't absolute
#filepaths: enumerable of Pathnames
#basedir: Pathname
#return: enumerable of Pathnames
def absolutizeFilepaths(filepaths, basedir)
	return filepaths.map {|filepath| absolutizeFilepath(filepath, basedir)}
end

#clean up by removing multiple separators, all ..s, etc (requires visiting the filesystem)
#filepath: abs Pathname
#return: Pathname
def realFilepath(filepath)
	return realdir(filepath.dirname()).join(filepath.basename())
end

#absolutize and clean up by removing multiple separators, all ..s, etc (requires visiting the filesystem)
#filepath: Pathname
#basedir: Pathname
#return: Pathname
def canonicalizeFilepath(filepath, basedir)
	abspath = absolutizeFilepath(filepath, basedir)
	return realdir(abspath.dirname()).join(abspath.basename())
end

#absolutize and clean up by removing multiple separators, all ..s, etc (requires visiting the filesystem)
#filepaths: enumerable of Pathnames
#basedir: Pathname
#return: enumerable of Pathnames
def canonicalizeFilepaths(filepaths, basedir)
	return filepaths.map {|filepath| canonicalizeFilepath(filepath, basedir)}
end

#paths: array of strings, Pathnames and FileLists
#return: array of Pathnames
def flattenPathArray(paths)
	return (
		paths.map do |item|
			case item
				when String then [Pathname.new(item)]
				when Pathname then [item]
				when FileList then item.to_a.map {|f| Pathname.new(f)}
				else raise "invalid type"
			end
		end
	).flatten()
end

#print the cmd, run the cmd and die if it failed (since rake doesn't seem to do that automatically)
#(meant to be used within rake task definitions)
#return: none
def printAndCall(cmd)
	puts cmd
	`#{cmd}`
	raise "command failed; killing rake" if $?.to_i != 0
end

#require() the file with an anonymous module wrapped around it so its local variable declarations become in fact local to that file
#filename: string or Pathname
def requireInNewModule(filename)
	m = Module.new #anonymous module
	infile = File.open(filename) {|fid| m.module_eval fid.readlines.join('')} #read and evaluate code	
end

######################################################################################
#project-wide build environment
#
#for projects involving compile and link stages, and possibly generated source code
#
#a module, but not meant to be mixed in
#
####################################################################################
#each project-specific rakefile-header including this file must provide the following within module BuildEnv:
# private projrootPathname() -- return Pathname
# private sourceTreeRoots() -- return array of Pathnames
# private buildTreeRoot() -- return Pathname
# whichever private functions of the form create<COMPILER_TYPE>() are needed for the project (see Compiler.rb)
#
module BuildEnv

##### filesystem paths #####

	private
	
	#return whether filepath, which might not exist, is a non-strict descendent of dirpath, which exists
	#filepath: abs Pathname
	#dirpath: abs Pathname
	def self.subtreeOf?(filepath, dirpath)
		filepath.ascend {|path| return true if path.exist? && realFilepath(path) == dirpath}
		return false
	end
	
	#get the offset of filepath from whichever project source tree it's in
	#pre: pathWithinProject?(filepath)
	#filepath: Pathname
	#return: Pathname
	def self.sourceTreeOffset(filepath)
		return filepath.relative_path_from(filepathSrcRoot(filepath))
	end
	
	#return the source tree root filepath is under
	#pre: pathWithinProject?(filepath)
	#filepath: abs Pathname
	#return: abs Pathname
	def self.filepathSrcRoot(filepath)
		sourceTreeRoots().each {|dirpath| return dirpath if subtreeOf?(filepath, dirpath)}
		raise "path '#{filepath}' isn't in any src dir"
	end
	
	#filepath: Pathname
	#return: whether the (possibly nonexistent) file referred to by filepath is in any of the project's source trees
	def self.pathWithinProject?(filepath)
		sourceTreeRoots().each {|dirpath| return true if subtreeOf?(filepath, dirpath)}
		return false
	end
	
	#return the path to the file that holds the mapping from source tree roots to/from build subdir names
	#return: abs Pathname
	def self.srcdirBuildIDMapFilepath()
		return buildTreeRoot().join('srcroots-buildIDs.map')
	end
	
	#read the file that holds the mapping from source tree roots to/from build subdir names
	#return: none
	def self.readSrcdirBuildIDMapFile()
		#create an empty file if the file doesn't exist
		unless srcdirBuildIDMapFilepath().exist?()
			System::createPath srcdirBuildIDMapFilepath().dirname()
			`> #{srcdirBuildIDMapFilepath()}`
		end
	
		@@srcdir2buildIDMap = Hash.new() #abs Pathname -> build subdir name string
		@@buildID2srcdirMap = Hash.new() #build subdir name string -> abs Pathname
		@@nextBuildID = 0
		File.open(srcdirBuildIDMapFilepath(), "r") do |fid|
			fid.each_line do |line|
				tokens = line.chomp.split "\t"
				@@srcdir2buildIDMap[Pathname.new(tokens[0])] = tokens[1] #abs src root path => build subdir
				@@buildID2srcdirMap[tokens[1]] = Pathname.new(tokens[0]) #build subdir => abs src root path
				@@nextBuildID = Integer(/srcdir(\d+)\Z/.match(tokens[1])[1]) + 1
			end
		end
	end
	
	#write the file that holds the mapping from source tree roots to/from build subdir names
	#return: none
	def self.writeSrcdirBuildIDMapFile()
		File.open(srcdirBuildIDMapFilepath(), "w") do |fid|
			@@srcdir2buildIDMap.each_pair {|srcpath, buildID| fid.puts "#{srcpath}\t#{buildID}"}
		end
	end
	
	#get the build dir entry for the given src root dir
	#dirpath: abs Pathname
	#return: string
	def self.srcdir2buildID(dirpath)
		readSrcdirBuildIDMapFile() unless defined?(@@srcdir2buildIDMap) #ensure we've read the map file
		
		#add an entry for this src root if there isn't one
		#(don't delete entries that are currently unused; give the user the option of using them in this project again later)
		if !@@srcdir2buildIDMap.has_key?(dirpath)
			buildID = "srcdir#{@@nextBuildID}"
			@@srcdir2buildIDMap[dirpath] = buildID
			@@buildID2srcdirMap[buildID] = dirpath
			writeSrcdirBuildIDMapFile() #I can't think of a way to write only once when building finishes, so do it every time we add an entry -- EVH 20090115
			@@nextBuildID += 1
		end
		return @@srcdir2buildIDMap[dirpath]
	end
	
	#get the src root dir for the given build dir entry
	#id: string or Pathname
	#return: abs Pathname
	#yell if there's no such build subdir name
	def self.buildID2srcdir(id)
		readSrcdirBuildIDMapFile() unless defined?(@@srcdir2buildIDMap) #ensure we've read the map file
		raise "no such build id: '#{id}'" unless @@buildID2srcdirMap.has_key?(id.to_s)
		return @@buildID2srcdirMap[id.to_s]
	end
	
	public
	
	#pre: the source and build trees aren't rooted in the same place
	#filepath: Pathname
	#return: which type of project tree the (possibly nonexistent) file is in: :src, :build or :neither
	def self.whichProjectTree(filepath)
		#cache
		srcRoots = sourceTreeRoots()
		buildRoot = buildTreeRoot()
		
		#go through dirs in path, bottom-up
		filepath.ascend() do |path|
			if srcRoots.include?(path)
				return :src
			elsif path == buildRoot
				return :build
			end
		end
		return :neither
	end
	
	#move filepath from the source to the build tree
	#pre: pathWithinProject?(filepath)
	#filepath: Pathname
	#return: Pathname
	def self.src2build(filepath)
		raise "filepath not in src dir (try using srcOrBuild2build): #{filepath}" if whichProjectTree(filepath) != :src
		return Pathname.new(buildTreeRoot()).join(srcdir2buildID(filepathSrcRoot(filepath))).join(sourceTreeOffset(filepath))
	end

	def self.srcOrBuild2build(filepath)
		treeType = whichProjectTree(filepath)
		if treeType == :build then
			return filepath 
		elsif treeType == :src
			return src2build(filepath)
		else
			raise "filepath is neither build or src: #{filepath}"
		end
	end
	
	#move filepath from the build to the source tree
	#pre: pathWithinProject?(filepath)
	#filepath: Pathname
	#return: Pathname
	def self.build2src(filepath)
		relpath = filepath.relative_path_from(buildTreeRoot())
		
		#find the dir name in the path just below the build tree root dir
		dirs = []
		relpath.descend {|dirpath| dirs.push dirpath}
		
		relpath = filepath.relative_path_from(buildTreeRoot().join(dirs[0])) #rel path wrt build-name-specific and src-tree-specific build dir
		return Pathname.new(buildID2srcdir(dirs[0].basename())).join(relpath)
	end

##### properties of entities and entity types #####
#currently an 'entity spec' must be either an abs Pathname or an extlib symbol
	
	private
	
	#auxiliary to filename filter functions below:
	#return the module name if the filepath's extname() is in exts; else return nil
	#exts: array of strings
	#filepath: Pathname
	def self.checkExts(exts, filepath)
		return exts.include?(filepath.extname()) ? filepath.basename(filepath.extname()) : nil
	end
	
	#the definitive list of entity types supported by this system and various (default) properties of those types
	#
	#type symbol => hash with:
	#boolean attributes:
	#  :built => true if files of the type usually must be built as part of the project
	#  :linked => true if files of the type are built by linking
	#  :linkable => true if files of the type can be included in a link
	#  :lib => true if the type is a library type
	#  :external => true if the type is usually external to the project
	#general attributes:
	#  :filenameFilter => function taking a Pathname and returning either the module basename as a string or nil,
	#                      depending on whether the file is of this type
	#
	#each attribute has a default (false for booleans; listed above for non-boolean)
	#
	#TODO is there a decent way to move the system-specific part of this somewhere without annoying people who don't use system-standard extensions?
	@@typeInfo = {
		:h => { #header
			:filenameFilter => lambda {|filepath| return checkExts(['.h', '.hpp', '.hh', '.ipp', '.tpp'], filepath)}
		},
		:moc => { #MOC headers
			:filenameFilter => lambda {|filepath| return checkExts(['.moc'], filepath)},
			:built => true
		},
		:c => { #c source
			:filenameFilter => lambda {|filepath| return checkExts(['.c'], filepath)}
		},
		:cxx => { #c++ source
			:filenameFilter => lambda {|filepath| return checkExts(['.cpp'], filepath)}
		},
		:f => { #fortran source
			:filenameFilter => lambda {|filepath| return checkExts(['.f'], filepath)}
		},
		:rb => { #ruby source
			:filenameFilter => lambda {|filepath| return checkExts(['.rb'], filepath)}
		},
		:cobj => { #c++-compatible object
			:filenameFilter => lambda {|filepath| return checkExts(['.o'], filepath)},
			:built => true, 
			:linkable => true
		},
		:intlib => { #project-internal static lib
			:filenameFilter => lambda {|filepath| return checkExts(['.a'], filepath)},
			:built => true,
			:linkable => true,
			:lib => true
		},
		:extlib => { #project-external lib (system or third-party)
			:linkable => true,
			:lib => true,
			:external => true
		},
		:exe => { #executable
			:filenameFilter => lambda {|filepath| return checkExts([''], filepath)},
			:built => true,
			:linked => true
		}
	}
	
	#overrides of the type-level info above for specific entities
	@@entityOverrides = Hash.new #entity spec => any of the info given above for types
	
	#get the value of the given property for the given entity
	#entity: entity spec
	#propname: property-name symbol (see above)
	#return: boolean
	def self.getEntityBooleanProperty(entity, propname)
		if @@entityOverrides[entity] && @@entityOverrides[entity][propname]
			return @@entityOverrides[entity][propname]
		else
			return @@typeInfo[entityType(entity)[0]][propname] || false
		end
	end
	
	#override the default property value for the given entity
	#entity: entity spec
	#propname: property-name symbol (see above)
	#val: value to set
	def self.setEntityBooleanProperty(entity, propname, val)
		@@entityOverrides[entity] = Hash.new unless @@entityOverrides[entity]
		@@entityOverrides[entity][propname] = val
	end
	
	#usually we tell a file's type by its filename; allow overrides
	@@entityTypeOverrides = Hash.new #entity spec => [type symbol, module basename]
	
	public
	
	#try to figure out the type of an entity by looking at its entity spec (which is probably a filepath)
	#entity: entity spec
	#return: symbol for type of entity, module basename as a string
	#raise an exception if we can't figure out the type (see entityTypeSafe())
	def self.entityType(entity)
		raise "[param = #{entity}] strings aren't entity specs!" if entity.is_a?(String) #catch a common programmer error
		if @@entityTypeOverrides.has_key?(entity) then return @@entityTypeOverrides[entity]
		elsif entity.is_a?(Symbol) then return :extlib, extlibBasename(entity)
		else
			@@typeInfo.each do |typesym, info|
				if info.has_key?(:filenameFilter)
					match = info[:filenameFilter].call(entity)
					if match then return typesym, match end
				end
			end
		end
		raise "can't figure out type of entity '#{entity.to_s}'"
	end
	
	#entity: entity spec
	#return: symbol for type of entity, module basename as a string
	#if we can't figure out the type, return [:unknown, <unspecified>] (see entityType())
	def self.entityTypeSafe(entity)
		begin
			return entityType(entity)
		rescue #any exception
			case entity
				when Pathname then return :unknown, entity.basename(entity.extname()) #we probably only use extensions to signify file types, so filetitle is a good guess at module name
				else return :unknown, 'AINT_GOT_NO_CLUE'
			end
		end
	end
	
	#make an exception to the default method for figuring out entity type: explicitly set the type for a given entity
	#entity: entity spec
	#type: entity-type symbol
	#modbase: string with module basename (eg 'utils' for 'a/b/utils.o')
	#return: none
	def self.setEntityType(entity, type, modbase)
		@@entityTypeOverrides[entity] = [type, modbase]
	end
	
	###entity boolean-property getters/setters
	#getter: take entity spec, return boolean
	#setter: take entity spec, return none
	
	def self.isBuilt?(entity) return getEntityBooleanProperty(entity, :built) end
	#say this particular entity must be built even if its entity type usually isn't
	def self.setEntityBuilt(entity) setEntityBooleanProperty(entity, :built, true) end
	def self.isUsedInLinking?(entity) return getEntityBooleanProperty(entity, :linkable) end
	#pre: isBuilt?(entity)
	def self.isLinked?(entity) return getEntityBooleanProperty(entity, :linked) end
	def self.isProjectExternal?(entity) return getEntityBooleanProperty(entity, :external) end
	#say this entity is external to the project
	def self.setEntityProjectExternal(entity) setEntityBooleanProperty(entity, :external, true) end
	def self.isLib?(entity) return getEntityBooleanProperty(entity, :lib) end
	
	#getters for info about external libs
	
	#libsym: symbol for registered external lib
	#return: whether we've been given a path to the referenced external lib
	def self.extlibHasDir?(libsym)
		return ExtlibRegistry::get(libsym)[:dir] #true iff value isn't nil
	end
	
	#libsym: symbol for registered external lib
	#return: whether there's a shared lib associated with the given library
	def self.extlibHasLib?(libsym)
		return ExtlibRegistry::get(libsym)[:name] #true iff value isn't nil
	end
	
	#pre: extlibHasDir?(libsym)
	#libsym: symbol for registered external lib
	#return: Pathname
	def self.extlibLibdir(libsym)
		return ExtlibRegistry::get(libsym)[:dir]
	end
	
	#libsym: symbol for registered external lib
	#return: array of Pathnames for #includes for the given lib (probably won't include directories the compiler searches by default)
	def self.extlibIncdirs(libsym)
		return ExtlibRegistry::get(libsym)[:incdirs]
	end
	
	#libsym: symbol for registered external lib
	#return: string
	def self.extlibBasename(libsym)
		raise "unknown extlib reference #{libsym}" unless ExtlibRegistry::get(libsym)
		return ExtlibRegistry::get(libsym)[:name]
	end
	
##### misc bookkeeping of entities #####

	private
	
	#TODO preferable to have some sort of global list of all entities and have various views into it that get updated as nec;
	# for now this seems to be the only such view I use -- EVH 20081207
	@@generatedFiles = [] #abs Pathnames
	
	public
	
	#pre: filepath.dirname().exist?
	#filepath: abs Pathname
	#return: whether there's a generated file by the given name
	def self.fileIsGenerated?(filepath)
		truedir = realdir(filepath.dirname())
		ensureRakefileRead truedir
		return !@@generatedFiles.grep(filepath).empty?
	end
	
	#register that the given file is generated (this is the only way to ensure the system knows about a generated file)
	#filepath: abs Pathname
	#return: none
	def self.addGeneratedFile(filepath)
		@@generatedFiles.push filepath
	end
	
	#search for existing or generated headers associated with the given module so that link deps can be added
	#modpath: abs module Pathname
	#return: possibly empty array of Pathnames
	def self.findHeadersForModule(modpath)
		dir = modpath.dirname()
		modname = modpath.basename()
		existingToCheck = dir.entries().select {|filename| !filename.directory?}.map {|filename| dir.join(filename)}
		generatedToCheck = @@generatedFiles.select {|filepath| filepath.dirname() == dir}
		return (existingToCheck | generatedToCheck).select do |filepath|
			type, fmodname = entityTypeSafe(filepath)
			type == :h && fmodname == modname
		end
	end
	
##### dependence graphs #####

	private

	#Ruby Graph Library
	require 'rgl/adjacency'
	require 'rgl/topsort'
	
	@@buildPrereqs = RGL::DirectedAdjacencyGraph.new #vertices are entity specs; edge (u, v) says v must be built before u can be
	
	@@linkDeps = RGL::DirectedAdjacencyGraph.new #vertices are entity specs; edge (u, v) says v must be linked if u is being linked
#	@@linkDepsProcessed = Hash.new #entity spec => true if we've processed its link-time dependences
	
	#for debugging
	#block: return whether to print the item (an entity spec)
	def self.printGraph(graph, &block)
		graph.each_vertex do |v|
			neighbors = graph.adjacent_vertices(v).select(&block)
			if !neighbors.empty?() || block.call(v) #don't print uninteresting bits
				puts v.to_s + " =>\n[\n" + neighbors.join(",\n") + "\n]"
			end
		end
	end
	
	public
	
	### debugging functions ###
	
	def self.printLinkDeps(&filter)
		puts "link deps:"
		printGraph(@@linkDeps, &filter)
	end
	
	def self.printLinkDepsWithLibs()
		puts "link deps w/libs:"
		printGraph(@@linkDeps) {|s| s.is_a?(Symbol) || !@@linkDeps.adjacent_vertices(s).select {|t| t.is_a?(Symbol)}.empty?}
	end
	
	private
	
	#if we haven't already, put info we have on this entity into the link-dependence graph
	#entity: entity spec
	#return: none
	def self.processLinkDeps(entity)
#		unless @@linkDepsProcessed[entity]
#			#currently no link deps that wouldn't already have been processed
#			@@linkDepsProcessed[entity] = true
#		end
	end

#don't remove; this code is useful as a template for functions that do almost this, but I don't use this actual code -- EVH 20081205
#	
#	#get all elements u for which RELATION(v, u), given that RELATION is transitive and is partially encoded in the given graph
#	#graph: RGL::DirectedAdjacencyGraph
#	#v: entity spec that should be in graph as a vertex
#	#return: enumerable of entity specs
#	def self.transitiveClosure(graph, v)
#		#don't call graph.transitive_closure() because that takes forever when graph has a lot of vertices even when we don't care about most of them
#		closure = Set.new [v]
#		if graph.has_vertex?(v) #vertices are only added when edges are, so if it's not in the graph, there aren't edges out of it
#			toProcess = graph.adjacent_vertices(v)
#			until toProcess.empty?()
#				u = toProcess.shift
#				closure.add u
#				toProcess |= (graph.adjacent_vertices(u) - closure.to_a)
#			end
#		end
#		return closure
#	end
	
	public
	
	#builds-after(A, B) is a transitive relation
	
	#pre: isBuilt?(entity)
	#entity: entity spec
	#return: enumerable of entities on which entity has an immediate build dependence (they must be built before it)
	def self.buildPrereqs(entity)
		return @@buildPrereqs.adjacent_vertices(entity)
	end

	#say entity must be built after prereqs
	#entity: entity spec
	#prereqs: entity spec or array of them
	#return: none
	def self.addBuildPrereq(entity, prereqs)
		ensureArray(prereqs).each {|prereq| @@buildPrereqs.add_edge entity, prereq}
	end
	
	#requires-at-link-time(A, B) is a transitive relation
	
	#pre: isLinked?(entity) || exists A s.t. requires-at-link-time(A, entity)
	#entity: entity spec
	#return: enumerable of entities immediately required by entity at link time (even if entity doesn't get linked)
	def self.immediateLinkDeps(entity)
		processLinkDeps(entity) #add graph edges we didn't know about before, if we haven't done so
		if @@linkDeps.has_vertex?(entity)
			return @@linkDeps.adjacent_vertices(entity)
		else
			return []
		end
	end
	
	#pre: isLinked?(entity) || exists A s.t. requires-at-link-time(A, entity)
	#entity: entity spec
	#return: enumerable of entities immediately or indirectly required by entity at link time (even if entity doesn't get linked)
	def self.allLinkDeps(entity)
		#adapt transitiveClosure() to process link deps for each entity we encounter
		processLinkDeps(entity) #add graph edges we didn't know about before, if we haven't done so
		closure = Set.new [entity]
		if @@linkDeps.has_vertex?(entity) #vertices are only added when edges are, so if it's not in the graph, there aren't edges out of it
			toProcess = @@linkDeps.adjacent_vertices(entity)
			until toProcess.empty?()
				u = toProcess.shift
				processLinkDeps(u) #add graph edges we didn't know about before, if we haven't done so
				closure.add u
				toProcess |= (@@linkDeps.adjacent_vertices(u) - closure.to_a)
			end
		end
		return closure
	end
	
	#pre: isLinked?(entity) || exists A s.t. requires-at-link-time(A, entity)
	#entity: entity spec
	#return: enumerable of entities immediately or indirectly required by entity at link time (even if entity doesn't get linked),
	# in order for, eg, the gcc link line (ie sorted with each dependee after its dependents)
	def self.allLinkDepsOrdered(entity)
		closure = allLinkDeps(entity) #the elements we want, but not toposorted
		
		#toposort (libs only!) as efficiently as possible
		allLibs = [] #all libs, since some of them won't have edges in libgraph
		libgraph = RGL::DirectedAdjacencyGraph.new #lib entity => enumerable of libs the key depends on
		closure.select {|ent| isLib?(ent)}.each do |ent|
			allLibs.push ent
			#do bfs from this lib, stopping whenever we hit any other lib (because we'll get recursive deps from those other libs' BFSs)
			bfs = [immediateLinkDeps(ent), Set.new]
			until bfs[0].empty?()
				depent = bfs[0].shift
				bfs[1].add depent
				if isLib?(depent)
					libgraph.add_edge ent, depent
				else
					bfs[0] += immediateLinkDeps(depent) - bfs[1]
				end
			end
		end
		
		sortedClosure = closure.select {|ent| !isLib?(ent)} + (allLibs - libgraph.vertices()) #everything for which order doesn't matter
		sortedClosure += libgraph.topsort_iterator.map {|x| x} #everything for which order does matter
		return sortedClosure.select {|ent| isUsedInLinking?(ent)}
	end
	
	#say entity requires depents at link time
	#entity: entity spec
	#depents: entity spec or array of them
	#return: none
	def self.addLinkDeps(entity, depents)
		ensureArray(depents).each {|depent| @@linkDeps.add_edge entity, depent}
	end
	
##### project setup (there'll be a lot more of this in the Rakefile.include) #####

	private
	
	#ENV is a rake feature: if the user calls 'rake KEY=VAL', ENV will be {'KEY' => 'VAL'}
	
	#see Compiler.rb for setup involving compilers for specific file types
	
	RAKEFILENAME = 'Rakefile.rb' #used when looking for rakefiles in auxiliary source dirs; as of now only one filename is used -- EVH 20080422
	
##### project-specific libs #####

	private
	
	#tell the build system to use a previously registered external library
	#libsyms: symbol for registered library, or array of them
	#return: none
	def self.use3pLibs(libsyms)
		ensureArray(libsyms).each do |sym|
			unless @@linkDeps.has_vertex?(sym) #unless we've already processed this lib
				libinfo = ExtlibRegistry::get(sym)
			
				#set up include path
				cxxCompiler().addIncludeDirs(libinfo[:incdirs].map {|path| Pathname.new path})
			
				#set up dependence graphs
				deplibs = libinfo[:requires]
				use3pLibs deplibs #make sure the libs we depend on also get added to the project, and so on recursively
				addLinkDeps sym, deplibs
				libinfo[:headers].each {|filepath| addLinkDeps filepath, sym}
			end
		end
	end
	
##### automatic dependence finding #####
	
	public
	
	#return the filepath to the file listing header dependences of the given source file
	#srcpath: source file entity spec
	#return: abs Pathname of the dep list file
	def self.getIncludeDepListFilepath(srcfile)
		return realFilepath(Pathname.new("#{BuildEnv::srcOrBuild2build(srcfile)}.includes")) #Pathnames must be stringized for concatenation; + adds an entry
	end
	
	#run something equivalent to gcc to get source-file dependences; parse the output; check whether nonexistent files have generation rules;
	# yell if they don't; return all resulting header filenames
	#builder: Builder
	#srcfile: entity spec
	#return: enumerable of entity specs
	#post: for each e in <return val>, entityType(e)[0] == :h
	def self.parseHeaderDeps(builder, srcfile)
		listfilename = getIncludeDepListFilepath(srcfile) #non-temp file whose list doesn't include lots of extra system headers
		
		if File.exist?(listfilename) #dependences previously computed; might be up to date and we can skip more expensive processing
			files = File.open(listfilename).map {|line| line.chomp}
#			puts "existing deps for #{srcfile.to_s}:"
#			puts files.join("\n")
#			readline

			#figure out all the files that might have changed and made the includes-list file obsolete
			#(include this dir's rakefile and the project rakefile because if they've changed there might be new compile-time options for srcfile, so the
			# list of headers srcfile needs might have changed)
			rakefileIncludeFilepath = absolutizeFilepath(Pathname.new('Rakefile.include.rb'), projrootPathname())
			rakefileFilepath = absolutizeFilepath(Pathname.new('Rakefile.rb'), srcfile.dirname()) #might not exist -- TODO what happens then?
			filesToCheck = files + [srcfile.to_s, rakefileIncludeFilepath.to_s]
			if rakefileFilepath.exist?() then filesToCheck.push rakefileFilepath.to_s end
			
			if FileUtils.uptodate?(listfilename, filesToCheck) #if the info we stored on the file's includes is newer than all source files involved
				files = files.map {|filepath| canonicalizeFilepath(Pathname.new(filepath), builder.dir())}
				allFilesFound = true
				files.each do |filepath|
					ensureRakefileRead filepath.dirname() #if the file exists, find out what it pulls in; if it doesn't exist, find out whether it's generated
					#if any stored filename doesn't refer to an existing or generated file, we need to regenerate the list
					if !filepath.exist?() && !fileIsGenerated?(filepath)
							allFilesFound = false
					end
					
					type, modbase = entityTypeSafe(filepath)
					if type == :unknown
						setEntityType(filepath, :h, modbase) #allLinkDeps() etc need that the type is :h
					end
				end
				if allFilesFound
					return files.map {|filename| Pathname.new(filename)}
				end
			end
		end
		
		#else need to compute dependences and store to filesystem
		
		runDepFinderAgain = true
		while runDepFinderAgain
			runDepFinderAgain = false
			
			#run the compiler with all the include paths this file's builder knows (so if it can't find a header H, either H is generated or H doesn't exist)
			filenames = builder.cxxCompiler().getHeaderDependencesAbsOrRel(builder, srcfile, true)
			filenames = filenames.map {|filename| Pathname.new(filename)}
			
			#check for generated headers in the include path matching all the header filenames we haven't already found
			cantFindHeaderErrs = [] #list of err msgs for headers we can't locate
			filenames = filenames.map do |filepath|
#				puts "checking hdr '#{filepath}' from srcfile '#{srcfile}'"
				finalpath = filepath
				if filepath.relative?() #the compiler couldn't find a file, so assumed it's generated; check that assumption
					@@cxxCompiler.includeDirs().each do |dirpath|
						if File.exist?(dirpath) #if it doesn't exist, canonicalizeDir() will yell and abort rake, which isn't what we want
							dirpath = canonicalizeDir(dirpath, Pathname.pwd())
							if pathWithinProject?(dirpath)
								ensureRakefileRead dirpath
								dirname, filename = dirpath.join(filepath).split()
								#if there's no such subdirectory (dirname) of this include path (dirpath), let's skip this INCDIRS entry and avoid 
								# having realpath() abort rake with an unhelpful error msg
								if dirname.exist?()
									fullpath = dirname.realpath().join(filename)
									if fileIsGenerated?(fullpath)
										#cause it to be generated, then set a flag to redo the dependence finding to catch files the generated file pulls in
										Rake::Task[fullpath.to_s].reenable() #just in case
										Rake::Task[fullpath.to_s].invoke()
										runDepFinderAgain = true
									
										finalpath = fullpath
										break #take the first matching file we find
									end
								end
							end
						end
					end				
					if finalpath == filepath #we didn't find an existing or generated file; don't know how to build srcfile
						cantFindHeaderErrs.push "dependence finder can't find file, or rule to generate file, '#{filepath}' (included by '#{sourceTreeOffset(srcfile)}')"
					end
				end
				finalpath #if there was no error, this is the (future, if generated) absolute location of the header referred to by 'filepath'
			end
		end
		
		if !cantFindHeaderErrs.empty?
			puts cantFindHeaderErrs.join("\n")
			exit -1 #kill rake
		end
		
#		puts "new deps for #{srcfile.to_s}:"
#		puts filenames.join("\n")
#		readline
		filenames = filenames.map {|filepath| canonicalizeFilepath(filepath, builder.dir())}
		filenames.each do |filepath|
			type, modbase = entityTypeSafe(filepath)
			if type == :unknown
				setEntityType(filepath, :h, modbase)
			end
			if pathWithinProject?(filepath)
				ensureRakefileRead filepath.dirname() #find out what the file pulls in
			else
				setEntityProjectExternal(filepath)
			end
		end
		
#		puts "new deps for #{srcfile.to_s}:"
#		puts filenames.map {|f| "#{f} (#{f.class}) -> " + immediateLinkDeps(f).join(', ')}.join("\n")
		
		#heuristic to get rid of internal system headers
		#(this is a heuristic, not optimal, because nonpublic 3rd-party headers might be updated by a package manager, making us out of date;
		# but that's rare, and empirically this heuristic greatly increases the speed of operations on the dependence graphs)
		filenames = filenames.uniq().select do |filepath|
			pathWithinProject?(filepath) || #keep track of all headers that are part of the project code
			!immediateLinkDeps(filepath).empty? || #keep track of all headers that are immediately dependent on shared libs
			ExtlibRegistry::libIncludingHeader(filepath) #keep track of all headers that were specified by the user as part of a (possibly header-only) lib
		end
		
		#cache the updated dependence list to disk
		File.open(listfilename, 'w') do |outfile|
			filenames.each {|filename| outfile.puts filename.to_s + "\n"}
		end
		
		return filenames
	end
	
##### Rakers #####

	private
	
	@@rakers = Hash.new #Pathname => the unique Raker for that dir
	@@readingAuxiliary = false #whether we're reading the current rakefile as part of processing another
	
	#pre: we haven't already read the rakefile in the requested dir
	#read a rakefile as part of processing another one (so there are some things we don't want to do, like adding dependences to the 'clean' task)
	#dir: abs Pathname
	#return: none
	def self.readAuxiliaryRakefile(dir)
		#make sure rakefiles that can be used for multiple projects know which one is being built
		ENV['projroot'] = projrootPathname() unless ENV['projroot']
	
		prevRA = @@readingAuxiliary
		@@readingAuxiliary = true
		#use File::readlines() instead of load()ing each rakefile so that we can put each rakefile in its own scope (ie module) and avoid name clashes
		Dir.chdir(dir.to_s) do
			requireInNewModule RAKEFILENAME #give it its own anonymous module to avoid variable name clashes between rakefiles
		end
		@@readingAuxiliary = prevRA
	end

	public
	
	#one raker per directory
	#raker: Raker
	#dir: abs Pathname
	def self.setRaker(raker, dir)
		System::createPath src2build(dir) #we'll get yelled at later, by canonicalizePathname() if nothing else, if the build dir doesn't exist
		@@rakers[dir] = raker
		@@rakers[src2build(dir)] = raker #doesn't really matter which tree we're "in" when building
	end
	
	#if no existing raker, read that dir's rakefile; if it doesn't have one, yell
	#dir: (abs or rel to cwd) Pathname
	#return: Raker
	def self.raker(dir)
		dir = canonicalizeDir(dir, Pathname.pwd())
		ensureRakefileRead(dir)
		return @@rakers[dir]
	end
	
	#return: whether the rakefile we're currently reading is being read due to inclusion by another
	def self.readingAuxiliary?()
		return @@readingAuxiliary
	end
	
	#read the rakefile in the given location, if there is one and we haven't already seen it; if there isn't a rakefile, do nothing
	#dirpath: abs Pathname
	#return: none
	def self.ensureRakefileRead(dirpath)
		if pathWithinProject?(dirpath) && !@@rakers.has_key?(dirpath)
			if dirpath.join(RAKEFILENAME).exist?()
				readAuxiliaryRakefile dirpath
			#heuristic: assume the first rakefile above us in the filesystem is ours (if not, no rakefile is ours and we're confused, so yell);
			# recursively check for such a rakefile
			else
				raise "recursive directory check for rakefile failed" if dirpath == PROJROOT #base case for filesystem ascend
				ensureRakefileRead dirpath.parent()
			end
		end
	end

end

require 'Builder'
require 'builders/GeneratedSourceBuilder'
require 'builders/QtMocBuilder'
require 'builders/CXXObjBuilder'
require 'builders/FObjBuilder'
require 'builders/StaticLibBuilder'
require 'builders/ExeBuilder'
require 'builders/SymlinkBuilder'
require 'Raker'
