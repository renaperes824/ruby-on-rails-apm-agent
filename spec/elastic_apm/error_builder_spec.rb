# frozen_string_literal: true

require 'spec_helper'

module ElasticAPM
  RSpec.describe ErrorBuilder do
    subject { ErrorBuilder.new Config.new }

    context 'with an exception' do
      it 'builds an error from an exception', :mock_time do
        error = subject.build_exception(actual_exception)

        expect(error.culprit).to eq '/'
        expect(error.timestamp).to eq 694_224_000_000_000
        expect(error.exception.message).to eq 'ZeroDivisionError: divided by 0'
        expect(error.exception.type).to eq 'ZeroDivisionError'
        expect(error.exception.handled).to be true
      end

      it 'attaches a context from Rack' do
        env = Rack::MockRequest.env_for(
          '/somewhere/in/there?q=yes',
          method: 'POST'
        )
        env['HTTP_CONTENT_TYPE'] = 'application/json'
        error = subject.build_exception actual_exception, rack_env: env

        request = error.context.request
        expect(request).to be_a(Error::Context::Request)
        expect(request.method).to eq 'POST'
        expect(request.url).to eq(
          protocol: 'http',
          hostname: 'example.org',
          port: 80,
          pathname: '/somewhere/in/there',
          search: 'q=yes',
          hash: nil,
          full: 'http://example.org/somewhere/in/there?q=yes'
        )
        expect(request.headers).to eq(
          'Content-Type' => 'application/json'
        )
      end
    end

    context 'with a log' do
      it 'builds an error from a message', :mock_time do
        error = subject.build_log 'Things went BOOM', backtrace: caller

        expect(error.culprit).to eq 'instance_exec'
        expect(error.log.message).to eq 'Things went BOOM'
        expect(error.timestamp).to eq 694_224_000_000_000
        expect(error.log.stacktrace).to be_a Stacktrace
        expect(error.log.stacktrace.length).to be > 0
      end
    end
  end
end
