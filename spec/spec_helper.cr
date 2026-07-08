require "spec"
require "../src/term-vt"

{% if flag?(:unix) %}
  module Term::VT::Spec
    def self.with_pty(&)
      yield
    rescue ex : Term::VT::PTYUnavailable
      pending!("PTY unavailable: #{ex.message}")
    end
  end
{% end %}
