# frozen_string_literal: true

require 'test_helper'
require_relative '../support/ping_server_impl'
require_relative '../support/grpc_server_runner'
require_relative '../support/symbol_level_logger'

describe 'GrpcInterceptors::Server::LoggingInterceptor with a Symbol-level logger' do
  let(:logger) { SymbolLevelLogger.new(level: :info) }
  let(:server_runner) do
    Support::GrpcServerRunner.new(
      server_opts: {
        interceptors: [GrpcInterceptors::Server::LoggingInterceptor.new(logger)]
      }
    )
  end

  before do
    server_port = server_runner.start
    @stub = Support::PingServer::Stub.new("localhost:#{server_port}", :this_channel_is_insecure)
  end
  after { server_runner.stop }

  it 'still logs at INFO despite level being a Symbol' do
    @stub.request_response_ping(Support::PingRequest.new(value: 'Ping'))

    assert_equal 1, logger.messages.size
    severity, payload = logger.messages.first

    assert_equal :info, severity
    assert_equal 'support.PingServer', payload['grpc.service']
  end

  describe 'when level is :debug' do
    let(:logger) { SymbolLevelLogger.new(level: :debug) }

    it 'includes the request payload' do
      @stub.request_response_ping(Support::PingRequest.new(value: 'Ping'))

      severity, payload = logger.messages.first

      assert_equal :debug, severity
      assert_equal 'Ping', payload['request']['value']
    end
  end
end
