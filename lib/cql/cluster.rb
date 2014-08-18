# encoding: utf-8

module Cql
  class Cluster
    extend Forwardable

    # @!method each_host
    #   Yield or enumerate each member of this cluster
    #   @overload each_host
    #     @yieldparam host [Cql::Host] current host
    #     @return [Array<Cql::Host>] a list of hosts
    #   @overload each_host
    #     @return [Enumerator<Cql::Host>] an enumerator
    # @!parse alias :hosts :each_host
    #
    # @!method host(address)
    #   Find a host by its address
    #   @param address [IPAddr, String] ip address
    #   @return [Cql::Host, nil] host or nil
    #
    # @!method has_host?(address)
    #   Determine if a host by a given address exists
    #   @param address [IPAddr, String] ip address
    #   @return [Boolean] true or false
    def_delegators :@registry, :hosts, :each_host, :host, :has_host?

    # @private
    def initialize(logger, io_reactor, control_connection, cluster_registry, execution_options, connection_options, load_balancing_policy, reconnection_policy, retry_policy, connector)
      @logger                = logger
      @io_reactor            = io_reactor
      @control_connection    = control_connection
      @registry              = cluster_registry
      @execution_options     = execution_options
      @connection_options    = connection_options
      @load_balancing_policy = load_balancing_policy
      @reconnection_policy   = reconnection_policy
      @retry_policy          = retry_policy
      @connector             = connector
    end

    def register(listener)
      @registry.add_listener(listener)
      self
    end

    def connect_async(keyspace = nil)
      client  = Client.new(@logger, @registry, @io_reactor, @connector, @load_balancing_policy, @reconnection_policy, @retry_policy, @connection_options)
      session = Session.new(client, @execution_options)
      promise = Promise.new

      client.connect.on_complete do |f|
        if f.resolved?
          if keyspace
            f = session.execute_async("USE #{keyspace}")

            f.on_success {promise.fulfill(session)}
            f.on_failure {|e| promise.break(e)}
          else
            promise.fulfill(session)
          end
        else
          f.on_failure {|e| promise.break(e)}
        end
      end

      promise.future
    end

    def connect(keyspace = nil)
      connect_async(keyspace).get
    end

    def close_async
      promise = Promise.new

      @control_connection.close_async.on_complete do |f|
        if f.resolved?
          promise.fulfill(self)
        else
          f.on_failure {|e| promise.break(e)}
        end
      end

      promise.future
    end

    def close
      close_async.get
    end

    def inspect
      "#<#{self.class.name}:0x#{self.object_id.to_s(16)}>"
    end
  end
end

require 'cql/cluster/client'
require 'cql/cluster/connector'
require 'cql/cluster/control_connection'
require 'cql/cluster/options'
require 'cql/cluster/registry'
