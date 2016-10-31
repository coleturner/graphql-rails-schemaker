require 'fileutils'
require 'set'
require 'graphql/rails/schemaker/template_renderer'

namespace :schemaker do
  desc "Tasks for operating a GraphQL Schema Server"

  task introspect: :environment do
    viewer = SystemViewer.new

    query_string = GraphQL::Introspection::INTROSPECTION_QUERY
    result_hash = Schema.execute(query_string, context: {viewer: viewer})

    File.open("./build/schema.json","w+") do |f|
      f.write(result_hash.to_json)
    end
  end

  task generate: :environment do
    if File.exist? "./app/graph/schema.rb"
      abort "\e[1mAnother schema already exists @ ./app/graph/schema.rb\e[0m"
    end

    # Ensure directories are available
    #FileUtils::mkdir_p Rails.root.join("app", "graph", "mutations")
    #FileUtils::mkdir_p Rails.root.join("app", "graph", "resolvers")
    FileUtils::mkdir_p Rails.root.join("app", "graph", "types")

    # Load our application
    Rails.application.eager_load!
    models = ApplicationRecord.descendants.collect { |type| type }
    scalar_types = [:string, :integer, :float, :id, :boolean]

    # Determine whether to do snake case or camel case
    STDOUT.puts "\e[1mUse camelCase or snake_case? Enter (c/S).\e[0m"
    name_format =
      if STDIN.gets.chomp.downcase == 'c'
        :camel
      else
        :snake
      end

    # Function to convert object types to string
    object_type_to_string = lambda { |model, attributes|
      TemplateRenderer.render("rails/schemaker/object_type.erb", { model: model, attributes: attributes, all_models: models })
    }

    # Function to convert enum types to string
    enum_type_to_string = lambda { |name, values|
      TemplateRenderer.render("rails/schemaker/enum_type.erb", { name: name, values: values })
    }

    # Function to write object types
    put_object_type = lambda { |file, model, attributes|
      File.open(file, 'w+') { |file| file.write(object_type_to_string.call(model, attributes)) }
    }

    # Function to write enum types
    put_enum_type = lambda { |file, name, value|
      File.open(file, 'w+') { |file| file.write(enum_type_to_string.call(name, value)) }
    }

    STDOUT.puts "Using #{name_format == :camel ? 'camel case' : 'snake case'}"

    # Schema vars
    query_type_name = "QueryType"
    while ApplicationRecord.descendants.map(&:name).include? query_type_name
      if query_type_name == "QueryType"
        query_type_name = "QueryRootType"
      elsif query_type_name == "QueryRootType"
        query_type_name = "QueryRootObjectType"
      elsif query_type_name == "QueryRootObjectType"
        STDOUT.puts "Unable to formulate a query root type name - taken: QueryType, QueryRootType, QueryRootObjectType"
        abort "Exiting..."
      end
    end

    mutation_type_name = "MutationType"
    while ApplicationRecord.descendants.map(&:name).include? mutation_type_name
      if query_type_name == "MutationType"
        query_type_name = "MutationRootType"
      elsif query_type_name == "MutationRootType"
        query_type_name = "MutationRootObjectType"
      elsif query_type_name == "MutationRootObjectType"
        STDOUT.puts "Unable to formulate a mutation root type name - taken: MutationType, MutationRootType, MutationRootObjectType"
        abort "Exiting..."
      end
    end

    # The Main Schema entry point
    schema_rb_file = "./app/graph/schema.rb"
    unless File.exist? schema_rb_file
      STDOUT.puts "\e[1m\e[32mGenerating Schema Root...\e[0m"

      middleware = name_format == :camel ? "middleware AuthorizationMiddleware.new" : ""

      src = TemplateRenderer.render("rails/schemaker/schema.erb", { middleware: middleware, query_type_name: query_type_name, mutation_type_name: mutation_type_name })

      File.open(schema_rb_file, 'w+') { |file| file.write(src) }
    end

    # Camel Case Middleware
    if name_format == :camel
      FileUtils::mkdir_p Rails.root.join("app", "graph", "middleware")

      middleware_rb_file = "./app/graph/middleware/camel_case_middleware.rb"
      unless File.exist? middleware_rb_file
        src = TemplateRenderer.render("rails/schemaker/camel_case_middleware.erb")

        File.open(middleware_rb_file, 'w+') { |file| file.write(src) }
      end
    end

    fake_association = Class.new(Object) {
      def initialize(model, plural_name:, macro: :has_many, polymorphic: false)
          @model = model
          @plural_name = plural_name || model.name.pluralize
          @macro = macro
          @polymorphic = polymorphic
      end

      def klass() @model end
      def macro() @macro end
      def plural_name() @plural_name end
      def polymorphic?() @polymorphic end
      def collection?() [:has_many, :has_and_belongs_to_many].include?(@macro) end
    }

    scalar_types = { :id => "types.ID", :boolean => "types.Boolean", :integer => "types.Int", :float => "types.Float", :decimal => "types.Float", :string => "types.String"}

    guess_type = lambda { |model, name|
      return :enum if model.defined_enums.key?(name)
      matches = model.columns.select { |c| c.name == name }

      return matches.first.type if matches.present?

      :string
    }

    graphl_field_type = Proc.new { |type, name|
      graphql_type = nil
      graphql_type = scalar_types[type.to_sym] if scalar_types.key? type.to_sym

      if type == :enum
        graphql_type = "#{name.to_s.camelize}Enum"
      end

      graphql_type = scalar_types[:string] if type.nil?

      graphql_type
    }

    STDOUT.puts ""
    STDOUT.puts "\e[1m\e[32mGenerating Object Types...\e[0m"

    active_models = []
    active_enum = {}
    active_models_attributes = {}
    models.each do |model|
      model.connection
      skipped = false
      STDOUT.puts
      STDOUT.puts "----------------------------------"
      STDOUT.puts "\e[1mGenerating type for model: \e[32m#{model}\e[0m"
      attributes = Set.new
      attribute_types = {}
      attribute_graphql_types = {}
      attribute_properties = {}
      attribute_associations = {}

      # Track all the columns
      model.columns.each do |column|
        name = column.name

        type_sym =
          if model.defined_enums.key? name
            :enum
          else
            column.type
          end

        graphql_type = graphl_field_type.call(type_sym, name)

        new_name = name_format == :camel ? name.camelize(:lower).to_sym : name.underscore.to_sym
        attributes.add(new_name)
        attribute_types[new_name] = type_sym
        attribute_graphql_types[new_name] = graphql_type
        attribute_properties[new_name] = name
      end

      # Track all associations
      model.reflect_on_all_associations.each do |association|
        name = association.collection? ? association.plural_name.to_s : association.name.to_s
        type = :object

        new_name = name_format == :camel ? name.camelize(:lower).to_sym : name.underscore.to_sym
        attributes.add(new_name)
        attribute_types[new_name] = type
        attribute_graphql_types[new_name] = graphl_field_type.call(type, name)
        attribute_properties[new_name] = name
        attribute_associations[new_name] = association
      end

      # Process commands for each model
      last_input = $_
      is_repeating = false
      while last_input != "g"
        unless is_repeating
          STDOUT.puts
          STDOUT.puts "Using attributes: #{attributes.to_a.join(", ")}"
          STDOUT.puts "To continue, enter one of the following commands: (\e[34mg = generate \e[39m| \e[31mr = remove attribute \e[39m| \e[32ma = add attribute \e[39m| \e[93ms = skip model\e[39m)"
          command = STDIN.gets.chomp.downcase
        end

        is_repeating = false

        case command
        when "s"
          skipped = true
          break
        when "a"
          STDOUT.puts
          STDOUT.puts "Enter attribute name and type in following format: \e[32m#{name_format == :snake ? "property_name" : "columName"}\e[39m:(\e[96m#{scalar_types.join("\e[39m|\e[96m")}\e[39m)"
          raw_attr = STDIN.gets.chomp.downcase
          new_attr = raw_attr

          if name_format == :camel
            new_attr = raw_attr.camelize(:lower)
          else
            new_attr = raw_attr.underscore
          end

          unless new_attr === raw_attr
            STDOUT.puts "Converting to #{name_format == :camel ? 'camelCase' : 'snake_case'} - \"#{new_attr}\""
          end

          unless new_attr.present?
            is_repeating = false
            next
          end

          unless new_attr.include? ":"
            last_input = "a"
            is_repeating = true
            next
          end

          name, type = new_attr.split(":")
          property = name
          tries = 0;

          if attributes.include? name.to_sym
            STDOUT.puts "Attribute #{name} already exists. Retrying..."
            is_repeating = false
            next
          end

          until model.column_names.include? property or model.respond_to? property.to_sym
            if tries >= 3
              STDOUT.puts "Tried three times. Retrying..."
              break
            end

            STDOUT.puts "#{model} does not possess property \"#{property}\", what should \"#{name}\" respond with?"
            input = STDIN.gets.chomp
            property = input if input.present?

            tries += 1
          end

          if property.nil?
            is_repeating = true
            next
          end

          unless name == property
            attribute_properties[name] = property
          end

          attributes.add(name.to_sym)
          attribute_types[name.to_sym] = type
          attribute_graphql_types[name.to_sym] = graphl_field_type.call(type, name.to_sym)

        when "r"
          STDOUT.puts "Enter the name of the attribute to remove:"
          raw_attr = STDIN.gets.chomp.downcase

          if raw_attr.include? ":"
            raw_attr = raw_attr.split(":").first
          end

          remove_attr = raw_attr

          if name_format == :camel
            remove_attr = raw_attr.camelize(:lower)
          else
            remove_attr = raw_attr.underscore
          end

          unless remove_attr === raw_attr
            STDOUT.puts "Converting to #{name_format == :camel ? 'camelCase' : 'snake_case'} - \"#{remove_attr}\""
          end

          unless attributes.include? remove_attr.to_sym
            STDOUT.puts "Attribute \"#{remove_attr}\" does not exist."
            is_repeating = true
            next
          end

          STDOUT.puts "Removing attribute \"#{remove_attr}\"."
          attributes.delete(remove_attr.to_sym)
          attribute_types.delete remove_attr.to_sym
          attribute_graphql_types.delete remove_attr.to_sym
          attribute_properties.delete remove_attr.to_sym

          is_repeating = false
        when "g"
          break
        else
          STDOUT.puts "Unrecognized command #{command}"
        end

      end

      if skipped
        STDOUT.puts "\e[93mSkipping #{model.name}...\e[39m"
        next
      end

      object_type_file = "./app/graph/types/#{model.name.underscore}_type.rb"
      attr_composed = {}

      attributes.each do |attribute|
        hash = { :type => attribute_types[attribute], :graphql_type => attribute_graphql_types[attribute], :property => attribute_properties[attribute] }

        if attribute_associations.key? attribute
          hash[:association] = attribute_associations[attribute]
        end

        if model.defined_enums.key? hash[:property]
          active_enum[attribute.to_s.camelize] = model.defined_enums[hash[:property]]
        end

        attr_composed[attribute] = hash
      end

      put_object_type.call(object_type_file, model, attr_composed.sort_by { |k,v| [k == :id ? 0 : 1, k] })

      # Save this config for later
      active_models.push(model)
      active_models_attributes[model] = attr_composed

      # Todo
      # 2. Generate input types
      # 4. Generate generic resolvers (if using graphql-rails-resolver)

    end

    puts "active_enum = #{active_enum}"
    if active_enum.present?
      STDOUT.puts ""
      STDOUT.puts "----------------------------------"
      STDOUT.puts ""
      STDOUT.puts "\e[1m\e[32mGenerating Enum Types...\e[0m"

      active_enum.each do |name, values|
      enum_type_file = "./app/graph/types/#{name.underscore}_enum.rb"

        STDOUT.puts "\e[34m#{name}Enum\e[0m"
        put_enum_type.call(enum_type_file, name, values)
      end
  end

    STDOUT.puts ""
    STDOUT.puts "----------------------------------"
    STDOUT.puts ""

    # Generate union types from generated models
    polymorphics = active_models.map { |m| m.reflect_on_all_associations.select(&:polymorphic?) }.flatten
    if polymorphics.present?
      STDOUT.puts "\e[1m\e[32mGenerating Union Types...\e[0m"
      polymorphics.each do |polymorphic|

        STDOUT.puts "\e[34m#{polymorphic.name.to_s.camelize}Type\e[0m"

        polymorphic_rb_file = "./app/graph/types/#{polymorphic.name}_union.rb"
        associations = active_models.select { |m| m.reflect_on_all_associations.select{ |j| j.options[:as] == polymorphic.name }.present? }

          src = TemplateRenderer.render("rails/schemaker/union_type.erb", { polymorphic: polymorphic, associations: associations })

          File.open(polymorphic_rb_file, 'w+') { |file| file.write(src) }
      end
    end

    STDOUT.puts ""
    STDOUT.puts "----------------------------------"
    STDOUT.puts ""

    STDOUT.puts "\e[1m\e[32mGenerating Query Root...\e[0m"
    STDOUT.puts "A query root is the entry point to your Schema."
    STDOUT.puts ""
    STDOUT.puts "If you plan to use Relay v1, your Schema needs a global node to work properly."
    STDOUT.puts "See https://github.com/facebook/relay/issues/112 for more info."

    STDOUT.puts ""
    STDOUT.puts "----------------------------------"
    STDOUT.puts ""

    STDOUT.puts "How would you like to generate your query root?"
    STDOUT.puts "1 - Use Global Node (default)"
    STDOUT.puts "2 - Expose all fields on query root"
    STDOUT.puts ""

    command = STDIN.gets.chomp.downcase
    until ["1", "2", "", "g"].include? command
      STDOUT.puts "\"#{command}\" not recognized."
      command = STDIN.gets.chomp.downcase
    end

    if ["", "g"].include? command
      command = "1"
    end

    # Generate global node for query root
    if command == "1"
      root_type_name = nil

      # Check if developers already made a global node model
      if active_models.map(&:name).include? "Viewer"
        STDOUT.puts "A model by the name 'Viewer' already exists. Should this model be the global node? (Y/n)"

        command = STDIN.gets.chomp.downcase
        until ["y", "n", "", "g"].include?(command)
          STDOUT.puts "\"#{command}\" not recognized."
          command = STDIN.gets.chomp.downcase
        end

        if ["", "g"].include? command
          command = "y"
        end

        root_type_name = "Viewer"

        # Reconfigure the file
        model = active_models.select { |m| m.name == "Viewer" }.first
        attributes = active_models_attributes[model]

        root_type_attr = {}

        active_models.map do |model|
          key = model.name.pluralize

          if name_format == :camel
            key = key.camelize(:lower)
          else
            key = key.underscore
          end

          while key.nil? or attributes.key? key or attributes.key? key.to_sym
            STDOUT.puts "Field `\e[31m#{key}\e[0m` already exists on `\e[32m#{root_type_name}\e[0m`. Enter a new name for the field:"
            command = STDIN.gets.chomp
            unless command.present? and command[/[a-zA-Z]+/] == command
              command = nil
              next
            end

            key = command
          end

          if name_format == :camel
            key = key.camelize(:lower)
          else
            key = key.underscore
          end

          association = fake_association.new(model, plural_name: key)
          association.polymorphic?

          root_type_attr[key] = { :type => :id, :association => association}
        end

        object_type_file = "./app/graph/types/#{model.name.underscore}_type.rb"
        sorted_fields = Hash[root_type_attr.sort_by{ |k,v| k }]
        put_object_type.call(object_type_file, model, attributes.merge(sorted_fields))
      else
        STDOUT.puts "Define the root type to expose your object types: (letters only) (default = \e[32mViewer\e[0m)"
        name_command = STDIN.gets.chomp.downcase
        while root_type_name.nil?
          if name_command.empty?
            root_type_name = "Viewer"
          else
            unless name_command[/[a-zA-Z]+/] == name_command
              STDOUT.puts "Root type name must contain only letters. No numbers or special characters."
              next
            end

            if models.map(&:name).include?(name_command)
              STDOUT.puts "A model already exists by that name. Are you sure? (y/N)"
              command = STDIN.gets.chomp.downcase
              until ["y", "n", ""].include?(command)
                STDOUT.puts "\"#{command}\" not recognized."
                command = STDIN.gets.chomp.downcase
              end

              if command == ""
                command = "n"
              end

              if command == "n"
                next
              end
            end

            root_type_name = name_command.classify
          end
        end

        # Generate global node type with generated models
        Object.const_set(root_type_name, Class.new { def name() root_type_name end  })

        root_type_attr = {}
        active_models.each do |model|
          key = model.name.pluralize

          if name_format == :camel
            key = key.camelize(:lower)
          else
            key = key.underscore
          end

          association = fake_association.new(model, plural_name: key)
          root_type_attr[key] = { :type => :id, :association => association}
        end

        root_object_type_file = "./app/graph/types/#{root_type_name.underscore}_type.rb"
        put_object_type.call(root_object_type_file, root_type_name.constantize, root_type_attr)

      end
    end

    # Generate the Query root type (include)
    query_type_rb_file = "./app/graph/types/#{query_type_name.underscore}.rb"
    unless File.exist? query_type_rb_file
      STDOUT.puts "Generating Query Root Type..."

      src = TemplateRenderer.render("rails/schemaker/query_type.erb", { query_type_name: query_type_name, root_type_name: root_type_name })

      File.open(query_type_rb_file, 'w+') { |file| file.write(src) }
    end


    # Generate the Mutation root type (include)
    # TODO - Add Mutations
    mutation_type_rb_file = "./app/graph/types/#{mutation_type_name.underscore}.rb"
    unless File.exist? mutation_type_rb_file
      STDOUT.puts "Generating Mutation Root Type..."

      src = TemplateRenderer.render("rails/schemaker/mutation_type.erb", { mutation_type_name: mutation_type_name })

      File.open(mutation_type_rb_file, 'w+') { |file| file.write(src) }
    end


    STDOUT.puts "\e[32mDone...\e[0m"


  end

end
