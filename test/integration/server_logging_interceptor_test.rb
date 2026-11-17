# frozen_string_literal: true

require 'test_helper'
require_relative '../support/ping_server_impl'
require_relative '../support/grpc_server_runner'

describe GrpcInterceptors::Server::LoggingInterceptor do
  let(:log) { StringIO.new }
  let(:logger) do
    Logger.new(log, level: Logger::INFO, formatter: method(:formatter_helper))
  end
  let(:received_log) { JSON(log.string) }

  let(:server_runner) do
    Support::GrpcServerRunner.new(
      server_opts: {
        interceptors: [
          GrpcInterceptors::Server::LoggingInterceptor.new(logger)
        ]
      }
    )
  end

  before do
    server_port = server_runner.start
    @stub = Support::PingServer::Stub.new(
      "localhost:#{server_port}", :this_channel_is_insecure
    )
  end
  after do
    server_runner.stop
  end

  describe 'when logger level is INFO' do
    let(:ping_request) { Support::PingRequest.new(value: 'Ping') }

    it 'produces log with basic facts' do
      response = @stub.request_response_ping(ping_request)

      assert_instance_of Support::PingResponse, response
      assert_instance_of Integer, received_log['pid']
      assert_equal 'server', received_log['grpc.component']
      assert_equal 'support.PingServer', received_log['grpc.service']
      assert_equal 'request_response_ping', received_log['grpc.method']
      assert_equal 'unary', received_log['grpc.method_type']
      assert_equal 0, received_log['grpc.code']
      refute received_log.key?('backtrace')
      refute received_log.key?('error')
    end

    describe 'when tracing is enabled' do
      let(:otel_exporter) { OTEL_EXPORTER }
      let(:server_runner) do
        Support::GrpcServerRunner.new(
          server_opts: {
            interceptors: [
              GrpcInterceptors::Server::LoggingInterceptor.new(logger),
              GrpcInterceptors::Server::OpenTelemetryTracingInterceptor.new
            ]
          }
        )
      end
      after { otel_exporter.reset }

      it 'produces log with trace_id and span_id' do
        @stub.request_response_ping(ping_request)

        refute_nil received_log['span_id']
        refute_nil received_log['trace_id']
        refute_equal '0' * 16, received_log['span_id']
        refute_equal '0' * 32, received_log['trace_id']
      end
    end
  end

  describe 'when logger level is DEBUG' do
    let(:ping_request) { Support::PingRequest.new(value: 'Ping') }

    it 'produces log as on the INFO level plus request' do
      logger.level = Logger::DEBUG
      response = @stub.request_response_ping(ping_request)

      assert_instance_of Support::PingResponse, response
      assert_instance_of Integer, received_log['pid']
      assert_equal 'server', received_log['grpc.component']
      assert_equal 'support.PingServer', received_log['grpc.service']
      assert_equal 'request_response_ping', received_log['grpc.method']
      assert_equal 'unary', received_log['grpc.method_type']
      assert_equal 0, received_log['grpc.code']
      refute received_log.key?('backtrace')
      refute received_log.key?('error')

      logged_request = received_log['request']

      assert_equal 'Ping', logged_request['value']
    end
  end

  describe 'when an exception is raised' do
    let(:ping_request) do
      Support::PingRequest.new(error_code: GRPC::Core::StatusCodes::INVALID_ARGUMENT)
    end

    [Logger::DEBUG, Logger::INFO].each do |severity|
      it "produces error log when log level is #{severity}" do
        logger.level = severity

        assert_raises GRPC::InvalidArgument do
          @stub.request_response_ping(ping_request)
        end

        assert_instance_of Integer, received_log['pid']
        assert_equal 'server', received_log['grpc.component']
        assert_equal 'support.PingServer', received_log['grpc.service']
        assert_equal 'request_response_ping', received_log['grpc.method']
        assert_equal 'unary', received_log['grpc.method_type']
        assert_instance_of Integer, received_log['pid']
        assert_equal GRPC::Core::StatusCodes::INVALID_ARGUMENT, received_log['grpc.code']
        assert_instance_of Array, received_log['backtrace']
        assert_equal 'GRPC::InvalidArgument', received_log['error']
      end
    end

    it 'logs a caller error at warn with its event, even above info' do
      logger.level = Logger::WARN

      assert_raises(GRPC::InvalidArgument) { @stub.request_response_ping(ping_request) }

      assert_equal 'WARN', received_log['severity']
      assert_equal 'REQUEST_RESPONSE_PING_INVALID_ARGUMENT', received_log['event']
    end

    describe 'when the failure is ours' do
      let(:ping_request) do
        Support::PingRequest.new(error_code: GRPC::Core::StatusCodes::INTERNAL)
      end

      it 'logs it at error with its event, even when only errors are logged' do
        logger.level = Logger::ERROR

        assert_raises(GRPC::Internal) { @stub.request_response_ping(ping_request) }

        assert_equal 'ERROR', received_log['severity']
        assert_equal 'REQUEST_RESPONSE_PING_INTERNAL', received_log['event']
      end
    end
  end

  describe '.caller_caused_error?' do
    # An operator's failure a service must answer INTERNAL with.
    operator_failure = Class.new(GRPC::Internal) do
      def caller_caused? = true
    end

    it 'tells the caller\'s failures from ours' do
      assert GrpcInterceptors::Common::Logging.caller_caused_error?(GRPC::NotFound.new)
      assert GrpcInterceptors::Common::Logging.caller_caused_error?(operator_failure.new)
      refute GrpcInterceptors::Common::Logging.caller_caused_error?(GRPC::Internal.new)
      refute GrpcInterceptors::Common::Logging.caller_caused_error?(StandardError.new)
    end
  end

  private

  def formatter_helper(severity, _datetime, _progname, msg)
    JSON.dump(msg.merge('severity' => severity))
  end
end
