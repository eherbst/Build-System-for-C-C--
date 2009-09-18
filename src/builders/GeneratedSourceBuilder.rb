require 'Builder'

#for generated source-code files, which includes headers (as opposed to 'source files', which in my terminology doesn't)
class GeneratedSourceBuilder < Builder

	public
	
	#params we use:
	#  :inputs => script filename and any input files it uses (type: Pathname or array of them)
	#  :cmd => command to run
	#  :output => (abs or rel to cwd) Pathname for output file, or array of them
	def initialize(params)
		super
		inputs = ensureArray(requireParam(params, :inputs))
		@cmd = requireParam(params, :cmd)
		outputs = ensureArray(requireParam(params, :output)).map {|filepath| if filepath.relative? then canonicalizeFilepath(filepath, Dir.pwd()) else filepath end}
		
		inputs.each {|filepath| addPrereq filepath}
		outputs.each {|filepath| addTarget filepath; BuildEnv::setEntityBuilt filepath}
		outputs.each {|filepath| BuildEnv::addGeneratedFile filepath}
	end
	
	#update dependences (in BuildEnv and in rake) as necessary at build time
	#return: whether we're done updating and can progress to actual build steps
	def updateDeps(rakeTask)
		#no-op
	end

	#run build commands
	#return: none
	def build(rakeTask)
		printAndCall(@cmd)
	end

end
