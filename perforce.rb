require 'builder_error'

# Perforce source control implementation for CruiseControl.rb
class Perforce
  include CommandLine

  attr_accessor :port, :client_spec, :username, :password, :path, :p4path

  MAX_CHANGELISTS_TO_FETCH = 25
  
  def initialize(options = {})
    @port, @clientspec, @username, @password, @path, @p4path, @interactive = 
          options.delete(:port), options.delete(:clientspec), 
          options.delete(:user), options.delete(:password), 
          options.delete(:path), options.delete(:p4path),
          options.delete(:interactive)
    raise "don't know how to handle '#{options.keys.first}'" if options.length > 0
    @clientspec or raise 'P4 Clientspec not specified'
    @port or raise 'P4 Port not specified'
    @username or raise 'P4 username not specified'
    @password or raise 'P4 password not specified'
    @p4path or raise 'P4 depot path not specified'
  end

  def checkout(revision = nil, stdout = $stdout)
    options = ""
    options << "#{@p4path}@#{revision_number(revision)}" unless revision.nil?

    # need to read from command output, because otherwise tests break
    p4(:sync, options).each {|line| stdout.puts line.to_s }
  end
  
  def clean_checkout(revision = nil, stdout = $stdout)
    FileUtils.rm_rf(path)
    checkout(revision, stdout)
  end

  def latest_revision
    build_revision_from(p4(:changes, "-m 1 #{@p4path}").first)
  end
  
  def last_locally_known_revision
    return Revision.new(0) unless File.exist?(path)
    Revision.new(info.revision)
  end
  
  def up_to_date?(reasons = [], revision_number = last_locally_known_revision.number)
    result = true
    
    latest_revision = self.latest_revision()
    if latest_revision > Revision.new(revision_number)
      reasons << "New revision #{latest_revision.number} detected"
      reasons << revisions_since(revision_number)
      result = false
    end
    
    return result
  end
  
  # SYNC_PATTERN = /^(\/\/.+#\d+) - (\w+) .+$/
  def update(revision = nil)
    checkout(revision)
  #   sync_output = p4(:sync, revision.nil? ? "" : "#{@path}@#{revision_number(revision)}")
  #   synced_files = Array.new
  #   
  #   sync_output.each do |line|
  #   match = SYNC_PATTERN.match(line['data'])
  #   if match
  #     file, operation = match[1..2]
  #     synced_files << ChangesetEntry.new(operation, file)
  #   end
  # end.compact
  # 
  #   synced_files
  end
  
private
  
  # Execute a P4 command, and return an array of the resulting output lines
  # The array will contain a hash for each line out output
  def p4(operation, options = nil)
    p4cmd = "p4 -R -p #{@port} -c #{@clientspec} -u #{@username} " + password_args
    p4cmd << "#{operation.to_s}"
    p4cmd << " " << options if options
    
    p4_output = Array.new
    # puts p4cmd
    IO.popen(p4cmd, "rb") do |file|
      while not file.eof
        p4_output << Marshal.load(file)
      end
    end
    
    p4_output
  end
  
  def password_args
    (@password.blank?) ? "" : "-P #{@password} "
  end
  
  def info
    change1 = p4(:changes, "-m 1 #{@p4path}#have").first
    change2 = p4(:changes, "-m 1 #{@p4path}#head").first
    Perforce::Info.new(change1['change'].to_i, change2['change'].to_i, change2['user'])
  end
  
  def build_revision_from(change)
    return nil unless change
    
    changeset = change['change'].to_i
    
    # Build the array of changes
    changed_files = p4(:describe, "-s #{changeset}").first
    i = 0
    changesets = []
    while (changed_files["action#{i}"])
      changesets << ChangesetEntry.new(changed_files["action#{i}"], changed_files["depotFile#{i}"])
      i = i + 1
    end
    
    Revision.new(changeset, change['user'], Time.at(change['time'].to_i), change['desc'], changesets)
  end
  
  def revisions_since(revision_number)
    p4(:changes, "-m #{MAX_CHANGELISTS_TO_FETCH} #{@p4path}@#{revision_number},#head").collect do |change|
      build_revision_from(change)
    end
  end
  
  def revision_number(revision)
    revision.respond_to?(:number) ? revision.number : revision.to_i
  end
  
  Info = Struct.new :revision, :last_changed_revision, :last_changed_author
end
