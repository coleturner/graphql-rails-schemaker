require 'erb'

class TemplateRenderer
  def self.empty_binding
    binding
  end

  def self.render_string(template_content, locals = {})
    b = empty_binding
    locals.each { |k, v| b.local_variable_set(k, v) }

    ERB.new(template_content, nil, '-').result(b)
  end

  def self.render(file, locals = {})
    path = File.join Graphql::Rails::Schemaker.root, file
    render_string(File.read(path), locals)
  end
end
