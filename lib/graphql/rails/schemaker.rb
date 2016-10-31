require "graphql/rails/schemaker/version"
require 'graphql/rails/schemaker/railtie' if defined?(Rails)

module Graphql
  module Rails
    module Schemaker
      def self.root
        File.dirname __dir__
      end
    end
  end
end
