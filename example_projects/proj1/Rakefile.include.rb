#extend Evan's C/C++-based-project build system framework built on rake

require 'build_system/build-framework'

######################################################################################
###extend build-framework by adding project-specific vars (some of which must be global) and project-specific functions here if you want
###(for instance, you might want to change file extension info in the filename-conversion functions)
#project-wide build environment
#for projects involving compile and link stages, and possibly generated source code
#a module, but not meant to be mixed in
module BuildEnv
	
##### project setup #####

	private
	
	#globals ($...) are meant to be available to all rakefiles
	#ENV is a rake thing: if the user calls 'rake KEY=VAL target', ENV will be {'KEY' => 'VAL'}

	PROJROOT = Dir.pwd() #project root
	@@build_dirname = File.join('build', ENV['opt'] || 'default') #all built files are put in PROJROOT/build_dirname/...
	SRC1 = File.join(PROJROOT, 'src1')
	SRC2 = File.join(PROJROOT, 'src2')
	SHARED_SRC = "#{PROJROOT}/../shared-code" #a source tree not inside this project's root dir
	
	#return: Pathname for project root dir
	def self.projrootPathname()
		return Pathname.new(PROJROOT)
	end
	
	#return: array of Pathnames to roots of project source trees
	def self.sourceTreeRoots()
		return [SRC1, SRC2, SHARED_SRC].map {|dir| Pathname.new dir}
	end
	
	#return: Pathname to root of project build tree
	def self.buildTreeRoot()
		return projrootPathname().join(@@build_dirname)
	end
	
	#create compiler objects needed for the project, with default settings (to be overridden in special cases by Builders)
	#(ie implement one or more of the create*() functions referenced in Compiler.rb)
	#don't worry about caching compilers; that's done in the build framework
	
	#return: CXXCompiler
	def self.createCXXCompiler()
		_GCC = ENV['CXX'] || 'g++'
		_CXXFLAGS = []
		_OPTIM_FLAGS = case ENV['opt']
			when '3' then ['-O3']
			when 'g2' then ['-g', '-O2']
			else ['-g']
		end
		_CXXFLAGS += ['-Wall'] + _OPTIM_FLAGS
		_LDFLAGS = _OPTIM_FLAGS
		#other incdirs will be added when we process project-external shared libs
		_INCDIRS = [SRC1, SRC2, SHARED_SRC].map {|dirname| Pathname.new(dirname)}
		return GCC::new({:gcc => _GCC, :cflags => _CXXFLAGS, :cxxflags => _CXXFLAGS, :ldflags => _LDFLAGS, :incdirs => _INCDIRS})
	end
	
	#return: Linker
	def self.createLinker()
		return createCXXCompiler()
	end

##### project-specific libs #####

	private
	
	BOOST_INCDIR = '/usr/local/include/boost-1_37'
	BOOST_LIBDIR = '/usr/local/lib/boost-1_37'
	def self.boostlibname(namebase) return "boost_#{namebase}-gcc43-mt-1_37" end
	PROJ_SHARED_DATA_DIR = '/some/made-up/dir'
	CLAPACKDIR = "/username/libs/clapack-3.1.1"
	CLAPACK_INCDIR = "#{CLAPACKDIR}/INCLUDE"
	ARPACKPP_INCDIR = "/username/libs/arpack++/include" #sparse eigensolving via the ARnoldi method
	
	#####
	#declare external libraries (this could be done in a separate file shared among projects)
	#
	#this section is all commented out so you can run the build system on this example project, because you probably don't have all these libs on your system
	
#	cxxCompiler().addIncludeDirs Pathname.new(BOOST_INCDIR) #more efficient than declaring all of boost as a header-only lib
	
	#relative header paths for a given lib will be absolutized using that lib's given incdirs and the compiler's default search path
	
	#boost
