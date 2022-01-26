# frozen_string_literal: true

require 'dgi/configuration'

module MebApi
  module DGI
    module Enrollment
      class Configuration < Common::Client::Configuration::REST
        def base_path
          Settings.dgi.vets.url.to_s
        end

        def connection
          @conn ||= Faraday.new(base_path, headers: base_request_headers, request: request_options) do |faraday|
            faraday.use Faraday::Response::RaiseError

            faraday.request :multipart
            faraday.response :betamocks if mock_enabled?
            faraday.adapter Faraday.default_adapter
          end
        end

        def service_name
          'DGI/Enrollment'
        end

        def mock_enabled?
          Settings.dgi.vets.mock || false
        end
      end
    end
  end
end
