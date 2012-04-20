#
# Cookbook Name:: wt_streamingcollection
# Recipe:: default
#
# Copyright 2012, Webtrends
#
# All rights reserved - Do Not Redistribute
#

include_recipe "runit"

execute "install-java" do
  user "root"
  group "root"
  command "sudo add-apt-repository ppa:webupd8team/java;sudo apt-get update;sudo apt-get install oracle-java7-installer"
  action :run
end

log_dir      = File.join("#{node['wt_common']['log_dir_linux']}", "streamingcollection")
install_dir  = File.join("#{node['wt_common']['install_dir_linux']}", "streamingcollection")

tarball      = node[:tarball]
java_home    = node[:java_home]
download_url = node[:download_url]

log "Install dir: #{install_dir}"
log "Java home: #{java_home}"
log "Log dir: #{log_dir}"

directory "#{log_dir}" do
  owner   "#{node[:user]}"
  group   "#{node[:group]}"
  mode    "0755"
  recursive true
  action :create
end

directory "#{install_dir}/bin" do
  owner "root"
  group "root"
  mode "0755"
  recursive true
  action :create
end

remote_file "/tmp/#{tarball}" do
  source download_url
  mode "0644"
end

execute "tar" do
  user  "root"
  group "root" 
  cwd install_dir
  command "tar zxf /tmp/#{tarball}"
end

template "#{install_dir}/bin/streamingcollection.sh" do
  source  "streamingcollection.erb"
  owner "root"
  group "root"
  mode  "0755"
    variables({
                :log_dir => log_dir,
                :install_dir => install_dir,
                :java_home => java_home
              })
end

template "#{install_dir}/conf/netty.properties" do
  source  "netty.properties.erb"
  owner   "root"
  group   "root"
  mode    "0644"
  variables({
              :port => node[:wt_streamingcollection][:port]
            })
end

template "#{install_dir}/conf/kafka.properties" do
  source  "kafka.properties.erb"
  owner   "root"
  group   "root"
  mode    "0644"
  variables({
              :zk_connect => node[:zookeeper][:quorum][0]
            })
end

execute "delete_install_source" do
    user "root"
    group "root"
    command "rm -f /tmp/#{tarball}"
    action :run
end

runit_service "streamingcollection" do
    options({
        :log_dir => log_dir,
        :install_dir => install_dir,
        :java_home => java_home
      }) 
end 
