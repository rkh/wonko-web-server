require 'wonko'
require 'rack'

module Wonko
  module Utils
    include Rack::Utils
    extend self

    def cpu_count
      return Java::Java.lang.Runtime.getRuntime.availableProcessors if defined? Java::Java
      return File.read('/proc/cpuinfo').scan(/^processor\s*:/).size if File.exist? '/proc/cpuinfo'
      require 'win32ole'
      WIN32OLE.connect("winmgmts://").ExecQuery("select * from Win32_ComputerSystem").NumberOfProcessors
    rescue LoadError
      Integer `sysctl -n hw.ncpu 2>/dev/null` rescue 1
    end
  end
end
