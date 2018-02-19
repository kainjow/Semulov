$deps = [
	{
		'name' => 'Sparkle',
		'git_url' => 'https://github.com/sparkle-project/Sparkle.git',
		'git_commit' => '1.18.1',
	},
	{
		'name' => 'MASShortcut',
		'git_url' => 'https://github.com/shpakovski/MASShortcut.git',
		'git_commit' => '2.3.6',
	},
]

# # #

require 'fileutils'
require 'ostruct'
require 'pathname'

def build(base_dir, configuration, dep)
	root_dir = File.join(base_dir, dep.name)
	build_dir = File.join(root_dir, 'Build')
	
	# If the output file already exists, do nothing
	output = dep.output != nil ? dep.output : dep.name + '.framework'
	output_path = File.join(build_dir, configuration, output)
	return if File.exist?(output_path)
	
	# Fetch the source
	source_dir = File.join(root_dir, 'Source')
	FileUtils.rm_rf(source_dir)
	abort if !system(
		'git',
		'clone',
		'--branch', dep.git_commit,
		'--depth', '1',
		dep.git_url,
		source_dir
	)
	
	# Build the source
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

def main()
	base_dir = File.join(File.dirname(Pathname.new(__FILE__).realpath), 'Dependencies')

	$deps.each do |dep|
		# Set optional keys
		['scheme', 'output'].each do |key|
			dep[key] = nil if !dep.key?(key)
		end

		build(base_dir, 'Release', OpenStruct.new(dep))
	end
end

main
