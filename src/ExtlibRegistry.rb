#ExtlibRegistry: keep track of external libs installed on the system
#Evan Herbst, 12 / 5 / 08

require 'pathname'
require 'System'

module ExtlibRegistry

	private
	
	@@libsBySymbol = Hash.new #lib symbol =>
	                          #  {
	                          #   :name => lib basename (goes between 'lib' and extension) as a string (or nil for a header-only lib), 
	                          #   :dir => (abs Pathname | nil) for the lib itself,
	                          #   :incdirs => array of directories for include files,
	                          #   :headers => array of abs header filepaths (Pathnames)
	                          #   :requires => array of libsyms this lib depends on
	                          #  }
	
	public
	
	#libsym: a lib symbol
	#return: the hash associated with the given symbol, or nil if no such symbol is registered
	def self.get(libsym)
		return @@libsBySymbol[libsym]
	end
	
	#tell the build system about a library provided by a third party
	#params we use:
	#  :sym => symbol to uniquely identify lib
	#  :name (optional; default params[:sym]) => part of filetitle after 'lib', or nil for a header-only lib
	#  :dir (optional; default is hope the compiler's search path is enough) => string or Pathname for the dir containing the lib
	#  :incdirs (optional; default is hope the compiler's search path is enough) => string or array of them
	#    (incdirs can't be inferred from header filenames reasonably quickly)
	#  :headers (optional) => string, Pathname, FileList or array of those giving absolute or relative filepaths of associated header files
	#  :requires (optional; default []) => *previously declared* lib symbol or array of them
	def self.registerLib(params)
		sym = requireParam(params, :sym)
		basename = params.has_key?(:name) ? params[:name] : sym.to_s
		dir = params.has_key?(:dir) ? absolutizeDir(Pathname.new(params[:dir]), Pathname.pwd()) : nil
		headers = params.has_key?(:headers) ? flattenPathArray(ensureArray(params[:headers])) : []
		incdirs = params.has_key?(:incdirs) ? flattenPathArray(ensureArray(params[:incdirs])) : []
		libs = params.has_key?(:requires) ? ensureArray(params[:requires]) : []
		libs.each {|deplib| raise "extlib declaration for #{sym} references unknown lib #{deplib}" unless @@libsBySymbol.has_key?(deplib)}

		#the client shouldn't be declaring a lib twice (nothing wrong with it from a technical standpoint, but not logical)
		raise "multiple declaration of external lib #{sym}" if @@libsBySymbol[sym]
		
		#to find relative hdr filenames, use a reasonable default include path (ideally the same one the compiler uses less the compiler-internal dirs)
		relativeHeaders = headers.select {|filepath| filepath.relative?}
		searchPath = ['/usr/include', '/usr/local/include'] + incdirs
		processedHeaders = relativeHeaders.map do |relpath|
			incdir = searchPath.find {|searchdir| Pathname(searchdir).join(relpath).exist?} #first element for which filter is true
			incdir || raise("can't locate header #{relpath} used by external lib #{sym}; update either the :incdirs for extlib #{sym} or the default search path")
			fullpath = Pathname(incdir).join(relpath)
		end
		headers = (headers - relativeHeaders + processedHeaders).map {|filepath| realFilepath(filepath)}

		@@libsBySymbol[sym] = {:name => basename, :dir => dir, :incdirs => incdirs, :headers => headers, :requires => libs}
	end
	
	#filepath: absolute Pathname
	#return: the lib symbol of some lib (and ideally there is only one such lib) the given header was specified as part of, or nil if none
	def self.libIncludingHeader(filepath)
		@@libsBySymbol.each do |libsym, info|
			return libsym if info[:headers].index(filepath) #index() returns nil if not found
		end
		return nil
	end
	
	#libsym: extlib symbol
	#return: the list of incdirs for the given lib
	def self.incdirsForLib(libsym)
		raise "unknown extlib #{libsym}" unless @@libsBySymbol.has_key?(libsym)
		return @@libsBySymbol[libsym][:incdirs]
	end

end
