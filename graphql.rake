require 'fileutils'
require 'set'

namespace :graphql do
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

    # Function to convert types to string
    schema_to_string = lambda { |model, attributes|
      ApplicationController.render(
        file: "./lib/graphql-schemaker/object_type.erb",
        locals: { model: model, attributes: attributes, all_models: models },
        layout: nil
      )
    }

    # Function to write schema
    put_object_type = lambda { |file, model, attributes|
      File.open(file, 'w+') { |file| file.write(schema_to_string.call(model, attributes)) }
    }

    STDOUT.puts "Using #{name_format == :camel ? 'camel case' : 'snake case'}"

    # Schema vars
    query_type_name = "QueryType"
    while ApplicationRecord.descendants.map(&:name).include? query_type_name
      if query_type_name == "QueryType"
        query_type_name = "QueryRootType"
      elsif query_type_name == "QueryRootType"
        query_type_name = "QueryRootObjectType"
      elsif query_type_name == "QueryRooQueryRootObjectTypetType"
        STDOUT.puts "Unable to formulate a query root type name - taken: QueryType, QueryRootType, QueryRootObjectType"
        abort "Exiting..."
      end
    end

    # The Main Schema entry point
    schema_rb_file = "./app/graph/schema.rb"
    unless File.exist? schema_rb_file
      STDOUT.puts "\e[1m\e[32mGenerating Schema Root...\e[0m"

      middleware = name_format == :camel ? "middleware AuthorizationMiddleware.new" : ""

      src = ApplicationController.render(
        file: "./lib/graphql-schemaker/schema.erb",
        locals: { middleware: middleware, query_type_name: query_type_name },
        layout: nil
      )

      File.open(schema_rb_file, 'w+') { |file| file.write(src) }
    end

    # Camel Case Middleware
    if name_format == :camel
      FileUtils::mkdir_p Rails.root.join("app", "graph", "middleware")

      middleware_rb_file = "./app/graph/middleware/camel_case_middleware.rb"
      unless File.exist? middleware_rb_file
        src = ApplicationController.render(
          file: "./lib/graphql-schemaker/camel_case_middleware.erb",
          locals: { },
          layout: nil
        )

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

    STDOUT.puts ""
    STDOUT.puts "\e[1m\e[32mGenerating Object Types...\e[0m"

    active_models = []
    active_models_attributes = {}
    models.each do |model|
      model.connection
      skipped = false
      STDOUT.puts
      STDOUT.puts "----------------------------------"
      STDOUT.puts "\e[1mGenerating type for model: \e[32m#{model}\e[0m"
      attributes = Set.new
      attribute_types = {}
      attribute_properties = {}
      attribute_associations = {}

      # Track all the columns
      model.columns.each do |column|
        name = column.name
        type = column.type

        new_name = name_format == :camel ? name.camelize(:lower).to_sym : name.underscore.to_sym
        attributes.add(new_name)
        attribute_types[new_name] = type
        attribute_properties[new_name] = name
      end

      # Track all associations
      model.reflect_on_all_associations.each do |association|
        name = association.collection? ? association.plural_name.to_s : association.name.to_s
        type = :object

        new_name = name_format == :camel ? name.camelize(:lower).to_sym : name.underscore.to_sym
        attributes.add(new_name)
        attribute_types[new_name] = type
        attribute_properties[new_name] = name
        attribute_associations[new_name] = association
      end

      puts "attributes = #{attributes.to_a}"

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
        hash = { :type => attribute_types[attribute], :property => attribute_properties[attribute] }

        if attribute_associations.key? attribute
          hash[:association] = attribute_associations[attribute]
        end

        attr_composed[attribute] = hash
      end

      put_object_type.call(object_type_file, model, attr_composed.sort_by { |k,v| [k == :id ? 0 : 1, k] })

      # Save this config for later
      active_models.push(model)
      active_models_attributes[model] = attr_composed

      # Todo
      # 2. Generate input types
      # 3. Generate generic mutations
      # 4. Generate generic resolvers (if using graphql-rails-resolver)

    end

    STDOUT.puts ""
    STDOUT.puts "----------------------------------"
    STDOUT.puts ""

    # Generate enums from generated models
    polymorphics = active_models.map { |m| m.reflect_on_all_associations.select(&:polymorphic?) }.flatten
    if polymorphics.present?
      STDOUT.puts "\e[1m\e[32mGenerating Union Types...\e[0m"
      polymorphics.each do |polymorphic|

        STDOUT.puts "----------------------------------"
        STDOUT.puts "\e[1mGenerating type for union: \e[32m#{polymorphic.name.to_s.camelize}Type\e[0m"

        polymorphic_rb_file = "./app/graph/types/#{polymorphic.name}_union.rb"
        associations = active_models.select { |m| m.reflect_on_all_associations.select{ |j| j.options[:as] == polymorphic.name }.present? }

          src = ApplicationController.render(
            file: "./lib/graphql-schemaker/union_type.erb",
            locals: { polymorphic: polymorphic, associations: associations },
            layout: nil
          )

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
    until ["1", "2", ""].include?(command)
      STDOUT.puts "\"#{command}\" not recognized."
      command = STDIN.gets.chomp.downcase
    end

    if command == ""
      command = "1"
    end

    # Generate global node for query root
    if command == "1"
      root_type_name = nil

      # Check if developers already made a global node model
      if active_models.map(&:name).include? "Viewer"
        STDOUT.puts "A model by the name 'Viewer' already exists. Should this model be the global node? (Y/n)"

        command = STDIN.gets.chomp.downcase
        until ["y", "n", ""].include?(command)
          STDOUT.puts "\"#{command}\" not recognized."
          command = STDIN.gets.chomp.downcase
        end

        if command == ""
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
            command = STDIN.gets.chomp.downcase
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

      src = ApplicationController.render(
        file: "./lib/graphql-schemaker/query_type.erb",
        locals: { query_type_name: query_type_name, root_type_name: root_type_name },
        layout: nil
      )

      File.open(query_type_rb_file, 'w+') { |file| file.write(src) }
    end


    STDOUT.puts "\e[32mDone...\e[0m"


  end

end
