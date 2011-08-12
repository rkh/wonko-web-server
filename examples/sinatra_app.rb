#!/usr/bin/env ruby -I../lib
require 'sinatra'

set :server, 'wonko'
disable :logging

get '/' do
  sleep 0.1
  "#{Process.pid}\n"
end
