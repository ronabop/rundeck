#
# Cookbook Name:: wt_publishver
# Provider:: linux
# Author:: David Dvorak(<david.dvorakd@webtrends.com>)
#
# Copyright 2013, Webtrends Inc.
#
# All rights reserved - Do Not Redistribute
#

action :deploy_prereqs do

	require 'rbconfig'

	# working directories
	wdir = ::File.join(Chef::Config[:file_cache_path], 'wt_publishver')
	gdir = ::File.join(wdir, 'gems')
	idir = ::File.join(wdir, 'include')
	ldir = ::File.join(wdir, 'lib')

	ENV['GEM_HOME'] = gdir

	# determine if cache should be cleared
	clear_cache = false
	if node.has_key? 'wt_publishver'
		clear_cache = true if node['wt_publishver']['ruby_version'] != RbConfig::CONFIG['ruby_version']
		clear_cache = true if node['wt_publishver']['ruby_bindir'] != RbConfig::CONFIG['bindir']
		clear_cache = true if node['wt_publishver']['chef_version'] != node['chef_packages']['chef']['version']
	end

	# clear cache
	if clear_cache
		directory wdir do
			recursive true
			action :nothing
		end.run_action :delete
	end

	# save current values for next run
	node.set['wt_publishver']['ruby_version'] =  RbConfig::CONFIG['ruby_version']
	node.set['wt_publishver']['ruby_bindir'] = RbConfig::CONFIG['bindir']
	node.set['wt_publishver']['chef_version'] = node['chef_packages']['chef']['version']

	remote_directory wdir do
		source 'prereqs'
		overwrite true
		action :nothing
	end.run_action :create

	execute 'extract libs' do
		command "tar xzf #{::File.join(wdir, 'libs.tgz')} -C #{wdir}"
		creates idir
		action :nothing
	end.run_action :run

	# this is a precompiled gem
	gem_package 'nokogiri' do
		gem_binary ::File.join(RbConfig::CONFIG['bindir'], 'gem')
		source ::File.join(wdir, 'nokogiri-1.5.9-x86_64-linux.gem')
		options "--install-dir #{gdir}"
		action :nothing
	end.run_action :install

	gem_list = ['little-plugger-1.1.3', 'multi_json-1.5.0', 'logging-1.6.1', 'httpclient-2.2.4', 'rubyntlm-0.1.2', 'viewpoint-spws-0.5.0.wt', 'manifest-1.0.0']
	gem_list.each do |gem|
		gem_package gem[/^(.*)-[\d\.wt]+?/, 1] do
			gem_binary ::File.join(RbConfig::CONFIG['bindir'], 'gem')
			source ::File.join(wdir, "#{gem}.gem")
			options "--install-dir #{gdir} --ignore-dependencies --force"
			action :nothing
		end.run_action :install
	end

	::Gem.clear_paths

	require 'viewpoint/spws'
	require 'manifest'

end

action :update do

	Chef::Log.debug("Running #{@new_resource.name} in #{@new_resource.provider} from #{@new_resource.cookbook_name}::#{@new_resource.recipe_name}")

	# expand wildcards
	key_file = Dir[@new_resource.key_file].sort.first

	if key_file.nil?
		log("key_file: #{@new_resource.key_file} not found") { level :warn }
		next
	end

	# gets teamcity data
	pub = ::WtPublishver::Publisher.new @new_resource.download_url

	# set values for sp_query
	pub.hostname  = node['hostname']
	pub.pod       = node.chef_environment
	pub.role      = @new_resource.role
	pub.selectver = @new_resource.select_version

	# query sharepoint
	items = pub.sp_query
	if items.count == 0
		log("No records found: hostname => #{pub.hostname}, pod => #{pub.pod}, role => #{pub.role}") { level :warn }
		log('No publish version update performed') { level :warn }
		next
	end
	if items.count > 1
		log("More than 1 record found for: hostname => #{pub.hostname}, pod => #{pub.pod}, role => #{pub.role}") { level :warn }
		log('Please refine criteria. No publish version update performed') { level :warn }
		next
	end
	pub.oitem = ::WtPublishver::PublisherItem.new items.first
	pub.nitem = ::WtPublishver::PublisherItem.new items.first

	#
	# get new data to publish
	#

	# version (should start with a digit)
	pub.nitem.version = ENV['wtver'] if ENV['wtver'] =~ /^\d/

	# branch
	if pub.is_tc?
		pub.nitem.branch = "#{pub.project_name}_#{pub.buildtype_name}".gsub(/ /, '_')
	else
		pub.nitem.branch = pub.download_server
	end

	# build number (should be derived from key_file and not TC)
	case key_file
	when /\.jar$/
		pub.nitem.build = pub.jar_build key_file
	else
		log('key_file type not supported') { level :warn }
		pub.nitem.build = pub.build_number.to_s
	end

	# set os
	pub.nitem.os = get_osversion

	# set status
	case @new_resource.status
	when :up
		pub.nitem.status = 'Up'
	when :down
		pub.nitem.status = 'Down'
	when :pending
		pub.nitem.status = 'Pending'
	when :unknown
		pub.nitem.status = 'Unknown'
	end

	if pub.changed?
		puts "\nPod Details: BEFORE\n"
		puts pub.oitem.formatted
		printf("\n%-7s : %s\n", 'KeyFile', key_file)
		pub.sp_update
		puts "\nPod Details: AFTER\n"
		puts ( ::WtPublishver::PublisherItem.new pub.sp_query.first ).formatted
		puts "\n"
	else
		log 'Pod Detail field values are the same.  No update performed.'
	end

end

private

def get_osversion

	case node['platform']
	when 'ubuntu'
		os_name = 'Ubuntu'
		case node['platform_version']
		when '10.04'
			os_name << ' 10.04 LTS'
		when '12.04'
			os_name << ' 12.04 LTS'
		when '14.04'
			os_name << ' 14.04 LTS'
		else
			return nil
		end
	when 'centos'
		os_name = 'CentOS'
		case node['platform_version']
		when '6.2'
			os_name << ' 6.2'
		when '6.3'
			os_name << ' 6.3'
		else
			return nil
		end
	else
		return nil
	end

	return os_name

end
