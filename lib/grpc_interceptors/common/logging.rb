# frozen_string_literal: true

require 'grpc'
require 'logger'

module GrpcInterceptors
  module Common
    module Logging
      SYMBOL_TO_SEVERITY = {
        trace: ::Logger::Severity::DEBUG,
        debug: ::Logger::Severity::DEBUG,
        info: ::Logger::Severity::INFO,
        warn: ::Logger::Severity::WARN,
        error: ::Logger::Severity::ERROR,
        fatal: ::Logger::Severity::FATAL
      }.freeze

      # Codes a caller causes. A server call that fails with one is logged at
      # warn; a server call that fails with any other code is ours and logged at error.
      CALLER_CODES = [
        ::GRPC::Core::StatusCodes::CANCELLED,
        ::GRPC::Core::StatusCodes::INVALID_ARGUMENT,
        ::GRPC::Core::StatusCodes::NOT_FOUND,
        ::GRPC::Core::StatusCodes::ALREADY_EXISTS,
        ::GRPC::Core::StatusCodes::PERMISSION_DENIED,
        ::GRPC::Core::StatusCodes::FAILED_PRECONDITION,
        ::GRPC::Core::StatusCodes::ABORTED,
        ::GRPC::Core::StatusCodes::OUT_OF_RANGE,
        ::GRPC::Core::StatusCodes::UNAUTHENTICATED
      ].freeze

      CODE_NAMES = ::GRPC::Core::StatusCodes.constants.to_h do |name|
        [::GRPC::Core::StatusCodes.const_get(name), name.to_s]
      end.freeze

      def self.caller_caused?(code) = CALLER_CODES.include?(code)

      # Whether the caller caused error: a gRPC status with a caller code, or an
      # error that says so itself (caller_caused? returns true). The second is for
      # a failure a service must answer with another code, such as an operator's
      # failure answered INTERNAL because the caller reads it as an unknown outcome.
      def self.caller_caused_error?(error)
        return true if error.respond_to?(:caller_caused?) && error.caller_caused?

        error.is_a?(::GRPC::BadStatus) && caller_caused?(error.code)
      end

      # The event of a failed call: its method and code, e.g.
      # SIGN_OFF_ROUND_FAILED_PRECONDITION.
      def self.event(method, code)
        "#{GrpcHelper.method_name(method).upcase}_#{CODE_NAMES.fetch(code, 'UNKNOWN')}"
      end

      # Some logger implementations (e.g. SemanticLogger-backed CasinoLogger)
      # expose #level as a Symbol rather than the ::Logger::Severity Integer
      # constants this module compares against. Normalize here so any logger
      # duck-typed with #level/#info/#debug works without a per-service wrapper.
      def self.normalized_level(logger)
        raw = logger.respond_to?(:level) ? logger.level : ::Logger::Severity::INFO

        case raw
        when Integer then raw
        when Symbol then SYMBOL_TO_SEVERITY.fetch(raw, ::Logger::Severity::INFO)
        else ::Logger::Severity::INFO
        end
      end

      def self.yield_and_log(
        logger: nil, request: nil, method: nil, method_type: nil, kind: nil
      )
        grpc_code = ::GRPC::Core::StatusCodes::OK
        response = yield
      rescue StandardError => e
        grpc_code = e.is_a?(::GRPC::BadStatus) ? e.code : ::GRPC::Core::StatusCodes::UNKNOWN
        caller_caused = caller_caused_error?(e)
        extra_fields = {
          'error' => e.class.to_s,
          'error_message' => e.message,
          'backtrace' => e.backtrace
        }

        raise
      ensure
        extra_fields ||= {}
        extra_fields['grpc.code'] = grpc_code

        if normalized_level(logger) == ::Logger::Severity::DEBUG && !response.nil? && !response.is_a?(Enumerator)
          extra_fields['response'] = Common::GrpcHelper.proto_to_h(response)
        end

        log(
          logger: logger, request: request, method: method,
          method_type: method_type, kind: kind, extra_fields: extra_fields,
          caller_caused: caller_caused
        )
      end

      ##
      # Log a gRPC interaction.
      #
      # If the current log level is INFO, then it logs out basic facts.
      # If the current log level is DEBUG, then it additionally adds to the log request and response.
      # If the server responds with error, then the error is added to the log.
      # A failed server call is logged whatever the level, with its event: at warn
      # when the caller caused it, at error otherwise.
      #
      # @param [Object] request The request object
      # @param [String] method The method passed to the intercepting function
      # @param [String] method_type The used method_type, unary or one of the streams
      #
      def self.log(
        logger: nil, request: nil, method: nil, method_type: nil, kind: nil,
        extra_fields: {}, caller_caused: nil
      )
        payload = build_payload(method, method_type, kind)
        payload.merge!(extra_fields)

        level = normalized_level(logger)
        code = payload['grpc.code']
        if kind == GrpcInterceptors::Kind::SERVER && code && code != ::GRPC::Core::StatusCodes::OK
          payload['event'] = event(method, code)
          payload['request'] = Common::GrpcHelper.proto_to_h(request) if level == ::Logger::Severity::DEBUG && request
          caller_caused = caller_caused?(code) if caller_caused.nil?
          logger.public_send(caller_caused ? :warn : :error, payload)
        elsif level == ::Logger::Severity::INFO
          logger.info(payload)
        elsif level == ::Logger::Severity::DEBUG
          payload['request'] = Common::GrpcHelper.proto_to_h(request) unless request.nil?
          logger.debug(payload)
        end
      end

      def self.build_payload(method, method_type, kind)
        service = GrpcHelper.service_name(method)
        method = GrpcHelper.method_name(method)

        payload = {
          'pid' => Process.pid,
          'grpc.component' => kind, # the caller, server or client
          'grpc.service' => service,
          'grpc.method' => method,
          'grpc.method_type' => method_type
        }

        if defined?(OpenTelemetry) && OpenTelemetry::Trace.current_span.recording?
          tracing_context = OpenTelemetry::Trace.current_span.context
          payload['span_id'] = tracing_context.hex_span_id
          payload['trace_id'] = tracing_context.hex_trace_id
        end

        payload
      end
    end
  end
end
