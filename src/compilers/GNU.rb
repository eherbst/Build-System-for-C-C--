#implementation of Compiler.rb interfaces using GNU compilation system
#Evan Herbst, 12 / 16 / 08

require 'Compiler'

class GCC
include CXXCompiler
include FortranCompiler
include Linker

	public
	
	#I got this from http://zeljkofilipin.com/2006/02/09/ruby-deep-copy-object/;
	# apparently there isn't a better way to do a deep copy in ruby without a lot of coding -- EVH
	#return a deep copy of this object
	# (for Builders to create customized compilers without permanently changing our settings)
	def deepCopy()
		return Marshal::load(Marshal.dump(self))
	end
	
	#params: hash of param names to values
	#params we use:
	#  :gcc => name of gcc executable (eg '/my/bin/gcc'); by default used for everything
	#  :cc (optional) => use a C compiler other than that given by :gcc
	#  :cxx (optional) => use a C++ compiler other than that given by :gcc
	#  :fcc (optional) => use a Fortran compiler other than that given by :gcc
	#  :ld (optional) => use a linker other than that given by :gcc
	#  :cflags (optional; default []) => array of flags to C compiler (eg ['-g', '-Wall'])
	#  :cxxflags (optional; default []) => array of flags to C++ compiler (eg ['-g', '-Wall'])
	#  :fflags (optional; default []) => array of flags to fortran compiler (eg ?)
	#  :ldflags (optional; default []) => array of flags to linker (eg ['-g'])
	#  :incdirs (optional; default []) => array of abs Pathnames for include dirs
	def initialize(params)
		@CC = params[:cc] || params[:gcc]
		@CXX = params[:cxx] || params[:gcc]
		@FCC = params[:fcc] || params[:gcc]
		@LD = params[:ld] || params[:gcc]
		@CFLAGS = params[:cflags] || []
		@CXXFLAGS = params[:cxxflags] || []
		@FFLAGS = params[:fflags] || []
		@LDFLAGS = params[:ldflags] || []
		@INCDIRS = params[:incdirs] || []
		
		#find a directory we can scratch in
		@tmpdir = BuildEnv::buildTreeRoot().join('tmp');
		`mkdir -p #{@tmpdir}`;
	end
	
	#return: array of abs Pathnames
	def includeDirs() return @INCDIRS end
	
	#add include dirs
	#incdirs: abs Pathname or String or array of them
	#return: none
	def addIncludeDirs(incdirs)
		@INCDIRS += ensureArray(incdirs).map {|p| Pathname.new(p)}
	end
	
	#add flags (they'll go before flags added internally by this object)
	#flags: string or array of them
	#return: none
	def addCFlags(flags) @CFLAGS = ensureArray(flags) + @CFLAGS end
	def addCXXFlags(flags) @CXXFLAGS = ensureArray(flags) + @CXXFLAGS end

	#replace all flags other than include dirs
	#flags: string or array of them
	#return: none
	def setCFlags(flags) @CFLAGS = ensureArray(flags) end
	def setCXXFlags(flags) @CXXFLAGS = ensureArray(flags) end
	
	#run something equivalent to gcc to get source-file dependences; parse the output and return all resulting header filenames
	#builder: Builder
	#srcfile: entity spec
	#print: bool, whether to print that we're running (probably no if the run is on a file created by the build system)
	#return: enumerable of rel/abs filepath strings
	def getHeaderDependencesAbsOrRel(builder, srcfile, print)
		if print
			puts "running gcc dependence printer on #{srcfile}"
		end
		
		#don't need to src2build() the output dir because the builder's dir is already under the build tree
		outfilename = @tmpdir.join('includes.list') #write to file in case stdout gets muddied by preprocessor errors
		
		#gcc -M flag lists included headers; with -M, -MG means assume missing files are generated, and -MF specifies outfilename for header list
		cmd = "#{compileCmd(srcfile)} #{@INCDIRS.map {|dirpath| "-I#{dirpath}"}.join(' ')} -MF #{outfilename} -M -MG #{srcfile.to_s}"
		
