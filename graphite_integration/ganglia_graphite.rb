#!/usr/bin/ruby -d

#################################################################################
# Parse Ganglia XML stream and send metrics to Graphite
# License: Same as Ganglia
# Author: Vladimir Vuksan, Sean Treadway
# Modified from script written by: Kostas Georgiou
#################################################################################
require "nokogiri"
require 'socket'

ganglia, graphite = ARGV

if !ganglia || !graphite
  puts "Usage: #{$0} ganglia.host:port graphite.host:port"
  puts "  Optionally use '-' for either ganglia or graphite to use"
  puts "  stdin or stdout respectively"
  puts
  puts "  Example:"
  puts "    bundle install # once"
  puts "    bundle exec #{$0} ganglia -"
  exit 1
end

ganglia_hostname, ganglia_port = ganglia.to_s.split(":")
ganglia_port ||= 8651

graphite_host, graphite_port = graphite.to_s.split(":")
graphite_port ||= 2003

# Open up a socket to gmond
source =
  if ganglia_hostname == '-'
    $stdin
  else
    TCPSocket.open(ganglia_hostname, ganglia_port.to_i)
  end

# Open up a socket to graphite
dest =
  if graphite_host == "-"
    $stdout
  else
    TCPSocket.open(graphite_host, graphite_port.to_i)
  end

# Parse the XML we got from gmond
doc = Nokogiri::XML source

doc.xpath("//METRIC[@TYPE!='string']").each do |metric|
  path = metric.xpath("ancestor-or-self::*").                                 # All parents
    map        { |node| node["NAME"] }.                                       # Use root/grid/cluster/host/metric tree
    compact.                                                                  # Remove nameless nodes (root)
    inject([]) { |parts, name| parts << name.gsub("."+parts.last.to_s, '') }. # Remove redundant parts of the name
    map        { |name| name.gsub(/[ .]/, '_') }.                             # Normalize names to graphite's expectation
    join(".")

  # Use ganglia's value, ignoring the units
  value = metric["VAL"]

  # Use ganglia's reported time so our writes are idempotent
  time = metric.parent["REPORTED"]

  dest.puts("%s %s %s" % [ path, value, time ])
end

source.close
dest.close
