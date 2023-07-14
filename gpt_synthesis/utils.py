from jinja2 import Environment, FileSystemLoader, select_autoescape

jinja_environment = Environment(loader=FileSystemLoader('./'),
                  autoescape=select_autoescape(), trim_blocks=True, lstrip_blocks=True, line_comment_prefix='#')

def fill_template(template_file, prompt_parameter_values={}):
    template = jinja_environment.get_template(template_file)

    filled_prompt = template.render(**prompt_parameter_values)
    filled_prompt = '\n'.join([line.strip() for line in filled_prompt.split('\n')]) # remove whitespace at the beginning and end of each line
    return filled_prompt