require 'fileutils'
require 'ostruct'
require 'pathname'
require 'yaml'

def build(base_dir, configuration, dep)
	root_dir = File.join(base_dir, dep.name)
	build_dir = File.join(root_dir, 'Build')
	
	# If the source files already exist, do nothing
	source_dir = File.join(root_dir, 'Source')
	if dep.files
		all_files_exist = false
		dep.files.each do |file|
			all_files_exist = File.exist?(File.join(source_dir, file))
			break if !all_files_exist
		end
		return if all_files_exist
	end
	
	# If the output file already exists, do nothing
	output = dep.output != nil ? dep.output : dep.name + '.framework'
	output_path = File.join(build_dir, configuration, output)
	return if File.exist?(output_path)
	
	# Fetch the source
	FileUtils.rm_rf(source_dir)
	abort if !system(
		'git',
		'clone',
		'--branch', dep.git_commit,
		'--depth', '1',
		dep.git_url,
		source_dir
	)
	
	# Build the source, only if no files are specified
	if !dep.files
		FileUtils.rm_rf(build_dir)
		FileUtils.mkdir_p(build_dir)
		FileUtils.chdir(source_dir) do
			scheme = dep.xcode_scheme != nil ? dep.xcode_scheme : dep.name
			abort if !system(
				'xcodebuild',
				'-scheme', scheme,
				'-configuration', configuration,
				'-derivedDataPath', File.join(build_dir, 'DerivedData'),
				'SYMROOT=' + build_dir,
			)
		end
	
		# Remove source
		FileUtils.rm_rf(source_dir)
	end
end

def main()
	project_dir = File.dirname(Pathname.new(__FILE__).realpath)
	base_dir = File.join(project_dir, 'Dependencies')
	deps = YAML.load_file(File.join(project_dir, 'dependencies.yml'))
	deps.each do |dep|
		# Set optional keys
		[
			['scheme', nil],
			['output', nil],
			['files', nil],
		].each do |item|
			key = item[0]
			default = item[1]
			dep[key] = default if !dep.key?(key)
		end

		build(base_dir, 'Release', OpenStruct.new(dep))
	end
end

main