#		puts cmd
		`#{cmd}`
		if $?.to_i != 0
			raise "gcc dependence printer found errors; killing rake"
		else
			fid = File.open(outfilename)
			output = fid.map {|line| line.to_s}.join('')
			fid.close()
			`#{$RM} #{outfilename}`
			filenames = output.gsub(/\\\n/, ' ').gsub(/:\s+/, ' ').gsub(/([^\\])\s+/, "\\1 ").split(/\s+/) #regexes specific to gcc-like output
			filenames.shift; filenames.shift #remove object filename and source filename; rest are headers
			return filenames
		end
	end
	
	private
	
	#get the equivalent of the expansion in a makefile of $CXX $CXXFLAGS (for the appropriate language)
	#srcfile: entity spec
	#return: string
	def compileCmd(srcfile)
		return case BuildEnv::entityTypeSafe(srcfile)[0]
			when :c then "#{@CC} #{@CFLAGS.join(' ')}"
			when :cxx then "#{@CXX} #{@CXXFLAGS.join(' ')}"
			when :f then "#{@FCC} #{@FFLAGS.join(' ')}" 
			else raise "shouldn't happen"
		end
	end
	
	#pre: exists A s.t. requires-at-link-time(A, entity)
	#entity: entity spec
	#return: string with arguments to be added to the link line if entity is included in linking
	def linkArgsFor(entity)
		case BuildEnv::entityType(entity)[0]
			when :cobj then return entity.to_s
#as of 10 / 31 / 08, we never link internal static libs, because we can use their component object files instead with less annoyance
#			when :intlib then return "-L#{entity.dirname()} -l#{entity.basename().sub(entity.extname(), '')} -Wl,-rpath -Wl,#{entity.dirname()}"
			when :extlib then
				if BuildEnv::extlibHasLib?(entity)
					if BuildEnv::extlibHasDir?(entity)
						return "-L#{BuildEnv::extlibLibdir(entity)} -l#{BuildEnv::extlibBasename(entity)} -Wl,-rpath -Wl,#{BuildEnv::extlibLibdir(entity)}"
					else
						return "-l#{BuildEnv::extlibBasename(entity)}"
					end
				else
					return "" #nothing to link, but the lib symbol is needed in order to find shared libs its headers depend on
				end
			else return ''
		end
	end
	
	public
	
	#params: hash of param names to values
	#params we use:
	#  :src => source file entity spec
	#  :target => output file entity spec
	#  :opts (optional) => string of other options -- will be given before all other options generated from params
	#return: none
	def compileCXX(params)
		src = requireParam(params, :src)
		target = requireParam(params, :target)
		otherOptions = params[:opts] || []
		
		printAndCall("#{compileCmd(src)} #{otherOptions.join(' ')} #{@INCDIRS.map {|dirpath| "-I#{dirpath}"}.join(' ')} -o #{target} -c #{src}")
	end
	
	#params: hash of param names to values
	#params we use:
	#  :src => source file entity spec
	#  :target => output file entity spec
	#  :opts (optional) => string of other options -- will be given before all other options generated from params
	#return: none
	def compileFortran(params)
		src = requireParam(params, :src)
		target = requireParam(params, :target)
		otherOptions = params[:opts] || []
		
		printAndCall("#{compileCmd(src)} #{otherOptions.join(' ')} #{@INCDIRS.map {|dirpath| "-I#{dirpath}"}.join(' ')} -o #{target} -c #{src}")
	end
	
	#params: hash of param names to values
	#params we use:
	#  :objs => entity spec for entity to be linked, or array of them
	#  :target => output file entity spec
	#  :opts (optional) => string of other options -- will be given before all other options generated from params
	#return: none
	def link(params)
		objs = ensureArray(requireParam(params, :objs))
		target = requireParam(params, :target)
		otherOptions = params[:opts] || []
	
		printAndCall("#{@LD} #{@LDFLAGS.join(' ')} #{otherOptions.join(' ')} -o #{target} #{objs.map {|entity| linkArgsFor(entity)}.join(' ')}")
	end

end

#ar
class Ar
include StaticLibMaintainer

	public
	
	#I got this from http://zeljkofilipin.com/2006/02/09/ruby-deep-copy-object/;
	# apparently there isn't a better way to do a deep copy in ruby without a lot of coding -- EVH
	#return a deep copy of this object
	# (for Builders to create customized compilers without permanently changing our settings)
	def deepCopy()
		return Marshal::load(Marshal.dump(self))
	end
	
	#add or update object files in a static library
	#params: hash of param names to values
	#params we use:
	#  :lib => entity spec for (possibly nonexistent) static lib (ie abs Pathname)
	#  :objs => entity spec, or array of them, for objects to add to or update in the library
	#return: none
	def addOrUpdate(params)
		lib = requireParam(params, :lib)
		objs = ensureArray(requireParam(params, :objs))
		
		printAndCall("ar rv #{lib} #{objs.join(' ')}")
	end
	
	#index a static library (TODO does this have meaning on win32?)
	#libent: entity spec for static lib (ie abs Pathname)
	#return: none
	def index(libent)
		printAndCall("ar s #{libent}")
	end

end