#	ExtlibRegistry::registerLib(:sym => :boost_system, :name => boostlibname('system'), :dir => BOOST_LIBDIR, :incdirs => BOOST_INCDIR, :headers => ["#{BOOST_INCDIR}/boost/system.hpp", FileList["#{BOOST_INCDIR}/boost/system/*.hpp"]])
#	ExtlibRegistry::registerLib(:sym => :boost_filesystem, :name => boostlibname('filesystem'), :dir => BOOST_LIBDIR, :incdirs => BOOST_INCDIR, :headers => "#{BOOST_INCDIR}/boost/filesystem.hpp", :requires => :boost_system)
#	ExtlibRegistry::registerLib(:sym => :boost_iostreams, :name => boostlibname('iostreams'), :dir => BOOST_LIBDIR, :incdirs => BOOST_INCDIR, :headers => FileList["#{BOOST_INCDIR}/boost/iostreams/*.hpp"])
#	ExtlibRegistry::registerLib(:sym => :boost_regex, :name => boostlibname('regex'), :dir => BOOST_LIBDIR, :incdirs => BOOST_INCDIR, :headers => "#{BOOST_INCDIR}/boost/regex.hpp")
#	ExtlibRegistry::registerLib(:sym => :boost_serialization, :name => boostlibname('serialization'), :dir => BOOST_LIBDIR, :incdirs => BOOST_INCDIR, :headers => [FileList["#{BOOST_INCDIR}/boost/serialization/*.hpp"], FileList["#{BOOST_INCDIR}/boost/archive/*.hpp"]])
#	ExtlibRegistry::registerLib(:sym => :boost_program_options, :name => boostlibname('program_options'), :dir => BOOST_LIBDIR, :incdirs => BOOST_INCDIR, :headers => "#{BOOST_INCDIR}/boost/program_options.hpp")
	
	#a dependee lib must be declared before all dependent libs
#	ExtlibRegistry::registerLib(:sym => :pthread, :headers => "pthread.h")
#	ExtlibRegistry::registerLib(:sym => :boost_thread, :name => boostlibname('thread'), :dir => BOOST_LIBDIR, :incdirs => BOOST_INCDIR, :headers => "#{BOOST_INCDIR}/boost/thread/thread.hpp", :requires => :pthread)
	
	#math
#	ExtlibRegistry::registerLib(:sym => :gmp, :dir => '/uns/lib') #Gnu Multi-Precision float ops
#	ExtlibRegistry::registerLib(:sym => :atlas, :dir => '/usr/lib/atlas') 
#	ExtlibRegistry::registerLib(:sym => :lapack, :dir => '/usr/lib', :incdirs => CLAPACK_INCDIR, :headers => ["#{CLAPACK_INCDIR}/clapack.h", FileList["#{BOOST_INCDIR}/boost/numeric/bindings/lapack/*.hpp"]])
#	ExtlibRegistry::registerLib(:sym => :gnu_fortran, :name => 'gfortran')
#	ExtlibRegistry::registerLib(:sym => :gnu_f2c, :name => 'g2c', :dir => "#{PROJ_SHARED_DATA_DIR}/lib") #gcc 3.4 appears to be the last release series containing g77 (and g95 doesn't have libg2c), so this points to the gcc 3.4.6 lib dir
#	ExtlibRegistry::registerLib(:sym => :arpack, :name => 'arpack-debug_linux32', :dir => "#{PROJ_SHARED_DATA_DIR}/lib", :incdirs => ARPACKPP_INCDIR, :headers => FileList["#{ARPACKPP_INCDIR}/*.h"], :requires => [:gnu_fortran, :gnu_f2c, :lapack])
	
	#graphics
#	ExtlibRegistry::registerLib(:sym => :X11)
#	ExtlibRegistry::registerLib(:sym => :gl, :name => 'GL', :headers => "GL/gl.h")
#	ExtlibRegistry::registerLib(:sym => :glu, :name => 'GLU', :headers => "GL/glu.h", :requires => :gl)
#	ExtlibRegistry::registerLib(:sym => :glut, :headers => "GL/glut.h", :requires => :glu)
	
	#demonstrate a header-only extlib (:name => nil)
#	ExtlibRegistry::registerLib(:sym => :headers_only, :name => nil, :incdirs => '/some/dir', :headers => FileList["/some/dir/**/*.h"])
	
	#####
	#list the libs we actually need for this project
	#
	#if we list, eg, glut here, we need to list glu and gl (its dependences) too
	#
	#again, wouldn't be commented out in a real project
	
#	use3pLibs :boost_regex
#	use3pLibs :boost_serialization
#	use3pLibs [:lapack, :atlas]
	
end

######################################################################################
### extend build-framework by adding project-specific Builder subclasses here if you want

######################################################################################
### extend build-framework by adding factory functions for project-specific builders here if you want
#one Raker per directory; created in rakefiles
#any cleaning of pathnames from outside this file is done in this class (ie there might not be any done, but if you want to add it, do that here)
class Raker
##### for rakefile use #####
	public
end
