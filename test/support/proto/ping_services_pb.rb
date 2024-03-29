# Generated by the protocol buffer compiler.  DO NOT EDIT!
# Source: test/support/proto/ping.proto for package 'support'

require 'grpc'
require_relative 'ping_pb'

module Support
  module PingServer
    class Service

      include ::GRPC::GenericService

      self.marshal_class_method = :encode
      self.unmarshal_class_method = :decode
      self.service_name = 'support.PingServer'

      rpc :RequestResponsePing, ::Support::PingRequest, ::Support::PingResponse
      rpc :ClientStreamerPing, stream(::Support::PingRequest), ::Support::PingResponse
      rpc :ServerStreamerPing, ::Support::PingRequest, stream(::Support::PingResponse)
      rpc :BidiStreamerPing, stream(::Support::PingRequest), stream(::Support::PingResponse)
    end

    Stub = Service.rpc_stub_class
  end
end
