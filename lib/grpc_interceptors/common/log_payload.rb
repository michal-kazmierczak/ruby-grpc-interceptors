# frozen_string_literal: true

module GrpcInterceptors
  module Common
    module Logger
      ##
      # Log a gRPC interaction from the client side.
      #
      # If the current log level is INFO, then it logs out basic facts.
      # If the current log level is DEBUG, then it additionally adds to the log request and response.
      # If the server responds with error, then the error is added to the log.
      #
      # @param [Object] request The request object
      # @param [String] method The method passed to the intercepting function
      # @param [String] method_type The used method_type, unary or one of the streams
      #
      def self.log(
        logger: nil, request: nil, method: nil, method_type: nil, kind: nil
      )
        payload = build_payload(method, method_type, kind)

        if block_given?
          grpc_code = ::GRPC::Core::StatusCodes::OK
          begin
            response = yield
          rescue StandardError => e
            grpc_code = e.is_a?(::GRPC::BadStatus) ? e.code : ::GRPC::Core::StatusCodes::UNKNOWN

            payload['error'] = e.class.to_s
            payload['error_message'] = e.message
            payload['backtrace'] = e.backtrace

            raise
          end
        end
      ensure
        payload['grpc_code'] = grpc_code unless grpc_code.nil?

        if logger.level == Logger::Severity::INFO
          logger.info(payload)
        elsif logger.level == Logger::Severity::DEBUG
          payload['request'] = Common::GrpcHelper.proto_to_h(request) unless request.nil?
          payload['response'] = Common::GrpcHelper.proto_to_h(response) unless response.nil?
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
