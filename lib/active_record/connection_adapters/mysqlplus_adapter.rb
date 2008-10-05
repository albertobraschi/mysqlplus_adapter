begin
  require_library_or_gem('mysqlplus')
rescue LoadError
  $stderr.puts '!!! The mysqlplus gem is required!'
  raise
end
require 'active_record/connection_adapters/mysql_adapter'

module ActiveRecord
  module ConnectionAdapters
    class ConnectionPool
      attr_reader :connections, 
                  :checked_out
      
      def initialize(spec)
        @spec = spec
        # The cache of reserved connections mapped to threads
        @reserved_connections = {}
        # The mutex used to synchronize pool access
        @connection_mutex = Monitor.new
        @queue = @connection_mutex.new_cond
        # default 5 second timeout
        @timeout = spec.config[:wait_timeout] || 5
        # default max pool size to 5
        @size = (spec.config[:pool] && spec.config[:pool].to_i) || 5
        @connections = []
        @checked_out = []
        warmup!
      end
      
      alias :original_checkout_existing_connection :checkout_existing_connection
      
      def checkout_existing_connection
        c = (@connections - @checked_out).detect{|c| c.ready? }
        checkout_and_verify(c)
      end
            
      private
      
        def warmup!
          @connection_mutex.synchronize do
            1.upto(@size) do
              c = new_connection
              @connections << c
            end
          end  
        end  
     
    end  
  end    
end

module ActiveRecord
  module Deferrable
    
    def self.included(base)
      base.extend( SingletonMethods )
    end
    
    module SingletonMethods
      def defer(*methods)
        methods.each do |method|
          class_eval <<-EOS
            def #{method}_with_defer(*args, &block)
              ActiveRecord::Deferrable::Result.new do
                #{method}_without_defer(*args, &block)
              end
            end

            alias_method_chain :#{method}, :defer
          EOS
        end
      end      
    end
    
    class Result < ActiveSupport::BasicObject

      def initialize( &query )
        @query = query
        defer!
      end

      def defer!
        @result = Thread.new(@query) do |query|
          begin
            query.call    
          ensure
            ::ActiveRecord::Base.connection_pool.release_connection
          end    
        end
      end

      def method_missing(*args, &block)
        @_result ||= @result.value
        @_result.send(*args, &block)
      end 

    end    
  end  
end

module ActiveRecord
  class Base
    include ActiveRecord::Deferrable    
    
    class << self
      include ActiveRecord::Deferrable    
      defer :find_by_sql,
            #:exists?, # yields syntax err. with alias_method_chain
            :update_all,
            :delete_all,
            :count_by_sql,
            #:table_exists?, # yields syntax err. with alias_method_chain
            :columns
    end   
    
    defer :destroy,
          :update,
          :create            
    
  end
end
module ActiveRecord
  module ConnectionAdapters
    class MysqlplusAdapter < ActiveRecord::ConnectionAdapters::MysqlAdapter

      def socket
        @connection.socket
      end

      def ready?
        @connection.ready?        
      end
      
      def execute(sql, name = nil) #:nodoc:
        log(sql,name) do 
          @connection.c_async_query(sql)
        end
      end
 
    end
  end
end

module ActiveRecord
  class << Base
    
    def mysqlplus_connection(config)
      config = config.symbolize_keys
      host     = config[:host]
      port     = config[:port]
      socket   = config[:socket]
      username = config[:username] ? config[:username].to_s : 'root'
      password = config[:password].to_s

      if config.has_key?(:database)
        database = config[:database]
      else
        raise ArgumentError, "No database specified. Missing argument: database."
      end      
          
      mysql = Mysql.init
      mysql.ssl_set(config[:sslkey], config[:sslcert], config[:sslca], config[:sslcapath], config[:sslcipher]) if config[:sslca] || config[:sslkey]

      ConnectionAdapters::MysqlplusAdapter.new(mysql, logger, [host, username, password, database, port, socket], config)    
    end
    
  end
end    