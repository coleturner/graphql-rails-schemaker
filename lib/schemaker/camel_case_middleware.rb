class CamelCaseMiddleware
  def call(parent_type, parent_object, field_definition, field_args, query_context, next_middleware)
    next_middleware.call([parent_type, parent_object, field_definition, transform_arguments(field_args), query_context])
  end

  def transform_arguments(field_args)
    transformed_args = {}
    types = {}

    field_args.each_value do |arg_value|
      key = arg_value.key.to_s
      unless key == "clientMutationId"
        key = key.underscore
      end

      transformed_args[key] = transform_value(arg_value.value)
      types[key] = arg_value.definition
    end

    GraphQL::Query::Arguments.new(transformed_args, argument_definitions: types)
  end

  def transform_value(value)
    case value
      when Array
        value.map { |v| transform_value(v) }
      when Hash
        Hash[value.map { |k, v| [underscore_key(k), convert_hash_keys(v)] }]
      when GraphQL::Query::Arguments
        transform_arguments(value)
      else
        value
      end
  end

end
