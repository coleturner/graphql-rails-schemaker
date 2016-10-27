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
    mode =
      if File.exist? "./app/graph/schema.rb"
        :echo
      else
        :write
      end

    if mode == :echo
      STDOUT.puts "Another schema already exists. Switching to ECHO mode."
    else
      STDOUT.puts "Fresh run. Currently in WRITE mode."
    end

    # Determine whether to do snake case or camel case
    STDOUT.puts "\e[1mUse camelCase or snake_case? Enter (c/S).\e[0m"
    name_format =
      if STDIN.gets.chomp.downcase == 'c'
        :camel
      else
        :snake
      end

    STDOUT.puts "Using #{name_format == :camel ? 'camel case' : 'snake case'}"

    Rails.application.eager_load!
    models = ApplicationRecord.descendants.collect { |type| type }
    scalar_types = [:string, :integer, :float, :id, :boolean]

    models.each do |model|
      model.connection
      skipped = false
      STDOUT.puts
      STDOUT.puts "----------------------------------"
      STDOUT.puts "\e[1mGenerating schema for models: \e[32m#{model}\e[0m"
      attributes = []
      attribute_types = {}
      attribute_properties = {}

      model.column_names.each do |name|
        new_name = name_format == :camel ? name.camelize(:lower).to_sym : name.underscore.to_sym
        attributes.push(new_name)
        attribute_properties[new_name] = name
      end

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
        else
          STDOUT.puts "Unrecognized command #{command}"
        end

      end

      if skipped
        next
      end

      # Todo

      # 1. Generate object types
      # => Scalars
      # => Enum (from Rails)
      # => All else to strings

      # 2. Generate input types
      # 3. Generate generic mutations

      # 4. Advanced Mode
      # => Generate arguments for associations
      # => Generate arguments for scopes
      # => Generate resolvers



    end

  end

end
