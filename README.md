# graphql-rails-schemaker
A rake task to interactive create a GraphQL Schema for Rails Models.

# Word of Caution
This tool is designed to facilitate setup of a GraphQL Schema in Rails 5 Application. It has not been tested in any prior verison of Rails. This task will not run it if detects a previous setup @ `./app/graph/schema.rb` It will overwrite any files in `./app/graph/` if no `schema.rb` exists.

GraphQL Rails Schemaker is not a one-size-fits all solution. It will create a "base" schema including object types and sub-type dependencies from all models existing in the Rails application. It has been designed to formulate a generic schema to fit a wide variety of applications with support for associations.

**Do not run this in production environments.**


## Todo
- Generate Enum and Union Types
- Add Input Type templates
- Add Mutation Type templates
- Integration with `graphql-rails-resolver` (if installed)

## Needs Help
The `object_type.rb` template is large and cumbersome. The Todo above is planned for action. If you would like to handle any of the above, please file a pull request and add your name to the credits list.


# Credits
Cole Turner (http://cole.codes/)
