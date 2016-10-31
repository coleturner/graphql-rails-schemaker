module Graphql
  module Rails
    module Schemaker
      class Railtie < ::Rails::Railtie
        rake_tasks do
          load 'tasks/schemaker.rake'
        end
      end
    end
  end
end
