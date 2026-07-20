# frozen_string_literal: true

# Minimal stand-in for loggers (e.g. CasinoLogger/SemanticLogger) whose
# #level returns a Symbol instead of a ::Logger::Severity Integer.
class SymbolLevelLogger
  attr_accessor :level
  attr_reader :messages

  def initialize(level: :info)
    @level = level
    @messages = []
  end

  def info(msg) = @messages << [:info, msg]
  def debug(msg) = @messages << [:debug, msg]
end
