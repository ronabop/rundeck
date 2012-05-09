#
# Cookbook Name:: wt_cam
# Recipe:: pre
# Author: Kendrick Martin(<kendrick.martin@webtrends.com>)
#
# Copyright 2012, Webtrends
#
# All rights reserved - Do Not Redistribute
# This recipe sets up the base configuration for DX

log "Deploy build is #{ENV["deploy_build"]}"
if ENV["deploy_build"] == "true" then 
  include_recipe "wt_cam::uninstall" 
end


#Properties
install_dir = "#{node['wt_common']['install_dir_windows']}\\CAM"
install_logdir = node['wt_common']['install_log_dir_windows']
app_pool = node['wt_cam']['app_pool']
install_url = "#{node['wt_cam']['url']}#{node['wt_cam']['zip_file']}"

pod = node.chef_environment

iis_site 'Default Web Site' do
	action [:stop, :delete]
end

directory install_dir do
	recursive true
	action :create
end

iis_site 'CAM' do
    protocol :http
    port 80
    path install_dir
	action [:add,:start]
end

if ENV["deploy_build"] == "true" then 
  windows_zipfile install_dir do
    source install_url
    action :unzip	
  end
  
  template "#{install_dir}\\Webtrends.CamWeb.UI\\web.config" do
  	source "webConfig.erb"  
	variables(
  		:db_server => "(local)",
  		:user_id => "sa",
  		:password => "password"
  	)	
  end
  
  iis_pool app_pool do
	pipeline_mode :Integrated
  	runtime_version "4.0"
	action [:add, :config]
  end
  
  iis_app "CAM" do
  	path "/CamService"
  	application_pool app_pool
  	physical_path "#{install_dir}\\Webtrends.CamWeb.UI"
  	action :add
  end  
end