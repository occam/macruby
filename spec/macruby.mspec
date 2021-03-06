class MSpecScript
  # TODO: This doesn't work correctly yet.
  # load File.expand_path('../frozen/ruby.1.9.mspec', __FILE__)
  
  FROZEN_PREFIX = 'spec/frozen'
  load File.join(FROZEN_PREFIX, 'ruby.1.9.mspec')
  
  # Core library specs
  set :core, [
    'core',

    # obsolete in 1.9
    '^core/continuation',
    '^core/kernel/callcc_spec.rb',
    
    # Currently not working on MacRuby
    '^core/encoding'
  ]

  # Library specs
  set :library, [
    'library/abbrev',
    'library/base64',
    'library/cgi',
    'library/complex',
    'library/conditionalvariable',
    'library/csv',
    'library/date',
    'library/digest',
    'library/drb',
    'library/enumerator',
    'library/etc',
    'library/ftools',
    'library/generator', 
    'library/getoptlong',
    'library/ipaddr',
    'library/logger',
    'library/logger/application',
    'library/logger/device',
    'library/logger/logger',
    'library/mathn',
    'library/matrix',
    'library/mutex',
    'library/net',
    'library/net/telnet',
    'library/observer',
    'library/openstruct',
    'library/parsedate',
    'library/pathname',
    'library/ping',
    'library/rational',
    'library/queue',
    'library/readline',
    'library/resolv',
    'library/rexml',
    'library/scanf',
    'library/securerandom',
    'library/shellwords',
    'library/singleton',
    'library/socket',
    'library/stringio',
    'library/stringscanner',
    'library/tempfile',
    'library/time',
    'library/timeout',
    'library/tmpdir',
    'library/uri',
    'library/yaml/dump_spec.rb',
    'library/yaml/load_documents_spec.rb',
    'library/yaml/load_file.spec',
    'library/yaml/load_spec.rb',
    'library/yaml/tag_class_spec.rb',
    
     # Currently not working on MacRuby
     '^library/erb',
     '^library/iconv',
     '^library/generator',
     '^library/openssl',
     '^library/net/http', # due to '/fixtures/http_server' loaded in net/http/http/active_spec.rb  (webrick)
     '^library/net/ftp', # exists the specs when running using rake spec:library and reaching net/ftp/chdir_spec.rb
     
     '^library/prime',  # hangs probably because of timeout
     '^library/set', # sortedset is segfaulting
     '^library/syslog',
     
    
=begin
    # disabled the zlib specs for now because of a random GC crash
    # that seems to occur in gzipfile/closed_spec.rb
    'library/zlib/adler32_spec.rb',
    'library/zlib/crc32_spec.rb',
    'library/zlib/crc_table_spec.rb',
    'library/zlib/deflate'
=end
  ]
  
  # Prepend the paths with the proper prefix
  [:language, :core, :library].each do |pseudo_dir|
    set(pseudo_dir, get(pseudo_dir).map do |path|
      if path[0,1] == '^'
        "^#{File.join(FROZEN_PREFIX, path[1..-1])}"
      else
        File.join(FROZEN_PREFIX, path)
      end
    end)
  end
  
  set :macruby, ['spec/macruby']
  
  set :full, get(:macruby) + get(:language) + get(:core) + get(:library)
  
  # Optional library specs
  set :ffi, File.join(FROZEN_PREFIX, 'optional/ffi')
  
  # A list of _all_ optional library specs
  set :optional, [get(:ffi)]
  
  # All setup needed to run the specs from the macruby source root.
  #
  #
  # Make the macruby binary look for the framework in the source root
  source_root = File.expand_path('../../', __FILE__)
  ENV['DYLD_LIBRARY_PATH'] = source_root
  # Setup the proper load paths for lib and extensions
  load_paths = %w{ -I./lib -I./ext }
  load_paths.concat Dir.glob('./ext/**/*.bundle').map { |filename| "-I#{File.dirname(filename)}" }.uniq
  load_paths.concat(get(:flags)) if get(:flags)
  set :flags, load_paths
  # The default implementation to run the specs.
  set :target, File.join(source_root, 'macruby')
  
  set :tags_patterns, [
                        [%r(language/), 'tags/macruby/language/'],
                        [%r(core/),     'tags/macruby/core/'],
                        [%r(library/),  'tags/macruby/library/'],
                        [/_spec.rb$/,   '_tags.txt']
                      ]
end
