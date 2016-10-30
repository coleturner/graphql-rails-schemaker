require 'fileutils'

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
      abort "Another schema already exists @ ./app/graph/schema.rb"
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
      STDOUT.puts "Generating Schema Object..."

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

    # Todo
    # => Generate Enum
    # => Generate Union Types
    # => => puts "inverse_of = #{all_models.select { |m| m.reflect_on_all_associations.select{|j| j.options[:as] == association.name}.present?} }"


    models.each do |model|
      model.connection
      skipped = false
      STDOUT.puts
      STDOUT.puts "----------------------------------"
      STDOUT.puts "\e[1mGenerating schema for model: \e[32m#{model}\e[0m"
      attributes = []
      attribute_types = {}
      attribute_properties = {}

      model.columns.each do |column|
        name = column.name
        type = column.type

        new_name = name_format == :camel ? name.camelize(:lower).to_sym : name.underscore.to_sym
        attributes.push(new_name)
        attribute_types[new_name] = type
        attribute_properties[new_name] = name
      end

      # Process commands for each model
      last_input = $_
      is_repeating = false
      while last_input != "g"
        unless is_repeating
          STDOUT.puts
          STDOUT.puts "Using attributes: #{attributes.join(", ")}"
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

          attributes.push(name.to_sym)

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
          attributes -= [remove_attr.to_sym]
          is_repeating = false
        when "g"
          break
        else
          STDOUT.puts "Unrecognized command #{command}"
        end

      end

      if skipped
        next
      end

      STDOUT.puts "Generating schema for #{model.name}..."
      object_type_file = "./app/graph/types/#{model.name.underscore}_type.rb"
      attr_composed = {}

      attributes.each do |attribute|
        attr_composed[attribute] = { :type => attribute_types[attribute], :property => attribute_properties[attribute] }
      end

      put_object_type.call(object_type_file, model, attr_composed)

      # Todo
      # 2. Generate input types
      # 3. Generate generic mutations
      # 4. Generate generic resolvers (if using graphql-rails-resolver)

    end

    # Generate root type for query root
    root_type_name = nil
    STDOUT.puts "Define the root type to expose your object types: (letters only) (default = \e[32m#{root_type_name}\e[0m)"
    command = STDIN.gets.chomp.downcase
    while root_type_name.nil?
      if command.empty?
        root_type_name = "Viewer"
      else
        unless str[/[a-zA-Z]+/] == command
          STDOUT.puts "Root type name must contain only letters. No numbers or special characters."
          next
        end

        if models.map(&:name).include?(command)
          STDOUT.puts "Root type name must not be an existing model."
          next
        end

        root_type_name = command.classify
      end
    end

    # Generate root object type with every model
    Object.const_set(root_type_name, Class.new { def name() root_type_name end  })

    root_type_attr = model.map do |model|
      key = model.name.pluralize

      if name_format == :camel
        key = key.camelize(:lower)
      else
        key = key.underscore
      end

      association = Class.new {
          def klass() model end
          def macro() :has_many end
          def plural_name() key end
      }

      { :type => :id, :association => association}
    end

    root_object_type_file = "./app/graph/types/#{root_type_name.underscore}_type.rb"
    put_object_type.call(root_object_type_file, root_type_name.constantize, root_type_attr)

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


  end

end
