# graphql-rails-schemaker
A rake task to interactively create a GraphQL Schema for Rails Models.

![See it in action](https://raw.githubusercontent.com/colepatrickturner/graphql-rails-schemaker/master/preview.png)

## Getting Started
- Add `graphql-rails-schemaker` to your Gemfile's `:development` section.
- Run `bundle install`
- Run `rails schemaker:generate`
- Follow the prompts until it is done generating schema.
- Report any bugs or inconsistencies to make this application better.

## Features
### Schema
- Object Types
- Enum Types
- Union Types
- Query Root
- Mutation Root

### Smart Generation
- Association detection between models
- Automatic field for one-to-one associations
- Prompts for "many" associations - choice between GraphQL List or Connections
- Detects if naming overlaps with models (prompts for renaming)
- Global Node Support (for Relay v1)
- Camel Case with Middleware (for JavaScript type :camelCase fields)
- Snake Case without middleware

### Word of Caution
**This project is meant to generate a basic schema to cover a wide variety of uses. It is not a magical cure-all for your application's needs.**

This tool is designed to facilitate setup of a GraphQL Schema in Rails 5 Application. It has not been tested in any prior verison of Rails. This task will not run it if detects a previous setup @ `./app/graph/schema.rb` It will overwrite any files in `./app/graph/` if no `schema.rb` exists.

It will create a "base" schema including object types and sub-type dependencies from all models existing in the Rails application. It has been designed to formulate a generic schema to fit a wide variety of applications with support for associations.

**Do not run this in production environments.**


# Todo
- Generate Enum and Union Types
- Add Input Type templates
- Add Mutation Type templates
- Integration with `graphql-rails-resolver` (if installed)

## Needs Help
The `object_type.rb` template is large and cumbersome. The Todo above is planned for action. If you would like to handle any of the above, please file a pull request and add your name to the credits list.


## Credits
Cole Turner (http://cole.codes/)
