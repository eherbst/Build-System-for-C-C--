#Compiler: interfaces for functionality we expect the compilation system to take care of
#Evan Herbst, 12 / 5 / 08

require 'pathname'
require 'System'

#interface for compilers that can handle C/C++
module CXXCompiler

	public
	
	#add include dirs
	#incdirs: abs Pathname or array of them
	#return: none
	def addIncludeDirs(incdirs)
		raise "to be implemented by subclasses"
	end
	
	#add flags (they'll go before flags added internally by this object)
	#flags: string or array of them
	#return: none
	def addCFlags(flags)
		raise "to be implemented by subclasses"
	end

	#replace all flags other than include dirs
	#flags: string or array of them
	#return: none
	def setCFlags(flags)
		raise "to be implemented by subclasses"
	end

	#add flags (they'll go before flags added internally by this object)
	#flags: string or array of them
	#return: none
	def addCXXFlags(flags)
		raise "to be implemented by subclasses"
	end

	#replace all flags other than include dirs
	#flags: string or array of them
	#return: none
	def setCXXFlags(flags)
		raise "to be implemented by subclasses"
	end
	
	#run something equivalent to gcc to get source-file dependences; parse the output and return all resulting header filenames
	#builder: Builder
	#srcfile: entity spec
	#print: bool, whether to print that we're running (probably no if the run is on a file created by the build system)
	#return: enumerable of rel/abs filepath strings
	def getHeaderDependencesAbsOrRel(builder, srcfile, print)
		raise "to be implemented by subclasses"
	end
	
	#params: hash of param names to values
	#params we use:
	#  :src => source file entity spec
	#  :target => output file entity spec
	#  :opts (optional) => string of other options -- will be given before all other options generated from params
	#return: none
	def compileCXX(params)
		raise "to be implemented by subclasses"
	end
	
end

#interface for compilers that can handle fortran
module FortranCompiler

	public
	
	#params: hash of param names to values
	#params we use:
	#  :src => source file entity spec
	#  :target => output file entity spec
	#  :opts (optional) => string of other options -- will be given before all other options generated from params
	#return: none
	def compileFortran(params)
		raise "to be implemented by subclasses"
	end

end

#interface for linkers
module Linker

	public
	
	#params: hash of param names to values
	#params we use:
	#  :objs => entity spec for entity to be linked, or array of them
	#  :target => output file entity spec
	#  :opts (optional) => string of other options -- will be given before all other options generated from params
	#return: none
	def link(params)
		raise "to be implemented by subclasses"
	end
	
end

#interface for building static libraries
module StaticLibMaintainer

	public
	
	#add or update object files in a static library
	#params: hash of param names to values
	#params we use:
	#  :lib => entity spec for (possibly nonexistent) static lib (ie abs Pathname)
	#  :objs => entity spec, or array of them, for objects to add to or update in the library
	#return: none
	def addOrUpdate(params)
		raise "to be implemented by subclasses"
	end
	
	#index a static library (TODO does this have meaning on win32?)
	#libent: entity spec for static lib (ie abs Pathname)
	#return: none
	def index(libent)
		raise "to be implemented by subclasses"
	end

end

#give BuildEnv some support for the various types of compilation we provide
module BuildEnv

	private
	
	#cache once they've been created once
	@@cxxCompiler = nil
	@@fortranCompiler = nil
	@@linker = nil
	@@staticLibMaintainer = nil

	public
	
	#the various compiler objects should only be used through these interfaces, to ensure they get created when needed
	
	#return: CXXCompiler
	def self.cxxCompiler()
		if !@@cxxCompiler
			@@cxxCompiler = BuildEnv::createCXXCompiler()
		end
		return @@cxxCompiler
	end
	
	#return: FortranCompiler
	def self.fortranCompiler()
		if !@@fortranCompiler
			@@fortranCompiler = BuildEnv::createFortranCompiler()
		end
		return @@fortranCompiler
	end
	
	#return: Linker
	def self.linker()
		if !@@linker
			@@linker = BuildEnv::createLinker()
		end
		return @@linker
	end
	
	#return: StaticLibMaintainer
	def self.staticLibMaintainer()
		if !@@staticLibMaintainer
			@@staticLibMaintainer = BuildEnv::createStaticLibMaintainer()
		end
		return @@staticLibMaintainer
	end

end
