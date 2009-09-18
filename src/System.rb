#System: represent the OS and filesystem, and any OS-specific information that goes into building
#Evan Herbst, 12 / 5 / 08

require 'pathname'

#currently linux
module System

	private
	
	#the dir named in TMPDIR should already exist; we might make subdirs
	@@TMPDIR = Pathname.new('/tmp')

	public
	
	#return: temporary directory Pathname
	def self.tmpdir()
		return @@TMPDIR
	end
	
	#create as much of the path as doesn't exist (like rake's mkdir_p but don't print except on error)
	#dirpath: String
	#return: none
	def self.createPath(dirpath)
		`mkdir -p #{dirpath}`
		raise "couldn't create path #{dirpath}" if $?.to_i != 0
	end
	
##### filename conversions #####

	public

	#module name -> header filename (don't require file to exist)
	#modname: Pathname or String
	#return: corresponding header filename as a Pathname
	def self.mod2hdr(modname)
		return Pathname.new(modname.to_s + '.h') #need the to_s; otherwise it adds a path entry
	end

	#module name -> object filename (don't require file to exist)
	#modname: Pathname or String
	#return: corresponding object filename as a Pathname
	def self.mod2obj(modname)
		return Pathname.new(modname.to_s + '.o') #need the to_s; otherwise it adds a path entry
	end
	
	#module name -> static library filename (don't require file to exist)
	#modname: Pathname or String
	#return: corresponding static-lib filename as a Pathname
	def self.mod2slib(modname)
		return modname.dirname().join('lib' + modname.basename().to_s + '.a') #need the to_s; otherwise it adds a path entry
	end
	
##### operations useful for building #####

	public
	
	$RM = 'rm -fv'

	#delete the specified files
	#filepaths: abs Pathname or array of them
	#return: none
	def self.clean(filepaths)
		printAndCall("#{$RM} #{ensureArray(filepaths).join(' ')}")
	end
	
	#create a symlink to target named linkname
	#links: hash of linkname => target, where each linkname and target are abs Pathnames
	def self.symlink(links)
		links.each_pair do |linkname, target|
			if `readlink -f #{linkname}`.chomp != target.to_s #don't print unless we actually have to change something; might confuse the user
				printAndCall("ln -sf #{target} #{linkname}")
			end
		end
	end

end
