require 'Builder'

#run Qt's MOC preprocessor on a header file
class QtMocBuilder < Builder

	public
	
	#params we use:
	#  :input => header filepath: (abs or rel to cwd) Pathname
	#  :mocpath => path to MOC, including filetitle
	#  :output (optional) => moc output filename: (abs or rel to cwd) Pathname
	def initialize(params)
		super
		@input = requireParam(params, :input)
		@mocpath = params[:mocpath]
		inEntityType, inModuleName = BuildEnv::entityTypeSafe(@input)
		if params[:output]
			outputName = canonicalizeFilepath(Pathname.new(params[:output]), BuildEnv::src2build(Pathname.pwd()))
		elsif inEntityType == :h
			outputName = QtMocBuilder::mod2moc(inModuleName)
		else
			raise "Name of file to feed to moc must end in header extension: #{@input}"
		end
		@output = canonicalizeFilepath(Pathname.new(outputName), Pathname.pwd())
		
		addPrereq @input
		addTarget @output
		BuildEnv::addGeneratedFile(@output)
		raker = BuildEnv::raker(dir())
		raker.associate(@input => [@output])
		outModuleName = BuildEnv::entityType(@output)[1]
		outModuleName = BuildEnv::src2build(canonicalizeFilepath(outModuleName, Pathname.pwd()))
		CXXObjBuilder.new(:name => outModuleName, :src => @output)
	end
	
	#update dependences (in BuildEnv and in rake) as necessary at build time
	#return: whether we're done updating and can progress to actual build steps
	def updateDeps(rakeTask)
		return true
	end

	#run build commands
	#return: none
	def build(rakeTask)
		unless uptodate?(@output, [@input]) #the check rake does always fails because it includes non-file prereq tasks, so do our own
			printAndCall("#{@mocpath} -o #{@output} #{@input}")
		end
	end

	def self.mod2moc(modname)
		mocname = "moc_#{modname}.cpp"
		return canonicalizeFilepath(Pathname.new(mocname), BuildEnv::src2build(Pathname.pwd()))
	end
end
