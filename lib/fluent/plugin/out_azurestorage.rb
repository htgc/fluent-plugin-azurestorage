module Fluent
  require 'fluent/mixin/config_placeholders'

  class AzureStorageOutput < Fluent::TimeSlicedOutput
    Fluent::Plugin.register_output('azurestorage', self)

    def initialize
      super
      require 'azure'
      require 'zlib'
      require 'time'
      require 'tempfile'
      require 'open3'
    end

    config_param :path, :string, :default => ''
    config_param :azure_storage_account, :string, :default => nil
    config_param :azure_storage_access_key, :string, :default => nil
    config_param :azure_container, :string, :default => nil
    config_param :azure_storage_type, :string, :default => 'blob'
    config_param :azure_object_key_format, :string, :default => "%{path}%{time_slice}_%{index}.%{file_extension}"
    config_param :store_as, :string, :default => 'gzip'
    config_param :auto_create_container, :bool, :default => true
    config_param :format, :string, :default => 'out_file'
    config_param :command_parameter, :string, :default => nil

    include Fluent::Mixin::ConfigPlaceholders

    def placeholders
      [:percent]
    end

    def configure(conf)
      super

      @ext = case @store_as
             when 'gzip'
               'gz'
             when 'lzo'
               check_command('lzop', 'LZO')
               @command_parameter = '-qf1' if @command_parameter.nil?
               'lzo'
             when 'lzma2'
               check_command('xz', 'LZMA2')
               @command_paramter = '-qf0' if @command_parameter.nil?
               'xz'
             when 'json'
               'json'
             else
               'txt'
             end

      @storage_type = case @azure_storage_type
                      when 'tables'
                        raise NotImplementedError
                      when 'queues'
                        raise NotImplementedError
                      else
                        'blob'
                      end

      conf['format'] = @format
      @formatter = TextFormatter.create(conf)

      if @localtime
        @path_slicer = Proc.new {|path|
          Time.now.strftime(path)
        }
      else
        @path_slicer = Proc.new {|path|
          Time.now.utc.strftime(path)
        }
      end

      if @azure_container.nil?
        raise ConfigError, 'azure_container is needed'
      end
    end

    def start
      super

      if (!@azure_storage_account.nil? && !@azure_storage_access_key)
        Azure.configure do |config|
          config.storage_account_name = @azure_storage_account
          config.storage_access_key   = @azure_storage_access_key
        end
      end
      @bs = Azure::BlobService.new

      ensure_container
    end

    def format(tag, time, record)
      @formatter.format(tag, time, record)
    end

    def write(chunk)
      i = 0
      begin
        path = @path_slicer.call(@path)
        values_for_object_key = {
          'path' => path,
          'time_slice' => chunk.key,
          'file_extension' => @ext,
          'index' => i
        }
        storage_path = @azure_object_key_format.gsub(%r(%{[^}]+})) { |expr|
          values_for_object_key[expr[2...expr.size-1]]
        }
        i += 1
      end while blob_exists?(@azure_container, storage_path)
 
      tmp = Tempfile.new("azure-")
      begin
        case @store_as
        when 'gzip'
          w = Zlib::GzipWriter.new(tmp)
          chunk.write_to(w)
          w.close
        when 'lzo'
          w = Tempfile.new('chunk-tmp')
          chunk.write_to(w)
          w.close
          tmp.close
          system "lzop #{@command_parameter} -o #{tmp.path} #{w.path}"
        when 'lzma2'
          w = Tempfile.new('chunk-xz-tmp')
          chunk.write_to(w)
          w.close
          tmp.close
          system "xz #{@command_parameter} -c #{w.path} > #{tmp.path}"
        else
          chunk.write_to(tmp)
          tmp.close
        end
        content = File.open(tmp.path, 'rb') { |file| file.read }
        @bs.create_block_blob(@azure_container, storage_path, content)
      ensure
        tmp.close(true) rescue nil
        w.close rescue nil
        w.unlink rescue nil
      end
    end

    private
    def ensure_container
      if ! @bs.list_containers.find { |c| c.name == @azure_container }
        if @auto_create_container
          @bs.create_container(@azure_container)
        else
          raise "The specified container does not exist: container = #{@azure_container}"
        end
      end
    end

    def check_command(command, algo)
      begin
        Open3.capture3("#{command} -V")
      rescue Errno::ENOENT
        raise ConfigError, "'#{command}' utility must be in PATH for #{algo} compression"
      end
    end

    def blob_exists?(container, blob)
      begin
        @bs.get_blob_properties(container, blob)
        true
      rescue Azure::Core::Http::HTTPError => ex
        raise if ex.status_code != 404
        false
      rescue Exception => e
        raise e.message
      end
    end
  end
end
