require 'azure'
require 'fluent/plugin/upload_service'
require 'zlib'
require 'time'
require 'tempfile'
require 'fluent/plugin/output'

module Fluent::Plugin
  class AzureStorageOutput < Fluent::Plugin::Output
    Fluent::Plugin.register_output('azurestorage', self)

    helpers :compat_parameters, :formatter, :inject

    def initialize
      super

      @compressor = nil
    end

    config_param :path, :string, :default => ""
    config_param :azure_storage_account, :string, :default => nil
    config_param :azure_storage_access_key, :string, :default => nil, :secret => true
    config_param :azure_container, :string, :default => nil
    config_param :azure_storage_type, :string, :default => "blob"
    config_param :azure_object_key_format, :string, :default => "%{path}%{time_slice}_%{index}.%{file_extension}"
    config_param :store_as, :string, :default => "gzip"
    config_param :auto_create_container, :bool, :default => true
    config_param :format, :string, :default => "out_file"
    config_param :command_parameter, :string, :default => nil

    DEFAULT_FORMAT_TYPE = "out_file"

    config_section :format do
      config_set_default :@type, DEFAULT_FORMAT_TYPE
    end

    config_section :buffer do
      config_set_default :chunk_keys, ['time']
      config_set_default :timekey, (60 * 60 * 24)
    end

    attr_reader :bs

    def configure(conf)
      compat_parameters_convert(conf, :buffer, :formatter, :inject)
      super

      begin
        @compressor = COMPRESSOR_REGISTRY.lookup(@store_as).new(:buffer_type => @buffer_type, :log => log)
      rescue => e
        log.warn "#{@store_as} not found. Use 'text' instead"
        @compressor = TextCompressor.new
      end
      @compressor.configure(conf)

      @formatter = formatter_create

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

      @storage_type = case @azure_storage_type
                        when 'tables'
                          raise NotImplementedError
                        when 'queues'
                          raise NotImplementedError
                        else
                          'blob'
                      end
      # For backward compatibility
      # TODO: Remove time_slice_format when end of support compat_parameters
      @configured_time_slice_format = conf['time_slice_format']
    end

    def multi_workers_ready?
      true
    end

    def start
      super

      if (!@azure_storage_account.nil? && !@azure_storage_access_key.nil?)
        Azure.configure do |config|
          config.storage_account_name = @azure_storage_account
          config.storage_access_key   = @azure_storage_access_key
        end
      end
      @bs = Azure::Blob::BlobService.new
      @bs.extend UploadService

      ensure_container
    end

    def format(tag, time, record)
      r = inject_values_to_record(tag, time, record)
      @formatter.format(tag, time, r)
    end

    def write(chunk)
      i = 0
      metadata = chunk.metadata
      previous_path = nil
      time_slice_format = @configured_time_slice_format || timekey_to_timeformat(@buffer_config['timekey'])
      time_slice = if metadata.timekey.nil?
                     ''.freeze
                   else
                     Time.at(metadata.timekey).utc.strftime(time_slice_format)
                   end

      begin
        path = @path_slicer.call(@path)
        values_for_object_key = {
          "%{path}" => path,
          "%{time_slice}" => time_slice,
          "%{file_extension}" => @compressor.ext,
          "%{index}" => i,
          "%{hostname}" => Socket.gethostname,
          "%{uuid_flush}" => uuid_random
        }
        storage_path = @azure_object_key_format.gsub(%r(%{[^}]+}), values_for_object_key)
        storage_path = extract_placeholders(storage_path, metadata)
        if (i > 0) && (storage_path == previous_path)
          raise "duplicated path is generated. use %{index} in azure_object_key_format: path = #{storage_path}"
        end

        i += 1
        previous_path = storage_path
      end while blob_exists?(@azure_container, storage_path)

      tmp = Tempfile.new("azure-")
      begin
        @compressor.compress(chunk, tmp)
        tmp.close

        options = {}
        options[:content_type] = @compressor.content_type
        options[:container] = @azure_container
        options[:blob] = storage_path

        @bs.upload(tmp.path, options)
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

    def uuid_random
      require 'uuidtools'
      ::UUIDTools::UUID.random_create.to_s
    end

    # This is stolen from Fluentd
    def timekey_to_timeformat(timekey)
      case timekey
      when nil          then ''
      when 0...60       then '%Y%m%d%H%M%S' # 60 exclusive
      when 60...3600    then '%Y%m%d%H%M'
      when 3600...86400 then '%Y%m%d%H'
      else                   '%Y%m%d'
      end
    end

    class Compressor
      include Fluent::Configurable

      def initialize(opts = {})
        super()
        @buffer_type = opts[:buffer_type]
        @log = opts[:log]
      end

      attr_reader :buffer_type, :log

      def configure(conf)
        super
      end

      def ext
      end

      def content_type
      end

      def compress(chunk, tmp)
      end

      private

      def check_command(command, algo = nil)
        require 'open3'

        algo = command if algo.nil?
        begin
          Open3.capture3("#{command} -V")
        rescue Errno::ENOENT
          raise ConfigError, "'#{command}' utility must be in PATH for #{algo} compression"
        end
      end
    end

    class GzipCompressor < Compressor
      def ext
        'gz'.freeze
      end

      def content_type
        'application/x-gzip'.freeze
      end

      def compress(chunk, tmp)
        w = Zlib::GzipWriter.new(tmp)
        chunk.write_to(w)
        w.finish
      ensure
        w.finish rescue nil
      end
    end

    class TextCompressor < Compressor
      def ext
        'txt'.freeze
      end

      def content_type
        'text/plain'.freeze
      end

      def compress(chunk, tmp)
        chunk.write_to(tmp)
      end
    end

    class JsonCompressor < TextCompressor
      def ext
        'json'.freeze
      end

      def content_type
        'application/json'.freeze
      end
    end

    COMPRESSOR_REGISTRY = Fluent::Registry.new(:azurestorage_compressor_type, 'fluent/plugin/azurestorage_compressor_')
    {
        'gzip' => GzipCompressor,
        'json' => JsonCompressor,
        'text' => TextCompressor
    }.each { |name, compressor|
      COMPRESSOR_REGISTRY.register(name, compressor)
    }

    def self.register_compressor(name, compressor)
      COMPRESSOR_REGISTRY.register(name, compressor)
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
