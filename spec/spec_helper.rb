require 'serverspec'
require 'pathname'
require 'net/ssh'
require 'yaml'
require 'csv'
require 'serverspec-runner/util/hash'

ssh_opts_default = YAML.load_file(ENV['ssh_options'])
csv_path = ENV['result_csv']
explains = []
results = []

def get_example_desc(example_group, descriptions)

  descriptions << example_group[:description]
  return descriptions if example_group[:parent_example_group] == nil

  get_example_desc(example_group[:parent_example_group], descriptions)
end

RSpec.configure do |c|

  c.expose_current_running_example_as :example
  c.path = ENV['EXEC_PATH']

  run_path = c.files_to_run[0].split('/')

  speck_i = 0
  run_path.reverse.each_with_index do |r,i|
    if r == 'spec'
      speck_i = ((run_path.size - 1) - i)
    end
  end
  sliced = run_path.slice((speck_i + 1)..(run_path.size - 2))
  role_name = sliced.join('-')

  if ENV['ASK_SUDO_PASSWORD']
    require 'highline/import'
    c.sudo_password = ask("Enter sudo password: ") { |q| q.echo = false }
  else
    c.sudo_password = ENV['SUDO_PASSWORD']
  end

  set_property (YAML.load_file(ENV['platforms_tmp']))[ENV['TARGET_HOST'].to_sym]

  if ENV['TARGET_SSH_HOST'] !~ /localhost|127\.0\.0\.1/
    c.host = ENV['TARGET_SSH_HOST']
    options = Net::SSH::Config.for(c.host, files=["~/.ssh/config"])
    ssh_opts ||= ssh_opts_default
    property[:ssh_opts].each { |k, v| ssh_opts[k.to_sym] = v } if property[:ssh_opts]
    user    = options[:user] || ssh_opts[:user] || Etc.getlogin
    options.merge!(ssh_opts)
    set :ssh_options, options
    set :backend, :ssh
  else
    set :backend, :exec
  end

  prev_desc_hierarchy = nil

  c.before(:suite) do
    entity_host = (((ENV['TARGET_HOST'] != ENV['TARGET_SSH_HOST']) && (ENV['TARGET_SSH_HOST'] != nil)) ? "(#{ENV['TARGET_SSH_HOST']})" : "")
    puts "\e[33m"
    puts "### start [#{role_name}@#{ENV['TARGET_HOST']}] #{entity_host} serverspec... ###"
    print "\e[m"

    explains << "#{role_name}@#{ENV['TARGET_HOST']}#{entity_host}"
    results << ""
  end

  c.after(:each) do

    if ENV['explain'] == 'long'
      explains << "  " + example.metadata[:full_description] + (RSpec::Matchers.generated_description || '')
      results << (self.example.exception ? 'NG' : 'OK')
    else

      spacer = ''
      desc_hierarchy = get_example_desc(self.example.metadata[:example_group], []).reverse
      desc_hierarchy.each_with_index do |ex, i|
        spacer += '  '

        if prev_desc_hierarchy != nil && prev_desc_hierarchy.length > i && prev_desc_hierarchy[i] == desc_hierarchy[i]
        else
          explains << spacer + ex
          results << ''
        end
      end

      explains << spacer + '  ' + RSpec::Matchers.generated_description
      results << (self.example.exception ? 'NG' : 'OK')

      prev_desc_hierarchy = desc_hierarchy
    end
  end

  c.after(:suite) do
    CSV.open(csv_path, 'a') do |writer|
      explains.each_with_index do |v, i|
        writer << [v, results[i]]
      end
    end
  end
end
